import os
import io
import re
import csv
import json
import time
import uuid
import base64

from flask import Flask, jsonify, request
from flask_cors import CORS
from dotenv import load_dotenv
from supabase import create_client, Client
from ultralytics import YOLO
from PIL import Image
from google import genai
from google.genai import types

import health as health_rules
import water as water_store
import auth as auth_store
import label_scan
import active_learning


# ============================================================
# CONFIG
# ============================================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

env_file = os.path.join(BASE_DIR, ".env")
if os.path.exists(env_file):
    load_dotenv(env_file)
else:
    load_dotenv()

app = Flask(__name__)
CORS(app)

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Thieu SUPABASE_URL hoac SUPABASE_KEY trong file .env"
    )

supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_KEY
)

auth_store.set_supabase_client(supabase)
health_rules.set_supabase_client(supabase)
water_store.set_supabase_client(supabase)

DEFAULT_USER_KEY = "demo-user"


# ============================================================
# YOLO
# ============================================================

# Uu tien model YOLO26 moi neu da train xong, khong thi dung YOLOv8 cu.
_yolo26_candidates = [
    os.path.join(BASE_DIR, "models", "food_detector_yolo26.pt"),
    "models/food_detector_yolo26.pt"
]
_v8_candidates = [
    os.path.join(BASE_DIR, "models", "food_detector.pt"),
    "models/food_detector.pt"
]

MODEL_PATH = next((p for p in _yolo26_candidates if os.path.exists(p)), None)
if not MODEL_PATH:
    MODEL_PATH = next((p for p in _v8_candidates if os.path.exists(p)), "models/food_detector.pt")

model = YOLO(MODEL_PATH)

print(f"Model do an: {MODEL_PATH}")

# Model YOLO thu 2 danh rieng cho trai cay. App co nut chuyen che do
# "Do an" / "Trai cay" (field "mode" gui kem trong /detect), moi che do chi
# dung dung model cua no. Neu chua train xong (chua co file) thi bo qua,
# server van chay binh thuong o che do do an.
_fruit_candidates = [
    os.path.join(BASE_DIR, "models", "fruit_detector.pt"),
    "models/fruit_detector.pt"
]
FRUIT_MODEL_PATH = next((p for p in _fruit_candidates if os.path.exists(p)), "models/fruit_detector.pt")

fruit_model = (
    YOLO(FRUIT_MODEL_PATH)
    if os.path.exists(FRUIT_MODEL_PATH)
    else None
)

# class_id cua model trai cay bat dau lai tu 0 nen se trung voi 68 mon an.
# Trong bang foods, cac dong trai cay luu voi id = FRUIT_ID_OFFSET + class_id
# (vd class 0 cua model trai cay -> id 1000) de khong can doi schema.
FRUIT_ID_OFFSET = 1000

MODE_FOOD = "food"
MODE_FRUIT = "fruit"
MODE_ALL = "all"


# ============================================================
# GEMINI (tro ly chat ho tro nguoi dung)
# ============================================================

GEMINI_API_KEYS_RAW = os.environ.get("GEMINI_API_KEY", "")
GEMINI_API_KEYS = [
    k.strip()
    for k in GEMINI_API_KEYS_RAW.split(",")
    if k.strip()
]

GEMINI_MODEL_NAME = "gemini-3.6-flash"

_gemini_key_index = 0


def get_gemini_client():
    if not GEMINI_API_KEYS:
        return None

    return genai.Client(
        api_key=GEMINI_API_KEYS[_gemini_key_index]
    )


def switch_gemini_key():
    global _gemini_key_index

    if _gemini_key_index < len(GEMINI_API_KEYS) - 1:
        _gemini_key_index += 1
        return True

    return False


CHAT_SYSTEM_PROMPT = """Ban la tro ly dinh duong than thien trong app "Food Scan" - ung dung
nhan dien mon an Viet Nam qua anh va tra ve thong tin dinh duong.

Nhiem vu cua ban:
- Tra loi cau hoi cua nguoi dung ve dinh duong, mon an Viet Nam, cach dung app.
- Neu nguoi dung vua scan 1 tam anh (thong tin se duoc cung cap ben duoi), hay dua vao
  ket qua do de tu van cu the (vd: mon nay co phu hop voi nguoi giam can khong, nen an
  them gi de can bang dinh duong...).
- Neu co thong tin ho so (chieu cao, can nang, muc tieu calo/ngay) hoac lich su bua an
  gan day, hay dung de ca nhan hoa cau tra loi.
- Tra loi NGAN GON, de hieu, bang tieng Viet, giong nhu dang nhan tin voi ban be.
- Neu cau hoi khong lien quan toi dinh duong/mon an/app, van tra loi lich su nhung
  huong nguoi dung quay lai chu de chinh cua app.
- Khong dua ra chan doan y te, chi goi y dinh duong thong thuong. Neu nguoi dung co
  van de suc khoe nghiem trong, khuyen ho gap bac si/chuyen gia dinh duong.

{context}
"""


# Dataset YOLO (VietFood68) chi co 68 mon co dinh, rat nhieu mon Viet khac
# (vd: Bun thit nuong) khong co trong danh sach nay nen YOLO se luon tra ve
# ten mon GAN GIONG NHAT trong 68 class, va con tach 1 to/mam thanh nhieu
# box roi goi moi box la 1 "mon" day du (vd tach rau/bun/nuoc cham cua 1 to
# bun cha thanh "Bun cha Ha Noi", "Mam chung"...) - rat de gay nham lan.
#
# De khac phuc ma khong can train lai model, dung Gemini Vision phan tich
# NGUYEN tam anh 1 lan duy nhat, tra ve ca: (1) ten mon an CHINH, (2) danh
# sach nguyen lieu/thanh phan nhin thay duoc, (3) uoc tinh dinh duong cho
# CA phan an trong anh. YOLO van chay de ve bounding box tren anh cho sinh
# dong, nhung khong con duoc dung de dat ten "thanh phan" hay tinh dinh
# duong nua vi khong dang tin cay o muc do nay.
DISH_ANALYSIS_PROMPT = """Day la anh chup 1 mam/to do an Viet Nam.

Hay phan tich va CHI tra ve 1 object JSON duy nhat (khong bao trong markdown
code block, khong giai thich gi them truoc/sau), dung CHINH XAC cau truc:

{
  "main_dish": "<ten mon>",
  "ingredients": ["<thanh phan>", "<thanh phan>"],
  "estimated_weight_g": <so nguyen>,
  "estimated_total": {
    "calories": <so nguyen>,
    "protein_g": <so thuc>,
    "fat_g": <so thuc>,
    "carbs_g": <so thuc>
  }
}

Yeu cau:
- CHI dua tren nhung gi THAT SU NHIN THAY trong anh. Tuyet doi khong doan
  mon an hay nguyen lieu khong xuat hien trong anh.
- "main_dish": ten tieng Viet co dau.
  + Neu anh la 1 mon (1 to, 1 dia): ten mon pho bien nhat nguoi Viet se goi.
  + Neu anh la mam com co nhieu mon rieng: ghi "Mam com" kem mon noi bat,
    vd "Mam com (ga luoc, canh, rau luoc)".
  + Neu anh chi co trai cay: ghi ten loai trai cay hoac "Dia trai cay".
  + Neu anh khong co do an: de null.
- "ingredients": 3-10 mon/thanh phan/loai trai cay NHIN THAY trong anh,
  moi phan tu la 1 cum tu ngan tieng Viet co dau.
- "estimated_weight_g": uoc tinh TONG KHOI LUONG do an trong anh (gam), dua
  vao kich thuoc dia/to/bat va muc do day cua do an (1 chen com day khoang
  200g, 1 to bun/pho khoang 500g, 1 dia com tam khoang 400g). So nguyen.
- "estimated_total": uoc tinh dinh duong cho TOAN BO luong do an trong anh
  (khong phai tren 100g); calories la so nguyen, con lai la so thuc don vi
  gam. Uoc tinh gan dung la duoc.
- Chi tra ve JSON thuan, khong them chu ```json hay bat ky dinh dang nao
  khac."""


def _is_quota_error(error_text):
    return "RESOURCE_EXHAUSTED" in error_text or "429" in error_text


def _is_temporary_error(error_text):
    # Loi tam thoi do Gemini dang qua tai, KHAC voi het quota - thu lai sau
    # vai giay thuong se thanh cong, khong can doi sang key khac.
    return "UNAVAILABLE" in error_text or "503" in error_text


def _parse_dish_analysis_json(raw_text):
    text = (raw_text or "").strip()

    # Phong truong hop Gemini van boc trong ```json ... ``` du da yeu cau
    # khong lam vay trong prompt.
    if text.startswith("```"):
        text = text.strip("`")

        if text.lower().startswith("json"):
            text = text[4:]

        text = text.strip()

    data = json.loads(text)

    main_dish = str(data.get("main_dish") or "").strip() or None

    ingredients_raw = data.get("ingredients") or []

    ingredients = [
        str(item).strip()
        for item in ingredients_raw
        if str(item).strip()
    ]

    total_raw = data.get("estimated_total") or {}

    estimated_total = {
        "calories": number_or_zero(total_raw.get("calories")),
        "protein_g": number_or_zero(total_raw.get("protein_g")),
        "fat_g": number_or_zero(total_raw.get("fat_g")),
        "carbs_g": number_or_zero(total_raw.get("carbs_g")),
    }

    return {
        "main_dish": main_dish,
        "ingredients": ingredients,
        "estimated_total": estimated_total,
        "estimated_weight_g": number_or_zero(data.get("estimated_weight_g")),
    }


def analyze_dish_with_gemini(
    image_bytes,
    mime_type="image/jpeg",
    mode=MODE_FOOD
):
    """
    Goi Gemini Vision 1 lan de lay ca ten mon chinh, danh sach nguyen lieu,
    va uoc tinh dinh duong cho ca phan an trong anh. Tra ve None neu Gemini
    chua cau hinh, het quota o tat ca key, hoac loi khong doc duoc JSON.
    O che do trai cay thi doi cau mo dau cua prompt cho dung ngu canh.
    """
    if not GEMINI_API_KEYS:
        return None

    prompt = DISH_ANALYSIS_PROMPT

    if mode == MODE_FRUIT:
        prompt = prompt.replace(
            "Day la anh chup 1 mam/to do an Viet Nam.",
            "Day la anh chup 1 hoac nhieu loai trai cay "
            "(coi ten loai trai cay chinh la \"main_dish\", "
            "\"ingredients\" la cac loai trai cay co trong anh)."
        )
    elif mode == MODE_ALL:
        prompt = prompt.replace(
            "Day la anh chup 1 mam/to do an Viet Nam.",
            "Day la anh chup bua an Viet Nam, co the gom ca mon an "
            "va trai cay (neu chi co trai cay thi coi loai trai cay "
            "chinh la \"main_dish\")."
        )

    last_error = None
    keys_tried = 0

    while keys_tried < len(GEMINI_API_KEYS):
        client = get_gemini_client()
        if client is None:
            break

        # Gemini qua tai (503) la loi tam thoi, thu lai vai lan tren CUNG
        # 1 key truoc khi bo cuoc voi key do (cho vai giay giua moi lan).
        retries_left = 3

        while retries_left > 0:
            try:
                response = client.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=[
                        types.Part.from_bytes(
                            data=image_bytes,
                            mime_type=mime_type
                        ),
                        prompt
                    ],
                    config={
                        "response_mime_type": "application/json"
                    }
                )

                return _parse_dish_analysis_json(response.text)

            except json.JSONDecodeError as e:
                last_error = f"JSON khong hop le: {e}"

                break

            except Exception as e:
                last_error = str(e)

                retries_left -= 1

                if _is_temporary_error(last_error) and retries_left > 0:
                    time.sleep(1.5)
                    continue

                break

        keys_tried += 1

        if not switch_gemini_key():
            break

    print(f"Khong phan tich duoc mon an qua Gemini: {last_error}")

    return None


# ============================================================
# FOODS CACHE
# ============================================================

_foods_cache = {}


def load_foods_cache():
    global _foods_cache

    try:
        response = (
            supabase
            .table("foods")
            .select("*")
            .execute()
        )

        _foods_cache = {
            int(str(row.get("id", 0))): dict(row)
            for row in (response.data or [])
            if isinstance(row, dict)
        }

        print(
            f"Da load {len(_foods_cache)} mon an vao cache."
        )

    except Exception as e:
        print(
            f"Khong load duoc foods cache: {e}"
        )

        _foods_cache = {}


load_foods_cache()


# ============================================================
# HELPERS
# ============================================================

def number_or_none(value):
    if value is None:
        return None

    try:
        return float(value)

    except (TypeError, ValueError):
        return None


def number_or_zero(value):
    try:
        return float(value or 0)

    except (TypeError, ValueError):
        return 0.0


# ============================================================
# HEALTH
# ============================================================

@app.route(
    "/health",
    methods=["GET"]
)
def health():
    return jsonify({
        "status": "ok",
        "message": "Backend is running"
    })


@app.route(
    "/health/db",
    methods=["GET"]
)
def health_db():
    try:
        response = (
            supabase
            .table("foods")
            .select("id")
            .limit(1)
            .execute()
        )

        return jsonify({
            "status": "ok",
            "message": "Supabase connected successfully",
            "sample_row_count": len(response.data)
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# ============================================================
# FOODS
# ============================================================

@app.route(
    "/foods/reload-cache",
    methods=["POST"]
)
def reload_foods_cache():
    load_foods_cache()

    return jsonify({
        "status": "ok",
        "message": (
            f"Da reload "
            f"{len(_foods_cache)} mon an"
        )
    })


@app.route(
    "/api/foods",
    methods=["GET"]
)
def get_foods():
    try:
        foods = []

        for class_id in sorted(
            _foods_cache.keys()
        ):
            food = _foods_cache[
                class_id
            ]

            foods.append({
                "id":
                    class_id,

                "name_vi":
                    food.get(
                        "name_vi",
                        f"Mon #{class_id}"
                    ),

                "name_en":
                    food.get(
                        "name_en",
                        ""
                    ),

                "category":
                    food.get(
                        "category"
                    ),

                "calories_per_100g":
                    number_or_zero(
                        food.get(
                            "calories_per_100g"
                        )
                    ),

                "protein_g":
                    number_or_zero(
                        food.get(
                            "protein_g"
                        )
                    ),

                "fat_g":
                    number_or_zero(
                        food.get(
                            "fat_g"
                        )
                    ),

                "carbs_g":
                    number_or_zero(
                        food.get(
                            "carbs_g"
                        )
                    )
            })

        return jsonify({
            "status": "ok",
            "foods": foods
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# ============================================================
# PROFILE
# ============================================================

@app.route(
    "/api/profile/<user_key>",
    methods=["GET"]
)
def get_profile(user_key):
    try:
        user_key = _bearer_uid() or user_key
        response = (
            supabase
            .table("profiles")
            .select("*")
            .eq(
                "user_key",
                user_key
            )
            .limit(1)
            .execute()
        )

        if response.data:
            return jsonify({
                "status": "ok",
                "profile":
                    response.data[0]
            })

        default_profile = {
            "user_key":
                user_key,

            "display_name":
                "Người dùng Food Scan",

            "height_cm":
                None,

            "weight_kg":
                None,

            "daily_goal":
                2000
        }

        created = (
            supabase
            .table("profiles")
            .insert(
                default_profile
            )
            .execute()
        )

        return jsonify({
            "status": "ok",
            "profile":
                created.data[0]
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route(
    "/api/profile/<user_key>",
    methods=["POST"]
)
def save_profile(user_key):
    try:
        user_key = _bearer_uid() or user_key
        data = request.get_json(
            silent=True
        ) or {}

        display_name = str(
            data.get(
                "display_name",
                "Người dùng Food Scan"
            )
        ).strip()

        if not display_name:
            display_name = (
                "Người dùng Food Scan"
            )

        daily_goal = number_or_zero(
            data.get(
                "daily_goal"
            )
        )

        if daily_goal <= 0:
            daily_goal = 2000

        profile_data = {
            "user_key":
                user_key,

            "display_name":
                display_name,

            "height_cm":
                number_or_none(
                    data.get(
                        "height_cm"
                    )
                ),

            "weight_kg":
                number_or_none(
                    data.get(
                        "weight_kg"
                    )
                ),

            "daily_goal":
                daily_goal
        }

        response = (
            supabase
            .table("profiles")
            .upsert(
                profile_data,
                on_conflict="user_key"
            )
            .execute()
        )

        return jsonify({
            "status": "ok",
            "profile":
                response.data[0]
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# ============================================================
# MEAL LOGS
# ============================================================

@app.route(
    "/api/meals/<user_key>",
    methods=["GET"]
)
def get_meals(user_key):
    try:
        user_key = _bearer_uid() or user_key
        response = (
            supabase
            .table("meal_logs")
            .select("*")
            .eq(
                "user_key",
                user_key
            )
            .order(
                "created_at",
                desc=True
            )
            .execute()
        )

        return jsonify({
            "status": "ok",
            "meals":
                response.data
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route(
    "/api/meals",
    methods=["POST"]
)
def create_meal():
    try:
        data = request.get_json(
            silent=True
        ) or {}

        food_name = str(
            data.get(
                "food_name",
                ""
            )
        ).strip()

        meal_type = str(
            data.get(
                "meal_type",
                ""
            )
        ).strip()

        if not food_name:
            return jsonify({
                "status": "error",
                "message":
                    "Thieu food_name"
            }), 400

        if not meal_type:
            return jsonify({
                "status": "error",
                "message":
                    "Thieu meal_type"
            }), 400

        try:
            portion_g = int(
                data.get(
                    "portion_g",
                    150
                )
            )

        except Exception:
            portion_g = 150

        if portion_g <= 0:
            portion_g = 150

        resolved_user_key = _bearer_uid() or data.get("user_key") or DEFAULT_USER_KEY

        meal_data = {
            "user_key":
                resolved_user_key,

            "food_name":
                food_name,

            "meal_type":
                meal_type,

            "portion_g":
                portion_g,

            "calories":
                number_or_zero(
                    data.get(
                        "calories"
                    )
                ),

            "protein_g":
                number_or_zero(
                    data.get(
                        "protein_g"
                    )
                ),

            "fat_g":
                number_or_zero(
                    data.get(
                        "fat_g"
                    )
                ),

            "carbs_g":
                number_or_zero(
                    data.get(
                        "carbs_g"
                    )
                )
        }

        response = (
            supabase
            .table("meal_logs")
            .insert(
                meal_data
            )
            .execute()
        )

        return jsonify({
            "status": "ok",
            "meal":
                response.data[0]
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route(
    "/api/meals/<int:meal_id>",
    methods=["DELETE"]
)
def delete_meal(meal_id):
    try:
        # Chi xoa bua an cua CHINH nguoi dang dang nhap (truoc day ai co
        # token cung xoa duoc bua an cua nguoi khac neu biet id).
        response = (
            supabase
            .table("meal_logs")
            .delete()
            .eq(
                "id",
                meal_id
            )
            .eq(
                "user_key",
                _bearer_uid()
            )
            .execute()
        )

        if not response.data:
            return jsonify({
                "status": "error",
                "message": "Khong tim thay bua an"
            }), 404

        return jsonify({
            "status": "ok",
            "message":
                "Da xoa bua an"
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route(
    "/api/meals/<int:meal_id>",
    methods=["PUT"]
)
def update_meal(meal_id):
    """Chinh sua khau phan / bua an / dinh duong cua mon da luu trong Nhat ky."""
    try:
        data = request.get_json(silent=True) or {}
        uid = _bearer_uid()

        update_payload = {}
        if "food_name" in data and str(data["food_name"]).strip():
            update_payload["food_name"] = str(data["food_name"]).strip()
        if "meal_type" in data and str(data["meal_type"]).strip():
            update_payload["meal_type"] = str(data["meal_type"]).strip()
        if "portion_g" in data:
            try:
                update_payload["portion_g"] = max(int(data["portion_g"]), 10)
            except Exception:
                pass
        for field in ("calories", "protein_g", "fat_g", "carbs_g"):
            if field in data:
                update_payload[field] = number_or_zero(data[field])

        if not update_payload:
            return jsonify({
                "status": "error",
                "message": "Khong co du lieu cap nhat"
            }), 400

        response = (
            supabase
            .table("meal_logs")
            .update(update_payload)
            .eq("id", meal_id)
            .eq("user_key", uid)
            .execute()
        )

        if not response.data:
            return jsonify({
                "status": "error",
                "message": "Khong tim thay bua an"
            }), 404

        return jsonify({
            "status": "ok",
            "meal": response.data[0]
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route(
    "/api/meals/parse-text",
    methods=["POST"]
)
def parse_meal_text():
    """
    Nhan text mieu ta bua an bang tieng Viet (vd: "trua nay an 1 to pho bo voi ly tra da")
    Goi Gemini de tach thanh danh sach mon an kem uoc tinh khoi luong va calo.
    Co co che tu dong fallback tu dien mon an neu Gemini het quota hoac gap loi.
    """
    try:
        data = request.get_json(silent=True) or {}
        text = str(data.get("text", "")).strip()
        meal_type = str(data.get("meal_type", "lunch")).strip()

        if not text:
            return jsonify({
                "status": "error",
                "message": "Thieu text mieu ta bua an"
            }), 400

        items = []
        gemini_client = get_gemini_client()
        if gemini_client:
            prompt = f"""Phan tich cau mieu ta bua an tieng Viet sau day: "{text}".
Tach ra tung mon an, uoc tinh so luong/khoi luong va dinh duong cho tung mon.
CHI tra ve 1 JSON array hop le (khong bao trong markdown block, khong them bat ky chu thich nao khac):
[
  {{
    "name_vi": "<ten mon tieng Viet co dau>",
    "quantity": "<1 to / 1 dia / 1 ly / 2 qua / 200g...>",
    "portion_g": <so nguyen khoi luong uoc tinh gam>,
    "calories": <so nguyen kcal>,
    "protein_g": <so thuc>,
    "fat_g": <so thuc>,
    "carbs_g": <so thuc>
  }}
]
"""
            try:
                response = gemini_client.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=prompt,
                )
                raw_text = response.text or ""
                if "```json" in raw_text:
                    raw_text = raw_text.split("```json")[1].split("```")[0].strip()
                elif "```" in raw_text:
                    raw_text = raw_text.split("```")[1].split("```")[0].strip()
                parsed = json.loads(raw_text.strip())
                if isinstance(parsed, list):
                    items = parsed
            except Exception as e:
                print(f"Loi goi Gemini parse meal: {e}")

        # Fallback neu Gemini khong tra ve ket qua
        if not items:
            lower_text = text.lower()
            fallback_foods = [
                ("phở bò", 480, 24, 12, 65, "1 tô", 500),
                ("phở gà", 420, 26, 10, 58, "1 tô", 500),
                ("cơm tấm", 620, 28, 22, 75, "1 đĩa", 400),
                ("bún bò", 520, 25, 16, 68, "1 tô", 500),
                ("bún chả", 560, 26, 18, 62, "1 suất", 450),
                ("bánh mì", 360, 14, 12, 48, "1 ổ", 180),
                ("trà đá", 5, 0, 0, 1, "1 ly", 250),
                ("cà phê sữa", 130, 2, 4, 22, "1 ly", 200),
                ("sữa chua", 100, 4, 3, 14, "1 hộp", 100),
                ("chuối", 90, 1, 0, 23, "1 quả", 100),
                ("trứng", 75, 6, 5, 1, "1 quả", 50),
            ]
            for name, cal, p, f, c, qty, g in fallback_foods:
                if name in lower_text:
                    items.append({
                        "name_vi": name.title(),
                        "quantity": qty,
                        "portion_g": g,
                        "calories": cal,
                        "protein_g": float(p),
                        "fat_g": float(f),
                        "carbs_g": float(c)
                    })
            if not items:
                items.append({
                    "name_vi": text[:40],
                    "quantity": "1 phần",
                    "portion_g": 200,
                    "calories": 250,
                    "protein_g": 10.0,
                    "fat_g": 8.0,
                    "carbs_g": 35.0
                })

        total_cal = sum(it.get("calories", 0) for it in items)
        total_p = sum(it.get("protein_g", 0.0) for it in items)
        total_f = sum(it.get("fat_g", 0.0) for it in items)
        total_c = sum(it.get("carbs_g", 0.0) for it in items)

        return jsonify({
            "status": "ok",
            "meal_type": meal_type,
            "items": items,
            "total": {
                "calories": round(total_cal),
                "protein_g": round(total_p, 1),
                "fat_g": round(total_f, 1),
                "carbs_g": round(total_c, 1)
            }
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# ============================================================
# AI FEEDBACK
# ============================================================

FEEDBACK_DIR = os.path.join(BASE_DIR, "dataset_feedback")
MAX_FEEDBACK_IMAGE_BYTES = 8 * 1024 * 1024


def _class_id_by_name(name):
    """Tim id trong bang foods theo ten tieng Viet (khong phan biet hoa thuong)."""
    key = (name or "").strip().lower()

    for food_id, food in _foods_cache.items():
        if str(food.get("name_vi") or "").strip().lower() == key:
            return food_id

    return None


def yolo_label_line(class_id, box, img_w, img_h):
    """Doi box pixel {x1,y1,x2,y2} thanh 1 dong nhan YOLO:
    "<class> <x_tam> <y_tam> <rong> <cao>" (chuan hoa 0-1).
    Tra ve None neu box khong hop le."""
    try:
        x1 = max(0.0, min(float(box["x1"]), img_w))
        y1 = max(0.0, min(float(box["y1"]), img_h))
        x2 = max(0.0, min(float(box["x2"]), img_w))
        y2 = max(0.0, min(float(box["y2"]), img_h))
    except (KeyError, TypeError, ValueError):
        return None

    if x2 <= x1 or y2 <= y1 or img_w <= 0 or img_h <= 0:
        return None

    return (
        f"{int(class_id)} "
        f"{(x1 + x2) / 2 / img_w:.6f} {(y1 + y2) / 2 / img_h:.6f} "
        f"{(x2 - x1) / img_w:.6f} {(y2 - y1) / img_h:.6f}"
    )


def _save_feedback_sample(image_base64, box, class_id, corrected_name, user_key):
    """Luu anh + nhan dinh dang YOLO vao dataset_feedback/ de train lai,
    dong thoi ghi 1 dong vao dataset_feedback/feedback.csv de doi chieu.
    Tra ve duong dan/URL anh."""
    if "," in image_base64:
        image_base64 = image_base64.split(",", 1)[1]

    img_bytes = base64.b64decode(image_base64)

    if len(img_bytes) > MAX_FEEDBACK_IMAGE_BYTES:
        raise ValueError("Anh qua lon")

    # Doc lai bang PIL giong /detect de toa do box khop voi kich thuoc anh
    image = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    img_w, img_h = image.size

    # Trai cay (id >= 1000) la model rieng -> tach thu muc, tru offset
    sub_dir = FEEDBACK_DIR
    label_class_id = class_id

    if class_id is not None and int(class_id) >= FRUIT_ID_OFFSET:
        sub_dir = os.path.join(FEEDBACK_DIR, "fruit")
        label_class_id = int(class_id) - FRUIT_ID_OFFSET

    img_dir = os.path.join(sub_dir, "images")
    lbl_dir = os.path.join(sub_dir, "labels")
    os.makedirs(img_dir, exist_ok=True)
    os.makedirs(lbl_dir, exist_ok=True)

    # user_key chi giu ky tu an toan -> khong the ghi file ra ngoai thu muc
    safe_user = re.sub(r"[^A-Za-z0-9_-]", "", str(user_key))[:32] or "user"
    file_id = f"fb_{time.strftime('%Y%m%d_%H%M%S')}_{safe_user}_{uuid.uuid4().hex[:6]}"

    image.save(os.path.join(img_dir, f"{file_id}.jpg"), format="JPEG", quality=92)

    # Mon chua co trong 68 class (khong co class_id) thi chi luu anh + ten
    # trong feedback.csv, chua tao nhan (can them class moi truoc khi train).
    line = (
        yolo_label_line(label_class_id, box, img_w, img_h)
        if label_class_id is not None else None
    )

    if line:
        with open(os.path.join(lbl_dir, f"{file_id}.txt"), "w", encoding="utf-8") as f:
            f.write(line + "\n")

    with open(os.path.join(FEEDBACK_DIR, "feedback.csv"), "a",
              newline="", encoding="utf-8") as f:
        csv.writer(f).writerow([
            file_id,
            "" if class_id is None else class_id,
            corrected_name,
            "yes" if line else "no",
        ])

    image_path = os.path.relpath(os.path.join(img_dir, f"{file_id}.jpg"), BASE_DIR)

    try:
        supabase.storage.from_("feedback").upload(
            f"{file_id}.jpg",
            img_bytes,
            file_options={"content-type": "image/jpeg", "upsert": "true"}
        )
        image_path = supabase.storage.from_("feedback").get_public_url(f"{file_id}.jpg") or image_path
    except Exception as ex:
        print(f"Supabase storage upload info: {ex}")

    return image_path

@app.route(
    "/api/feedback",
    methods=["POST"]
)
def create_feedback():
    try:
        data = request.get_json(
            silent=True
        ) or {}

        predicted_name = str(
            data.get(
                "predicted_name",
                ""
            )
        ).strip()

        corrected_name = str(
            data.get(
                "corrected_name",
                ""
            )
        ).strip()

        if not predicted_name:
            return jsonify({
                "status": "error",
                "message":
                    "Thieu predicted_name"
            }), 400

        if not corrected_name:
            return jsonify({
                "status": "error",
                "message":
                    "Thieu corrected_name"
            }), 400

        image_base64 = data.get("image_base64")
        bounding_box = data.get("bounding_box") or {}
        user_key = _current_user_key()
        corrected_class_id = data.get("corrected_class_id")

        if corrected_class_id is None:
            corrected_class_id = _class_id_by_name(corrected_name)

        image_path = None

        if image_base64:
            try:
                image_path = _save_feedback_sample(
                    image_base64, bounding_box,
                    corrected_class_id, corrected_name, user_key
                )
            except Exception as e:
                print(f"Loi luu anh feedback dataset: {e}")

        feedback_data = {
            "user_key":
                user_key,

            "predicted_class_id":
                data.get(
                    "predicted_class_id"
                ),

            "predicted_name":
                predicted_name,

            "predicted_confidence":
                number_or_zero(
                    data.get(
                        "predicted_confidence"
                    )
                ),

            "corrected_class_id":
                corrected_class_id,

            "corrected_name":
                corrected_name
        }

        try:
            response = (
                supabase
                .table(
                    "scan_feedback"
                )
                .insert(
                    feedback_data
                )
                .execute()
            )
            ret_data = response.data[0] if response.data else feedback_data
        except Exception:
            ret_data = feedback_data

        try:
            active_learning.export_feedback_to_yolo(_foods_cache)
        except Exception:
            pass

        return jsonify({
            "status": "ok",
            "message": "Da ghi nhan du lieu feedback kem anh vao dataset Active Learning",
            "image_saved": image_path is not None,
            "feedback": ret_data
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


# ============================================================
# DETECT
# ============================================================

@app.route(
    "/detect",
    methods=["POST"]
)
def detect():
    if "image" not in request.files:
        return jsonify({
            "status": "error",
            "message":
                "Thieu file 'image'"
        }), 400

    file = request.files[
        "image"
    ]

    image_bytes = file.read()

    image_mime_type = file.mimetype or "image/jpeg"

    # Che do quet: mac dinh "all" = quet CHUNG ca do an va trai cay tren
    # cung 1 anh (chay ca 2 model roi gop ket qua). Van ho tro "food" /
    # "fruit" neu muon chi quet 1 loai.
    scan_mode = (
        request.form.get("mode") or MODE_ALL
    ).strip().lower()

    if scan_mode == MODE_FRUIT:
        if fruit_model is None:
            return jsonify({
                "status": "error",
                "message":
                    "Chua co model trai cay "
                    f"({FRUIT_MODEL_PATH}). Hay train va dat file vao "
                    "thu muc models/ roi khoi dong lai server."
            }), 503

        active_models = [(fruit_model, FRUIT_ID_OFFSET)]
    elif scan_mode == MODE_FOOD:
        active_models = [(model, 0)]
    else:
        scan_mode = MODE_ALL
        active_models = [(model, 0)]

        if fruit_model is not None:
            active_models.append((fruit_model, FRUIT_ID_OFFSET))

    try:
        image = Image.open(
            io.BytesIO(
                image_bytes
            )
        ).convert(
            "RGB"
        )

    except Exception as e:
        return jsonify({
            "status": "error",
            "message":
                f"Anh khong hop le: {e}"
        }), 400

    # Anh gui cho Gemini: ma hoa lai thanh JPEG chuan. KHONG dung loai file
    # do client khai bao - Flutter gui "application/octet-stream" nen Gemini
    # khong doc duoc anh va tu bịa ket qua tu vi du trong prompt. Thu nho
    # con toi da 1024px cho nhanh va do ton quota.
    gemini_image = image.copy()
    gemini_image.thumbnail((1024, 1024))
    gemini_buffer = io.BytesIO()
    gemini_image.save(gemini_buffer, format="JPEG", quality=90)
    gemini_image_bytes = gemini_buffer.getvalue()

    # Chay tung model, gom tat ca box lai kem id_offset cua model do (de
    # tra dung dong trong bang foods: do an id 0-67, trai cay id 1000+).
    # Neu model mon an da nhan dien ro mon chinh (conf >= 0.55), loai bo cac
    # box trai cay conf thap (< 0.80) hoac nam de len dia do an (vd trung op la
    # hoac dua leo tren dia Com tam bi nham thanh Tao 45%).
    all_boxes = []
    food_xyxy = []

    try:
        for active_model, offset in active_models:
            min_conf = 0.55 if (offset == FRUIT_ID_OFFSET and scan_mode == MODE_ALL) else 0.40
            results = list(active_model.predict(
                image,
                conf=min_conf,
                verbose=False
            ))

            if results:
                boxes = getattr(results[0], "boxes", None)
                if boxes is not None:
                    for box in boxes:
                        b_conf = float(box.conf[0])
                        bx1, by1, bx2, by2 = box.xyxy[0].tolist()
                        if offset == 0:
                            all_boxes.append((box, offset))
                            if b_conf >= 0.55:
                                food_xyxy.append((bx1, by1, bx2, by2))
                        else:
                            if food_xyxy:
                                if b_conf < 0.80:
                                    continue
                                b_area = max(bx2 - bx1, 1.0) * max(by2 - by1, 1.0)
                                inside_dish = False
                                for fx1, fy1, fx2, fy2 in food_xyxy:
                                    ix1 = max(bx1, fx1)
                                    iy1 = max(by1, fy1)
                                    ix2 = min(bx2, fx2)
                                    iy2 = min(by2, fy2)
                                    inter = max(ix2 - ix1, 0.0) * max(iy2 - iy1, 0.0)
                                    if inter / b_area > 0.35:
                                        inside_dish = True
                                        break
                                if inside_dish:
                                    continue
                            all_boxes.append((box, offset))

    except Exception as e:
        return jsonify({
            "status": "error",
            "message":
                f"Loi YOLO: {e}"
        }), 500

    detections = []

    total = {
        "calories": 0.0,
        "protein_g": 0.0,
        "fat_g": 0.0,
        "carbs_g": 0.0
    }

    DEFAULT_PORTION_G = 150

    for box, id_offset in all_boxes:
        class_id = int(
            box.cls[0]
        )

        confidence = float(
            box.conf[0]
        )

        x1, y1, x2, y2 = (
            box.xyxy[0]
            .tolist()
        )

        food_info = (
            _foods_cache.get(
                class_id + id_offset
            )
        )

        if food_info:
            name_vi = (
                food_info[
                    "name_vi"
                ]
            )

            name_en = (
                food_info[
                    "name_en"
                ]
            )

            category = (
                food_info.get(
                    "category"
                )
            )

            # Khau phan uoc tinh theo dien tich bbox so voi ca anh: chiem
            # ~25% khung hinh = khau phan chuan 150g, ti le 0.5x - 2x.
            img_w, img_h = image.size
            area_frac = (
                max(x2 - x1, 0) * max(y2 - y1, 0)
            ) / float(max(img_w * img_h, 1))

            portion_g = round(
                DEFAULT_PORTION_G *
                min(max(area_frac / 0.25, 0.5), 2.0) / 5.0
            ) * 5

            factor = (
                portion_g /
                100.0
            )

            calories = round(
                number_or_zero(
                    food_info.get(
                        "calories_per_100g"
                    )
                ) *
                factor,
                1
            )

            protein = round(
                number_or_zero(
                    food_info.get(
                        "protein_g"
                    )
                ) *
                factor,
                1
            )

            fat = round(
                number_or_zero(
                    food_info.get(
                        "fat_g"
                    )
                ) *
                factor,
                1
            )

            carbs = round(
                number_or_zero(
                    food_info.get(
                        "carbs_g"
                    )
                ) *
                factor,
                1
            )

            total[
                "calories"
            ] += calories

            total[
                "protein_g"
            ] += protein

            total[
                "fat_g"
            ] += fat

            total[
                "carbs_g"
            ] += carbs

        else:
            name_vi = (
                f"Món chưa xác định "
                f"#{class_id}"
            )

            name_en = (
                f"class_{class_id:02d}"
            )

            category = None
            portion_g = None

            calories = None
            protein = None
            fat = None
            carbs = None

        detections.append({
            "class_id":
                class_id + id_offset,

            "name_vi":
                name_vi,

            "name_en":
                name_en,

            "category":
                category,

            "confidence":
                round(
                    confidence,
                    3
                ),

            "estimated_portion_g":
                portion_g,

            "nutrition": {
                "calories":
                    calories,

                "protein_g":
                    protein,

                "fat_g":
                    fat,

                "carbs_g":
                    carbs
            },

            "bounding_box": {
                "x1":
                    round(
                        x1,
                        1
                    ),

                "y1":
                    round(
                        y1,
                        1
                    ),

                "x2":
                    round(
                        x2,
                        1
                    ),

                "y2":
                    round(
                        y2,
                        1
                    )
            }
        })

    # Hoi Gemini Vision phan tich NGUYEN tam anh: ten mon CHINH, danh sach
    # nguyen lieu, va uoc tinh dinh duong cho ca phan an. Day la nguon tin
    # cay hon YOLO cho ca 3 thu nay, vi YOLO chi co 68 class co dinh va hay
    # tach 1 to/mam thanh nhieu "mon" rieng sai lech (xem comment o tren).
    gemini_analysis = analyze_dish_with_gemini(
        gemini_image_bytes,
        "image/jpeg",
        scan_mode
    )

    # YOLO van duoc dung lam fallback khi Gemini loi/het quota, va de ve
    # bounding box len anh cho sinh dong (field "detections" ben duoi).
    yolo_total = {
        "calories": round(total["calories"], 1),
        "protein_g": round(total["protein_g"], 1),
        "fat_g": round(total["fat_g"], 1),
        "carbs_g": round(total["carbs_g"], 1),
    }

    if gemini_analysis:
        main_dish = gemini_analysis["main_dish"]
        ingredients = gemini_analysis["ingredients"]
        gemini_total = gemini_analysis["estimated_total"]

        # Neu Gemini tra ve JSON hop le nhung estimated_total toan so 0
        # (vd model tu choi uoc tinh), van fallback ve tong YOLO cho co
        # con so hien thi thay vi 0 kcal gay hieu lam.
        has_real_total = any(
            gemini_total.get(key, 0) for key in
            ("calories", "protein_g", "fat_g", "carbs_g")
        )

        total_nutrition = gemini_total if has_real_total else yolo_total
        nutrition_source = "gemini" if has_real_total else "yolo"
    else:
        main_dish = None
        ingredients = []
        total_nutrition = yolo_total
        nutrition_source = "yolo"

    estimated_weight_g = (
        gemini_analysis.get("estimated_weight_g") if gemini_analysis else 0
    ) or sum(
        d["estimated_portion_g"] or 0 for d in detections
    )

    health_user_key = _current_user_key()
    user_health_profile = health_rules.load_profile(health_user_key)

    warning_names = [d["name_vi"] for d in detections]

    if main_dish:
        warning_names.append(main_dish)

    warnings = health_rules.check_warnings(
        user_health_profile,
        warning_names,
        ingredients,
        total_nutrition
    )

    pathology = health_rules.analyze_food_pathology(
        user_health_profile,
        {
            "product_name": " ".join(warning_names),
            "ingredients": ingredients,
            **total_nutrition,
        }
    )

    return jsonify({
        "status": "ok",

        "warnings":
            warnings,

        "disease_breakdown":
            pathology.get("disease_breakdown", []),

        "drug_interactions":
            pathology.get("drug_interactions", []),

        "estimated_weight_g":
            estimated_weight_g,

        "main_dish":
            main_dish,

        "ingredients":
            ingredients,

        "nutrition_source":
            nutrition_source,

        "mode":
            scan_mode,

        "num_detections":
            len(
                detections
            ),

        "detections":
            detections,

        "total_nutrition":
            total_nutrition
    })


# ============================================================
# HEALTH PROFILE (di ung / benh ly / thuoc / OCR ho so y te)
# ============================================================

@app.route("/api/health/scan-medical", methods=["POST"])
def scan_medical_endpoint():
    """Quet don thuoc hoac phieu xet nghiem mau qua Gemini Vision / mau lam sang."""
    data = request.get_json(silent=True) or {}
    sample_type = data.get("sample") or request.form.get("sample")

    image_bytes = None
    mime = "image/jpeg"

    if "image" in request.files:
        file = request.files["image"]
        try:
            med_image = Image.open(io.BytesIO(file.read())).convert("RGB")
            med_image.thumbnail((1600, 1600))
            buf = io.BytesIO()
            med_image.save(buf, format="JPEG", quality=92)
            image_bytes = buf.getvalue()
        except Exception as e:
            return jsonify({
                "status": "error",
                "message": f"Anh ho so y te khong hop le: {e}"
            }), 400
    elif not sample_type:
        sample_type = "blood_test"

    client = get_gemini_client() if GEMINI_API_KEYS else None
    result = health_rules.scan_medical_document(
        image_bytes=image_bytes,
        mime_type=mime,
        sample_type=sample_type,
        gemini_client=client,
    )
    return jsonify({
        "status": "ok",
        "medical_record": result,
    })


@app.route("/api/health/<user_key>", methods=["GET"])
def get_health_profile(user_key):
    user_key = _bearer_uid() or user_key
    return jsonify({
        "status": "ok",
        "health": health_rules.load_profile(user_key)
    })


@app.route("/api/health/<user_key>", methods=["PUT", "POST"])
def save_health_profile(user_key):
    user_key = _bearer_uid() or user_key
    data = request.get_json(silent=True) or {}

    saved = health_rules.save_profile(
        user_key,
        data.get("allergies") or [],
        data.get("conditions") or [],
        data.get("medications") if "medications" in data else None,
    )

    return jsonify({"status": "ok", "health": saved})


# ============================================================
# AUTH
# ============================================================

def _bearer_uid():
    header = request.headers.get("Authorization", "")

    if header.startswith("Bearer "):
        return auth_store.verify_token(header[7:].strip())

    return None


def _current_user_key():
    """User lay tu TOKEN, khong tin user_key client tu gui (neu khong ai
    cung doc duoc ho so suc khoe cua nguoi khac qua /chat, /api/suggest...).
    Chua dang nhap -> dung chung tai khoan demo."""
    return _bearer_uid() or DEFAULT_USER_KEY


_USER_SCOPED_PREFIXES = (
    "/api/profile/",
    "/api/meals/",
    "/api/water/",
    "/api/health/",
    "/api/report/weekly/",
    "/api/weight/",
)


@app.before_request
def require_auth():
    """Moi API theo user_key phai co token hop le va dung chu tai khoan."""
    if request.method == "OPTIONS":
        return None

    path = request.path

    # /api/meals/parse-text, /api/health/scan-medical va /api/meal-plan/weekly
    # trung tien to nhung KHONG phai API theo user_key -> kiem tra token chung.
    if path in (
        "/api/meals/parse-text",
        "/api/health/scan-medical",
        "/api/meal-plan/weekly",
    ):
        if not _bearer_uid():
            return jsonify({
                "status": "error",
                "message": "Chua dang nhap"
            }), 401
        return None

    for prefix in _USER_SCOPED_PREFIXES:
        if path.startswith(prefix):
            uid = _bearer_uid()

            if not uid:
                return jsonify({
                    "status": "error",
                    "message": "Chua dang nhap"
                }), 401

            key = path[len(prefix):]

            # DELETE/PUT /api/meals/<id> dung id bua an, khong phai user_key.
            is_meal_by_id = (
                prefix == "/api/meals/" and request.method in ("DELETE", "PUT")
            )

            if not is_meal_by_id and key not in (uid, DEFAULT_USER_KEY):
                return jsonify({
                    "status": "error",
                    "message": "Khong co quyen"
                }), 403

            return None

    if path == "/api/meals" and request.method == "POST":
        uid = _bearer_uid()
        body = request.get_json(silent=True) or {}
        body_key = body.get("user_key")

        if not uid or (body_key and body_key not in (uid, DEFAULT_USER_KEY)):
            return jsonify({
                "status": "error",
                "message": "Chua dang nhap"
            }), 401

    return None


@app.route("/api/auth/register", methods=["POST"])
def auth_register():
    data = request.get_json(silent=True) or {}

    user, error = auth_store.register(
        data.get("email"), data.get("password"), data.get("name")
    )

    if error or not user:
        return jsonify({"status": "error", "message": error}), 400

    return jsonify({
        "status": "ok",
        "user": user,
        "token": auth_store.make_token(user["id"])
    })


@app.route("/api/auth/login", methods=["POST"])
def auth_login():
    data = request.get_json(silent=True) or {}

    user, error = auth_store.login(
        data.get("email"), data.get("password")
    )

    if error or not user:
        return jsonify({"status": "error", "message": error}), 401

    return jsonify({
        "status": "ok",
        "user": user,
        "token": auth_store.make_token(user["id"])
    })


@app.route("/api/auth/guest", methods=["POST"])
def auth_guest():
    """Dung thu khong can tai khoan - dung chung du lieu demo-user."""
    return jsonify({
        "status": "ok",
        "user": {
            "id": auth_store.GUEST_ID,
            "email": "",
            "name": "Khách"
        },
        "token": auth_store.make_token(auth_store.GUEST_ID)
    })


@app.route("/api/auth/me", methods=["GET"])
def auth_me():
    uid = _bearer_uid()

    if not uid:
        return jsonify({"status": "error", "message": "Het han"}), 401

    return jsonify({"status": "ok", "user_id": uid})


# ============================================================
# WATER + SUGGESTIONS
# ============================================================

@app.route("/api/water/<user_key>", methods=["GET"])
def get_water(user_key):
    user_key = _bearer_uid() or user_key
    return jsonify({
        "status": "ok",
        **water_store.get_water(user_key)
    })


@app.route("/api/water/<user_key>", methods=["POST"])
def add_water(user_key):
    user_key = _bearer_uid() or user_key
    data = request.get_json(silent=True) or {}

    try:
        ml = int(data.get("ml", 0))
    except Exception:
        ml = 0

    return jsonify({
        "status": "ok",
        **water_store.add_water(user_key, ml)
    })


@app.route("/api/suggest", methods=["GET"])
def suggest_foods():
    """Goi y mon con vua calo con lai trong ngay, uu tien nhieu dam,
    bo qua mon trung di ung cua nguoi dung."""
    user_key = _current_user_key()

    try:
        remaining = float(request.args.get("remaining", 600))
    except Exception:
        remaining = 600.0

    profile = health_rules.load_profile(user_key)
    portion = 150
    candidates = []

    for food in _foods_cache.values():
        factor = portion / 100.0
        kcal = number_or_zero(food.get("calories_per_100g")) * factor

        if kcal <= 0 or kcal > max(remaining, 120):
            continue

        item = {
            "name_vi": food.get("name_vi"),
            "category": food.get("category"),
            "portion_g": portion,
            "calories": round(kcal, 1),
            "protein_g": round(
                number_or_zero(food.get("protein_g")) * factor, 1),
            "fat_g": round(number_or_zero(food.get("fat_g")) * factor, 1),
            "carbs_g": round(
                number_or_zero(food.get("carbs_g")) * factor, 1),
        }

        warns = health_rules.check_warnings(
            profile, [item["name_vi"] or ""], [], item
        )

        if any(w["level"] == "red" for w in warns):
            continue

        item["score"] = item["protein_g"] / max(kcal, 1)
        candidates.append(item)

    candidates.sort(key=lambda x: x["score"], reverse=True)

    for c in candidates:
        c.pop("score", None)

    return jsonify({
        "status": "ok",
        "remaining": round(remaining),
        "suggestions": candidates[:6]
    })


# ============================================================
# STAGE 3: 7-DAY AI MEAL PLAN & WEEKLY CLINICAL REPORT
# ============================================================

@app.route("/api/meal-plan/weekly", methods=["POST", "GET"])
def weekly_meal_plan_endpoint():
    """Lap thuc don 7 ngay ca nhan hoa theo TDEE + Di ung + Benh ly + Thuoc."""
    user_key = _current_user_key()
    data = request.get_json(silent=True) or {}

    daily_goal = number_or_zero(data.get("daily_goal"))
    if daily_goal <= 0:
        try:
            p_res = (
                supabase.table("profiles")
                .select("daily_goal")
                .eq("user_key", user_key)
                .limit(1)
                .execute()
            )
            if p_res.data and isinstance(p_res.data[0], dict):
                daily_goal = number_or_zero(p_res.data[0].get("daily_goal"))
        except Exception:
            pass
    if daily_goal <= 0:
        daily_goal = 2000

    health_profile = health_rules.load_profile(user_key)
    plan = health_rules.generate_weekly_meal_plan(
        daily_goal=daily_goal,
        profile=health_profile,
    )
    return jsonify({
        "status": "ok",
        "plan": plan,
    })


@app.route("/api/report/weekly/<user_key>", methods=["GET"])
def weekly_report_endpoint(user_key):
    """Tong hop bao cao dinh duong & y te 7 ngay gan nhat cho nguoi dung."""
    from datetime import datetime, timedelta, timezone
    user_key = _bearer_uid() or user_key

    try:
        p_res = (
            supabase.table("profiles")
            .select("*")
            .eq("user_key", user_key)
            .limit(1)
            .execute()
        )
        user_prof = (
            dict(p_res.data[0])
            if p_res.data and isinstance(p_res.data[0], dict)
            else {}
        )
    except Exception:
        user_prof = {}

    daily_goal = number_or_zero(user_prof.get("daily_goal")) or 2000
    display_name = user_prof.get("display_name") or "Người dùng FoodScan AI"
    health_prof = health_rules.load_profile(user_key)
    water_info = water_store.get_water(user_key)

    now_utc = datetime.now(timezone.utc)
    cutoff = (now_utc - timedelta(days=7)).isoformat()

    try:
        m_res = (
            supabase.table("meal_logs")
            .select("*")
            .eq("user_key", user_key)
            .gte("created_at", cutoff)
            .order("created_at", desc=True)
            .execute()
        )
        meals = m_res.data or []
    except Exception:
        meals = []

    by_day = {}
    total_cal = 0.0
    total_pro = 0.0
    total_fat = 0.0
    total_carb = 0.0

    for m in meals:
        if not isinstance(m, dict):
            continue
        c = number_or_zero(m.get("calories"))
        p = number_or_zero(m.get("protein_g"))
        f = number_or_zero(m.get("fat_g"))
        cb = number_or_zero(m.get("carbs_g"))
        raw_dt = str(m.get("created_at") or "")[:10]
        if raw_dt:
            by_day[raw_dt] = by_day.get(raw_dt, 0.0) + c
        total_cal += c
        total_pro += p
        total_fat += f
        total_carb += cb

    logged_days = len([d for d, v in by_day.items() if v > 0])
    avg_cal = round(total_cal / logged_days, 1) if logged_days > 0 else 0.0
    avg_water = round(
        sum(int(h.get("ml") or 0) for h in (water_info.get("history") or [])) / 7.0
    )

    adherence_pct = (
        round((avg_cal / daily_goal) * 100, 1) if daily_goal > 0 and logged_days > 0 else 0.0
    )

    recommendations = []
    if logged_days == 0:
        recommendations.append("Chưa có nhật ký bữa ăn trong 7 ngày qua. Hãy bắt đầu quét món hoặc ghi nhanh bằng AI.")
    else:
        if avg_cal > daily_goal * 1.1:
            recommendations.append(
                f"Năng lượng trung bình ({avg_cal:.0f} kcal/ngày) đang vượt mục tiêu {daily_goal:.0f} kcal. Nên giảm 20% tinh bột vào bữa tối."
            )
        elif avg_cal < daily_goal * 0.75:
            recommendations.append(
                f"Năng lượng trung bình ({avg_cal:.0f} kcal/ngày) thấp hơn mục tiêu {daily_goal:.0f} kcal. Hãy bổ sung bữa phụ giàu đạm (sữa chua, hạt, ức gà)."
            )
        else:
            recommendations.append(
                f"Duy trì calo rất tốt ({avg_cal:.0f}/{daily_goal:.0f} kcal/ngày, đạt {adherence_pct}% mục tiêu)."
            )

    if avg_water < 1500:
        recommendations.append(
            f"Lượng nước trung bình ({avg_water} ml/ngày) còn thấp so với chuẩn 2000 ml. Hãy uống thêm 2-3 ly nước mỗi ngày."
        )
    if health_prof.get("conditions"):
        recommendations.append(
            "Lưu ý bệnh lý nền (" + ", ".join(health_prof["conditions"]) + "): tiếp tục duy trì kiểm tra bảng 6 bệnh lý trước khi ăn."
        )

    return jsonify({
        "status": "ok",
        "report": {
            "display_name": display_name,
            "generated_at": now_utc.strftime("%Y-%m-%d %H:%M UTC"),
            "daily_goal": round(daily_goal),
            "logged_days": logged_days,
            "total_meals_logged": len(meals),
            "total_calories": round(total_cal),
            "average_daily_calories": avg_cal,
            "adherence_percent": adherence_pct,
            "total_protein_g": round(total_pro, 1),
            "total_fat_g": round(total_fat, 1),
            "total_carbs_g": round(total_carb, 1),
            "average_water_ml": avg_water,
            "health_profile": health_prof,
            "recommendations": recommendations,
        },
    })


# ============================================================
# STAGE 4: WEIGHT TRAJECTORY FORECAST & ACTIVE LEARNING METRICS
# ============================================================

@app.route("/api/weight/<user_key>", methods=["GET"])
def get_weight_endpoint(user_key):
    """Lay lich su can nang va du bao xu huong 30 ngay."""
    from datetime import datetime, timedelta, timezone
    user_key = _bearer_uid() or user_key

    try:
        p_res = (
            supabase.table("profiles")
            .select("*")
            .eq("user_key", user_key)
            .limit(1)
            .execute()
        )
        prof = (
            dict(p_res.data[0])
            if p_res.data and isinstance(p_res.data[0], dict)
            else {}
        )
    except Exception:
        prof = {}

    current_w = number_or_none(prof.get("weight_kg"))
    daily_goal = number_or_zero(prof.get("daily_goal")) or 2000.0
    history = active_learning.get_weight_history(user_key, current_w)
    if history and current_w is None:
        current_w = number_or_none(history[-1].get("weight_kg"))

    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
    try:
        m_res = (
            supabase.table("meal_logs")
            .select("calories,created_at")
            .eq("user_key", user_key)
            .gte("created_at", cutoff)
            .execute()
        )
        meals = m_res.data or []
    except Exception:
        meals = []

    by_day: dict[str, float] = {}
    for m in meals:
        if not isinstance(m, dict):
            continue
        dt = str(m.get("created_at") or "")[:10]
        if dt:
            by_day[dt] = by_day.get(dt, 0.0) + number_or_zero(m.get("calories"))

    logged_days = len([d for d, v in by_day.items() if v > 0])
    avg_cal = (sum(by_day.values()) / logged_days) if logged_days > 0 else daily_goal

    forecast = active_learning.forecast_weight_30d(
        current_weight_kg=current_w,
        daily_goal_kcal=daily_goal,
        avg_consumed_kcal=avg_cal,
        logged_days=logged_days,
    )

    return jsonify({
        "status": "ok",
        "history": history,
        "forecast": forecast,
    })


@app.route("/api/weight/<user_key>", methods=["POST"])
def log_weight_endpoint(user_key):
    """Ghi nhan moc can nang moi va cap nhat luon ho so nguoi dung."""
    user_key = _bearer_uid() or user_key
    data = request.get_json(silent=True) or {}
    w = number_or_zero(data.get("weight_kg"))
    if w <= 20 or w >= 300:
        return jsonify({
            "status": "error",
            "message": "Can nang khong hop le (20 - 300 kg)"
        }), 400

    history = active_learning.log_weight(
        user_key=user_key,
        weight_kg=w,
        note=str(data.get("note") or ""),
    )

    try:
        supabase.table("profiles").update({"weight_kg": w}).eq("user_key", user_key).execute()
    except Exception:
        pass

    return jsonify({
        "status": "ok",
        "weight_kg": w,
        "history": history,
    })


@app.route("/api/ai/metrics", methods=["GET"])
def ai_metrics_endpoint():
    """Tra ve bang chi so thuc nghiem YOLO26 + trang thai Active Learning Dataset."""
    return jsonify({
        "status": "ok",
        "metrics": active_learning.get_ai_metrics(_foods_cache),
    })


# ============================================================
# CHAT (tro ly AI ho tro nguoi dung - nut tron noi trong app)
# ============================================================

@app.route(
    "/chat",
    methods=["POST"]
)
def chat():
    if not GEMINI_API_KEYS:
        return jsonify({
            "status": "error",
            "message":
                "Server chua cau hinh GEMINI_API_KEY"
        }), 500

    data = request.get_json(
        silent=True
    ) or {}

    user_message = str(
        data.get(
            "message",
            ""
        )
    ).strip()

    if not user_message:
        return jsonify({
            "status": "error",
            "message":
                "Thieu 'message'"
        }), 400

    history = data.get(
        "history"
    ) or []

    scan_context = data.get(
        "scan_context"
    )

    user_key = _current_user_key()

    # Gom ngu canh: ket qua scan gan nhat + ho so nguoi dung (neu co)
    context_parts = []

    if scan_context:
        try:
            total = scan_context.get(
                "total_nutrition", {}
            )

            items = scan_context.get(
                "detections", []
            )

            names = ", ".join(
                d.get("name_vi", "?")
                for d in items
            )

            context_parts.append(
                f"Nguoi dung vua scan 1 tam anh, phat hien cac mon: {names}. "
                f"Tong dinh duong uoc tinh: {total.get('calories', '?')} kcal, "
                f"{total.get('protein_g', '?')}g dam, {total.get('fat_g', '?')}g beo, "
                f"{total.get('carbs_g', '?')}g tinh bot."
            )

        except Exception:
            pass

    try:
        profile_response = (
            supabase
            .table("profiles")
            .select("*")
            .eq("user_key", user_key)
            .limit(1)
            .execute()
        )

        if profile_response.data and isinstance(profile_response.data[0], dict):
            profile = profile_response.data[0]

            context_parts.append(
                f"Ho so nguoi dung: chieu cao "
                f"{profile.get('height_cm') or 'chua ro'}cm, "
                f"can nang {profile.get('weight_kg') or 'chua ro'}kg, "
                f"muc tieu {profile.get('daily_goal') or 2000} kcal/ngay."
            )

    except Exception:
        pass

    try:
        hp = health_rules.load_profile(user_key)
        hp_bits = []
        if hp.get("allergies"):
            hp_bits.append("dị ứng: " + ", ".join(hp["allergies"]))
        if hp.get("conditions"):
            hp_bits.append("bệnh lý nền: " + ", ".join(hp["conditions"]))
        if hp.get("medications"):
            hp_bits.append("thuốc đang dùng: " + ", ".join(hp["medications"]))
        if hp_bits:
            context_parts.append("Hồ sơ y tế cá nhân: " + "; ".join(hp_bits) + ".")
    except Exception:
        pass

    context_text = (
        "\nNGU CANH:\n" + "\n".join(context_parts) + "\n"
        if context_parts
        else ""
    )

    system_text = CHAT_SYSTEM_PROMPT.format(
        context=context_text
    )

    contents = []

    for turn in history[-10:]:
        role = (
            "user"
            if turn.get("role") == "user"
            else "model"
        )

        text = turn.get("text", "")

        if text:
            contents.append({
                "role": role,
                "parts": [{"text": text}]
            })

    contents.append({
        "role": "user",
        "parts": [{"text": user_message}]
    })

    last_error = None
    keys_tried = 0

    while keys_tried < len(GEMINI_API_KEYS):
        client = get_gemini_client()
        if client is None:
            break

        retries_left = 3

        while retries_left > 0:
            try:
                response = client.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=contents,
                    config={
                        "system_instruction": system_text
                    }
                )

                return jsonify({
                    "status": "ok",
                    "reply": (response.text or "").strip()
                })

            except Exception as e:
                last_error = str(e)

                retries_left -= 1

                if _is_temporary_error(last_error) and retries_left > 0:
                    time.sleep(1.5)
                    continue

                break

        keys_tried += 1

        if not switch_gemini_key():
            break

    return jsonify({
        "status": "error",
        "message": f"Loi goi Gemini: {last_error}"
    }), 500



# ============================================================
# LABEL & BARCODE SCANNER
# ============================================================

@app.route("/api/scan-label", methods=["POST"])
def scan_label_endpoint():
    """Doc nhan dinh duong tren bao bi qua Gemini Vision."""
    if "image" not in request.files:
        return jsonify({
            "status": "error",
            "message": "Vui long chon anh nhan san pham"
        }), 400

    file = request.files["image"]

    # Giong /detect: Flutter gui "application/octet-stream" nen phai ma hoa
    # lai thanh JPEG that, neu khong Gemini doc sai/khong doc duoc anh.
    try:
        label_image = Image.open(io.BytesIO(file.read())).convert("RGB")
    except Exception as e:
        return jsonify({"status": "error", "message": f"Anh khong hop le: {e}"}), 400

    label_image.thumbnail((1600, 1600))  # giu du net de doc chu nho tren nhan
    buffer = io.BytesIO()
    label_image.save(buffer, format="JPEG", quality=92)
    image_bytes = buffer.getvalue()
    mime = "image/jpeg"
    user_key = _current_user_key()

    result = label_scan.scan_nutrition_label(image_bytes, mime_type=mime, user_key=user_key)
    return jsonify(result), (200 if result.get("status") == "ok" else 400)


@app.route("/api/barcode/<barcode>", methods=["GET"])
def barcode_endpoint(barcode):
    """Tra cuu ma vach san pham qua Open Food Facts."""
    user_key = _current_user_key()
    result = label_scan.lookup_barcode_with_health(barcode, user_key=user_key)
    return jsonify(result), (200 if result.get("status") == "ok" else 404)


# ============================================================
# EXERCISE TRACKER, FOOD COMPARISON & CSV EXPORT (PRO 4.0)
# ============================================================

@app.route("/api/exercise/<user_key>", methods=["GET"])
def get_exercise_endpoint(user_key):
    user_key = _bearer_uid() or user_key
    return jsonify({"status": "ok", **active_learning.get_today_exercise(user_key)})


@app.route("/api/exercise/<user_key>", methods=["POST"])
def log_exercise_endpoint(user_key):
    user_key = _bearer_uid() or user_key
    payload = request.get_json(silent=True) or {}
    act_name = str(payload.get("activity_name") or "Đi bộ nhanh").strip()
    burned = number_or_zero(payload.get("burned_kcal"))
    mins = int(number_or_zero(payload.get("minutes")) or 30)
    res = active_learning.log_exercise(user_key, act_name, burned, mins)
    return jsonify({"status": "ok", **res})


@app.route("/api/exercise/<user_key>", methods=["DELETE"])
def clear_exercise_endpoint(user_key):
    user_key = _bearer_uid() or user_key
    res = active_learning.clear_today_exercise(user_key)
    return jsonify({"status": "ok", **res})


@app.route("/api/foods/catalog", methods=["GET"])
def foods_catalog_endpoint():
    """Tra ve danh muc cac mon an de nguoi dung chon so sanh A vs B."""
    items = []
    for cid, info in _foods_cache.items():
        if not isinstance(info, dict):
            continue
        nut = info.get("nutrition") if isinstance(info.get("nutrition"), dict) else info
        portion = int(info.get("portion_g") or nut.get("portion_g") or 250)
        factor = portion / 100.0 if nut.get("calories") is None else 1.0
        cal = round(float(nut.get("calories") or (float(info.get("calories_per_100g") or 0) * factor)))
        if cal <= 0:
            continue
        items.append({
            "class_id": int(cid),
            "name_vi": str(info.get("name_vi") or f"Món #{cid}"),
            "calories": cal,
            "protein_g": round(float(nut.get("protein_g") or info.get("protein_g") or 0) * factor, 1),
            "fat_g": round(float(nut.get("fat_g") or info.get("fat_g") or 0) * factor, 1),
            "carbs_g": round(float(nut.get("carbs_g") or info.get("carbs_g") or 0) * factor, 1),
            "portion_g": portion,
        })
    items.sort(key=lambda x: x["name_vi"])
    return jsonify({"status": "ok", "foods": items})


@app.route("/api/foods/compare", methods=["POST"])
def foods_compare_endpoint():
    """So sanh truc dien 2 mon an theo dinh duong & benh ly ca nhan."""
    payload = request.get_json(silent=True) or {}
    user_key = _bearer_uid() or str(payload.get("user_key") or DEFAULT_USER_KEY)
    food_a_id = int(payload.get("food_a_id") or 0)
    food_b_id = int(payload.get("food_b_id") or 1)

    hp = health_rules.load_profile(user_key)
    conds = hp.get("conditions", []) if isinstance(hp, dict) else []
    alls = hp.get("allergies", []) if isinstance(hp, dict) else []

    res = active_learning.compare_two_foods(
        food_a_id=food_a_id,
        food_b_id=food_b_id,
        foods_cache=_foods_cache,
        user_conditions=conds,
        user_allergies=alls,
    )
    return jsonify({"status": "ok", **res})


@app.route("/api/export/meals-csv/<user_key>", methods=["GET"])
def export_meals_csv_endpoint(user_key):
    """Xuat lich su nhat ky an uong ra dinh dang CSV (ho tro tieng Viet Excel)."""
    user_key = _bearer_uid() or user_key

    try:
        res = (
            supabase.table("meal_logs")
            .select("*")
            .eq("user_key", user_key)
            .order("created_at", desc=True)
            .limit(200)
            .execute()
        )
        rows = res.data or []
    except Exception:
        rows = []

    lines = [
        "Ngày,Giờ,Bữa ăn,Tên món ăn,Khẩu phần (g),Calo (kcal),Đạm (g),Chất béo (g),Tinh bột (g)"
    ]
    total_cal = 0.0
    for r in rows:
        if not isinstance(r, dict):
            continue
        raw_dt = str(r.get("created_at") or "")
        date_part = raw_dt[:10] if len(raw_dt) >= 10 else "Hôm nay"
        time_part = raw_dt[11:16] if len(raw_dt) >= 16 else "12:00"
        meal_type = str(r.get("meal_type") or "Bữa chính").replace(",", " ")
        name = str(r.get("food_name") or r.get("name") or "Món ăn").replace(",", " - ").replace('"', "'")
        portion = int(number_or_zero(r.get("portion_g")) or 250)
        cal = round(number_or_zero(r.get("calories")), 0)
        pro = round(number_or_zero(r.get("protein_g")), 1)
        fat = round(number_or_zero(r.get("fat_g")), 1)
        carb = round(number_or_zero(r.get("carbs_g")), 1)
        total_cal += cal
        lines.append(
            f"{date_part},{time_part},{meal_type},\"{name}\",{portion},{cal:.0f},{pro},{fat},{carb}"
        )

    csv_text = "\n".join(lines)
    return jsonify({
        "status": "ok",
        "count": len(rows),
        "total_calories": round(total_cal),
        "filename": f"nhat_ky_dinh_duong_{user_key}.csv",
        "csv": csv_text,
    })



# ============================================================
# RUN
# ============================================================

if __name__ == "__main__":
    app.run(
        debug=False,
        use_reloader=False,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "5000"))
    )