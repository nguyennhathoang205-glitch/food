import os
import io
import re
import csv
import json
import time
import uuid
import base64
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from datetime import datetime, timedelta, timezone

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
import community_api
import recipes_api
import family_api
import chat_agent_api
import volume_3d


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
active_learning.set_supabase_client(supabase)
app.register_blueprint(volume_3d.bp)

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

GEMINI_MODEL_NAME = os.environ.get("GEMINI_MODEL", "gemini-3.8-flash").strip()

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


CHAT_SYSTEM_PROMPT = """Ban la tro ly dinh duong than thien trong app "FoodScan AI" - ung dung
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
- "estimated_weight_g": uoc tinh TONG KHOI LUONG phan an (gam) sat thuc te
  khau phan 1 nguoi Viet an:
  + 1 dia com tam / com suon / com ga tieu chuan: 350 - 400g (~600-680 kcal,
    30-35g dam, 20-25g beo, 65-75g carb).
  + 1 to pho / bun bo / bun rieu tieu chuan: 400 - 450g (~450-550 kcal,
    25-32g dam, 12-18g beo, 55-65g carb).
  + 1 o banh mi thit / trung: 180 - 220g (~380-450 kcal, 16-22g dam).
  KHONG phong dai khoi luong hay luong dam vuot qua khau phan 1 dia tieu chuan.
- "estimated_total": uoc tinh dinh duong cho TOAN BO luong do an trong anh
  (khong phai tren 100g); calories la so nguyen, con lai la so thuc don vi
  gam. Uoc tinh sat thuc te dinh duong Viet Nam.
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

    cal = number_or_zero(total_raw.get("calories"))
    pro = number_or_zero(total_raw.get("protein_g"))
    fat = number_or_zero(total_raw.get("fat_g"))
    carb = number_or_zero(total_raw.get("carbs_g"))
    weight_g = number_or_zero(data.get("estimated_weight_g"))

    # Hieu chinh (calibration) neu Gemini uoc tinh phong dai cho 1 dia/to don:
    # 1 dia com tam / bun / pho 1 nguoi an tieu chuan nam trong khoang 350-410g
    # (khong phai 550g hay 55g dam). Khi chon "Vua (100%)" tren app, <= 420g
    # se khop dung "1 to/dia tieu chuan".
    dish_lower = (main_dish or "").lower()
    is_multi_feast = any(k in dish_lower for k in ("mâm cơm", "mam com", "lẩu", "lau", "tiệc", "combo"))
    if not is_multi_feast:
        if weight_g > 410:
            scale_w = 380.0 / weight_g
            weight_g = 380
            if cal > 700:
                cal = round(cal * max(scale_w, 0.74))
                pro = round(pro * max(scale_w, 0.65), 1)
                fat = round(fat * max(scale_w, 0.68), 1)
                carb = round(carb * max(scale_w, 0.85), 1)
        if pro > 38 and cal < 900:
            pro = round(min(pro * 0.68, 36.0), 1)

    estimated_total = {
        "calories": round(cal),
        "protein_g": round(pro, 1),
        "fat_g": round(fat, 1),
        "carbs_g": round(carb, 1),
    }

    return {
        "main_dish": main_dish,
        "ingredients": ingredients,
        "estimated_total": estimated_total,
        "estimated_weight_g": round(weight_g),
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
    max_keys_per_request = min(len(GEMINI_API_KEYS), 2)
    models_to_try = []
    for _m in (GEMINI_MODEL_NAME, "gemini-3.8-flash", "gemini-2.5-flash"):
        if _m and _m not in models_to_try:
            models_to_try.append(_m)

    while keys_tried < max_keys_per_request:
        client = get_gemini_client()
        if client is None:
            break

        for candidate_model in models_to_try:
            try:
                response = client.models.generate_content(
                    model=candidate_model,
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
                if "NOT_FOUND" in last_error or "404" in last_error:
                    # Thu model fallback ngay tren cung key
                    continue
                if _is_temporary_error(last_error):
                    time.sleep(0.4)
                break

        keys_tried += 1

        if not switch_gemini_key():
            break

    print(f"Khong phan tich duoc mon an qua Gemini: {last_error}")

    return None


# Danh sach thanh phan mac dinh khi fallback sang YOLO (hoac khi Gemini khong
# tra ve ingredients) de nguoi dung luon xem duoc chi tiet tung thanh phan mon an.
_DEFAULT_DISH_INGREDIENTS = {
    "cơm tấm": [
        "Cơm tấm",
        "Sườn heo nướng",
        "Bì heo trộn thính",
        "Chả trứng hấp",
        "Trứng ốp la",
        "Đồ chua & dưa leo",
        "Mỡ hành & nước mắm",
    ],
    "phở": [
        "Bánh phở tươi",
        "Thịt bò / gà thái lát",
        "Nước dùng hầm xương",
        "Hành lá & ngò gai",
        "Giá đỗ & rau thơm",
    ],
    "bún bò": [
        "Bún sợi to",
        "Thịt bắp bò & giò heo",
        "Chả cua / chả bò",
        "Nước dùng sả ruốc",
        "Rau muống bào & bắp chuối",
    ],
    "bún chả": [
        "Bún tươi",
        "Chả thịt heo nướng",
        "Thịt ba chỉ nướng",
        "Đu đủ & cà rốt ngâm chua",
        "Nước mắm chua ngọt & rau sống",
    ],
    "bún thịt nướng": [
        "Bún tươi",
        "Thịt heo nướng sả",
        "Chả giò chiên",
        "Đậu phộng & mỡ hành",
        "Đồ chua, rau sống & nước mắm",
    ],
    "bún đậu": [
        "Bún lá ép",
        "Đậu hũ chiên giòn",
        "Thịt chân giò luộc",
        "Chả cốm & dồi sụn",
        "Rau kinh giới, tía tô & mắm tôm",
    ],
    "bún riêu": [
        "Bún tươi",
        "Riêu cua đồng & đậu hũ",
        "Cà chua & huyết/giò",
        "Nước dùng chua thanh",
        "Rau sống & hoa chuối",
    ],
    "bánh mì": [
        "Bánh mì vỏ giòn",
        "Thịt nguội / thịt nướng & chả lụa",
        "Pate gan & sốt bơ",
        "Đồ chua (cà rốt, củ cải)",
        "Dưa leo, ngò rí & ớt",
    ],
    "bánh xèo": [
        "Vỏ bánh bột gạo nghệ giòn",
        "Tôm tươi & thịt ba chỉ",
        "Giá đỗ & đậu xanh",
        "Rau cải, xà lách & rau thơm",
        "Nước mắm chua ngọt",
    ],
    "gỏi cuốn": [
        "Bánh tráng gạo",
        "Tôm luộc & thịt heo luộc",
        "Bún tươi",
        "Xà lách, hẹ & rau thơm",
        "Tương chấm / mắm nêm",
    ],
    "hủ tiếu": [
        "Sợi hủ tiếu dai",
        "Thịt heo, tôm & trứng cút",
        "Nước dùng ninh xương",
        "Giá đỗ, hẹ & hành phi",
    ],
    "mì quảng": [
        "Sợi mì Quảng nghệ",
        "Tôm, thịt heo / gà & trứng",
        "Nước nhân đậm đà",
        "Bánh đa nướng & đậu phộng",
        "Rau sống trà quế",
    ],
    "cơm gà": [
        "Cơm nấu nước luộc gà",
        "Thịt gà xé / gà quay",
        "Dưa leo & đồ chua",
        "Hành ngò & nước chấm gừng",
    ],
    "cơm chiên": [
        "Cơm rang trứng vàng",
        "Xúc xích / lạp xưởng / tôm thịt",
        "Đậu Hà Lan, cà rốt & bắp ngọt",
        "Hành lá & dưa leo ăn kèm",
    ],
    "bánh cuốn": [
        "Bánh cuốn bột gạo tráng mỏng",
        "Nhân thịt heo băm & mộc nhĩ",
        "Chả lụa & hành phi",
        "Giá trụng, rau thơm & nước mắm",
    ],
}


def infer_default_ingredients(dish_name, detections=None):
    """Suy luan danh sach thanh phan mon an khi Gemini chua tra ve."""
    low = (dish_name or "").lower()
    for key, items in _DEFAULT_DISH_INGREDIENTS.items():
        if key in low:
            return list(items)
    if detections:
        names = []
        for d in detections:
            n = str(d.get("name_vi") or "").strip()
            if n and n not in names:
                names.append(n)
            for key, items in _DEFAULT_DISH_INGREDIENTS.items():
                if key in n.lower():
                    return list(items)
        if len(names) > 1:
            return names
    if "bún" in low:
        return ["Bún tươi", "Thịt / Đạm chính", "Nước dùng / Nước chấm", "Rau sống & gia vị"]
    if "cơm" in low:
        return ["Cơm trắng", "Thịt / Đạm chính", "Rau củ & đồ chua", "Gia vị & nước chấm"]
    if "bánh" in low:
        return ["Phần bột bánh chính", "Nhân thịt / tôm / đậu", "Rau ăn kèm & nước chấm"]
    if dish_name:
        return [dish_name, "Nguyên liệu đạm & tinh bột", "Rau gia vị đi kèm"]
    return []


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


# Supabase luu created_at theo gio UTC. Neu cat chuoi [:10] de lay ngay thi bua
# an tu 0h-7h sang (gio Viet Nam) bi tinh vao NGAY HOM TRUOC -> phai doi mui gio.
VN_TZ = timezone(timedelta(hours=7))


def local_datetime(created_at):
    """Doi created_at (ISO, UTC) sang gio Viet Nam. Tra ve None neu khong doc duoc."""
    text = str(created_at or "").strip()

    if not text:
        return None

    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    return dt.astimezone(VN_TZ)


def local_day(created_at):
    """Ngay (YYYY-MM-DD) theo gio Viet Nam, "" neu khong doc duoc."""
    dt = local_datetime(created_at)
    return dt.strftime("%Y-%m-%d") if dt else ""


def jpeg_for_gemini(raw_bytes, max_side=1600):
    """Ma hoa lai anh thanh JPEG that truoc khi gui Gemini (Flutter gui
    "application/octet-stream", anh co the la PNG/HEIC). Tra ve None neu
    khong phai anh hop le."""
    try:
        image = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    except Exception:
        return None

    image.thumbnail((max_side, max_side))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=92)
    return buffer.getvalue()


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
# ROOT HEALTH CHECK & STATUS PAGE
# ============================================================

@app.route("/", methods=["GET"])
def index_status():
    return jsonify({
        "status": "ok",
        "service": "FoodScan AI Backend Server",
        "engine": "YOLO26s + Gemini 2.5 Flash + CLIP Few-shot + 3D Volume Estimation",
        "foods_loaded": len(_foods_cache),
        "endpoints": ["/detect", "/api/foods", "/api/scan/volume-3d", "/api/label/scan", "/api/barcode/<code_str>"],
    })


# ============================================================
# MEAL LOGS & THUMBNAIL STORE
# ============================================================

_MEAL_THUMBS_PATH = os.path.join(BASE_DIR, "meal_thumbs.json")


def _load_meal_thumbs():
    try:
        if os.path.exists(_MEAL_THUMBS_PATH):
            with open(_MEAL_THUMBS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
    except Exception:
        pass
    return {}


def _save_meal_thumb(meal_id, thumb_b64):
    if not meal_id or not thumb_b64:
        return
    try:
        thumbs = _load_meal_thumbs()
        thumbs[str(meal_id)] = str(thumb_b64)[:60000]
        # Giu toi da 300 anh thumbnail gan nhat de file nhe
        if len(thumbs) > 300:
            keys = list(thumbs.keys())[-300:]
            thumbs = {k: thumbs[k] for k in keys}
        with open(_MEAL_THUMBS_PATH, "w", encoding="utf-8") as f:
            json.dump(thumbs, f, ensure_ascii=False)
    except Exception:
        pass


def _attach_meal_thumbs(rows):
    if not rows:
        return rows
    thumbs = _load_meal_thumbs()
    if not thumbs:
        return rows
    out = []
    for r in rows:
        if isinstance(r, dict):
            item = dict(r)
            mid = str(item.get("id") or "")
            if mid and mid in thumbs and not item.get("thumb"):
                item["thumb"] = thumbs[mid]
            out.append(item)
        else:
            out.append(r)
    return out


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
                _attach_meal_thumbs(response.data or [])
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

        saved_meal = dict(response.data[0]) if response.data else dict(meal_data)
        thumb_b64 = data.get("thumb")
        if isinstance(thumb_b64, str) and thumb_b64.strip():
            _save_meal_thumb(saved_meal.get("id"), thumb_b64.strip())
            saved_meal["thumb"] = thumb_b64.strip()

        return jsonify({
            "status": "ok",
            "meal":
                saved_meal
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

        updated_row = _attach_meal_thumbs(response.data)[0]

        return jsonify({
            "status": "ok",
            "meal": updated_row
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

    local_rel_path = os.path.relpath(os.path.join(img_dir, f"{file_id}.jpg"), BASE_DIR)
    image_path = local_rel_path

    try:
        supabase.storage.from_("feedback").upload(
            f"{file_id}.jpg",
            img_bytes,
            file_options={"content-type": "image/jpeg", "upsert": "true"}
        )
        image_path = supabase.storage.from_("feedback").get_public_url(f"{file_id}.jpg") or image_path
    except Exception as ex:
        print(f"Supabase storage upload info: {ex}")

    return image_path, local_rel_path

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
        local_image_path = None

        if image_base64:
            try:
                image_path, local_image_path = _save_feedback_sample(
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
            try:
                response = (
                    supabase
                    .table("feedback_logs")
                    .insert({
                        "user_key": user_key,
                        "predicted_name": predicted_name,
                        "predicted_class_id": data.get("predicted_class_id"),
                        "actual_name": corrected_name,
                        "actual_class_id": corrected_class_id,
                        "confidence": number_or_zero(data.get("predicted_confidence")),
                        "bounding_box": bounding_box,
                        "image_filename": local_image_path or image_path,
                    })
                    .execute()
                )
                ret_data = response.data[0] if response.data else feedback_data
            except Exception:
                ret_data = feedback_data

        try:
            active_learning.record_feedback_entry(
                user_key=user_key,
                predicted_name=predicted_name,
                corrected_name=corrected_name,
                predicted_class_id=data.get("predicted_class_id"),
                corrected_class_id=corrected_class_id,
                confidence=number_or_zero(data.get("predicted_confidence")),
                bounding_box=bounding_box,
                image_path=local_image_path,
            )
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

    # Anh gui cho Gemini: thu nho con toi da 640px (quality 80) de upload
    # nhanh gấp 4 lần, va chay SONG SONG voi YOLO trong ThreadPoolExecutor.
    gemini_image = image.copy()
    gemini_image.thumbnail((640, 640))
    gemini_buffer = io.BytesIO()
    gemini_image.save(gemini_buffer, format="JPEG", quality=80)
    gemini_image_bytes = gemini_buffer.getvalue()

    gemini_executor = ThreadPoolExecutor(max_workers=1)
    gemini_future = gemini_executor.submit(
        analyze_dish_with_gemini,
        gemini_image_bytes,
        "image/jpeg",
        scan_mode,
    )

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

        # Neu o nguong conf=0.40 chua bat duoc box nao (anh chup hoi xa/nghieng
        # tren dien thoai), ha nguong xuong 0.05 va lay box co do tin cay cao nhat
        # de dam bao luon co ket qua fallback.
        if not all_boxes:
            low_results = list(model.predict(image, conf=0.05, verbose=False))
            if low_results and getattr(low_results[0], "boxes", None):
                best_box = max(low_results[0].boxes, key=lambda b: float(b.conf[0]), default=None)
                if best_box is not None:
                    all_boxes.append((best_box, 0))

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
                min(max(area_frac / 0.25, 0.6), 1.67) / 5.0
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

    # Lay ket qua Gemini Vision da chay song song voi YOLO. Neu YOLO da nhan
    # dien duoc mon an (detections khong rong), gioi han cho Gemini toi da 4.5s
    # de nguoi dung khong bao gio phai doi lau.
    gemini_timeout = 7.5 if detections else 10.0
    try:
        gemini_analysis = gemini_future.result(timeout=gemini_timeout)
    except (FuturesTimeoutError, Exception):
        gemini_analysis = None
    finally:
        gemini_executor.shutdown(wait=False)

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
        main_dish = detections[0]["name_vi"] if detections else None
        ingredients = []
        total_nutrition = yolo_total
        nutrition_source = "yolo"

    if not ingredients:
        fallback_dish_name = main_dish or (detections[0]["name_vi"] if detections else "")
        ingredients = infer_default_ingredients(fallback_dish_name, detections)

    # Mon do CONG DONG day (khong nam trong 68 lop YOLO). Chi chay CLIP khi
    # YOLO chua nhan dien chac chan (< 0.55) de tiet kiem ~1s CPU cho cac mon
    # quen thuoc nhu Pho, Com tam, Bun bo.
    best_yolo_conf = max((d["confidence"] for d in detections), default=0.0)
    community_match = (
        community_api.match_for_detect(image)
        if best_yolo_conf < 0.55
        else None
    )

    if community_match:
        if not main_dish and not detections:
            main_dish = community_match.get("name_vi")
        if total_nutrition.get("calories", 0) <= 0:
            c_kcal_100 = number_or_zero(community_match.get("calories_per_100g"))
            if c_kcal_100 > 0:
                factor = 3.0  # khau phan tieu chuan ~300g
                total_nutrition = {
                    "calories": round(c_kcal_100 * factor, 1),
                    "protein_g": round(number_or_zero(community_match.get("protein_g")) * factor, 1),
                    "fat_g": round(number_or_zero(community_match.get("fat_g")) * factor, 1),
                    "carbs_g": round(number_or_zero(community_match.get("carbs_g")) * factor, 1),
                }
                nutrition_source = "community_clip"

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

    dish_for_3d = main_dish or (detections[0]["name_vi"] if detections else "Món ăn")
    vol_3d = volume_3d.estimate_3d_volume(
        image=image,
        dish_name=dish_for_3d,
        ingredients=ingredients,
        total_nutrition=total_nutrition,
        detections=detections,
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

        "volume_3d":
            vol_3d,

        "main_dish":
            main_dish,

        "community_match":
            community_match,

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
        # Truoc day tu tra ve phieu xet nghiem MAU nhu the la ket qua that.
        return jsonify({
            "status": "error",
            "message": "Chưa có ảnh phiếu xét nghiệm"
        }), 400

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
    "/api/exercise/",
    "/api/export/meals-csv/",
)


@app.before_request
def require_auth():
    """Moi API theo user_key phai co token hop le va dung chu tai khoan."""
    if request.method == "OPTIONS":
        return None

    path = request.path

    # Cac API khong theo user_key tren duong dan nhung dung ho so suc khoe /
    # goi Gemini -> bat buoc dang nhap (truoc day compare/menu/fridge nhan
    # user_key tu client nen ai cung doc duoc ho so nguoi khac).
    if path in (
        "/api/meals/parse-text",
        "/api/health/scan-medical",
        "/api/meal-plan/weekly",
        "/api/foods/compare",
        "/api/menu/analyze",
        "/api/fridge/suggest",
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
        raw_dt = local_day(m.get("created_at"))
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
            "generated_at": now_utc.astimezone(VN_TZ).strftime("%d/%m/%Y %H:%M"),
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
        dt = local_day(m.get("created_at"))
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

def _chat_context_parts(user_key, scan_context):
    """Gom ngu canh cho chat: ket qua scan gan nhat + ho so + ho so y te.
    Dung chung cho /chat va /api/chat/agent."""
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

    return context_parts


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

    context_parts = _chat_context_parts(user_key, scan_context)

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
    act_name = str(payload.get("activity_name") or "Đi bộ").strip()
    burned = number_or_zero(payload.get("burned_kcal"))
    mins = int(number_or_zero(payload.get("minutes")) or 1)
    dist_km = float(number_or_zero(payload.get("distance_km")))
    steps = int(number_or_zero(payload.get("steps")))
    pace = str(payload.get("pace") or "").strip()
    dur_sec = int(number_or_zero(payload.get("duration_sec")))
    res = active_learning.log_exercise(
        user_key=user_key,
        activity_name=act_name,
        burned_kcal=burned,
        minutes=mins,
        distance_km=dist_km,
        steps=steps,
        pace=pace,
        duration_sec=dur_sec,
    )
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
    user_key = _current_user_key()
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
        local_dt = local_datetime(r.get("created_at"))
        date_part = local_dt.strftime("%Y-%m-%d") if local_dt else ""
        time_part = local_dt.strftime("%H:%M") if local_dt else ""
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


@app.route("/api/menu/analyze", methods=["POST"])
def analyze_menu_endpoint():
    """Quet anh Menu quan an hoac danh sach mon de goi y Top 3 mon nen goi & mon can tranh."""
    payload = request.get_json(silent=True) or {}
    user_key = _current_user_key()
    sample_type = str(payload.get("sample_type") or request.form.get("sample_type") or "com_van_phong")
    menu_text = str(payload.get("menu_text") or request.form.get("menu_text") or "").strip()
    daily_goal = number_or_zero(payload.get("daily_goal") or request.form.get("daily_goal")) or 2000.0

    # Neu nguoi dung chup anh to Menu va co Gemini Vision -> trich xuat ten mon tren menu
    gclient = get_gemini_client()
    if "image" in request.files and gclient is not None:
        try:
            f = request.files["image"]
            img_bytes = jpeg_for_gemini(f.read())
            if img_bytes:
                resp = gclient.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=[
                        genai.types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg"),
                        "Đọc ảnh thực đơn (menu) này và liệt kê tối đa 8 tên món ăn bằng tiếng Việt, mỗi món 1 dòng, không đánh số.",
                    ],
                )
                extracted = (resp.text or "").strip()
                if extracted:
                    menu_text = extracted
        except Exception:
            pass

    hp = health_rules.load_profile(user_key)
    conds = hp.get("conditions", []) if isinstance(hp, dict) else []
    alls = hp.get("allergies", []) if isinstance(hp, dict) else []

    res = active_learning.analyze_restaurant_menu(
        menu_text=menu_text,
        sample_type=sample_type,
        daily_goal=daily_goal,
        user_conditions=conds,
        user_allergies=alls,
    )
    return jsonify({"status": "ok", **res})


@app.route("/api/fridge/suggest", methods=["POST"])
def fridge_suggest_endpoint():
    """Goi y 3 mon Viet de nau tu nguyen lieu trong tu lanh + loc benh ly/di ung."""
    payload = request.get_json(silent=True) or {}
    user_key = _current_user_key()
    daily_goal = number_or_zero(payload.get("daily_goal") or request.form.get("daily_goal")) or 2000.0
    raw_ings = payload.get("ingredients") or request.form.get("ingredients")
    ingredients: list[str] = []
    if isinstance(raw_ings, list):
        ingredients = [str(x).strip() for x in raw_ings if str(x).strip()]
    elif isinstance(raw_ings, str) and raw_ings.strip():
        ingredients = [x.strip() for x in raw_ings.split(",") if x.strip()]

    # Neu nguoi dung chup anh tu lanh va co Gemini Vision -> nhan dien nguyen lieu
    gclient = get_gemini_client()
    if "image" in request.files and gclient is not None:
        try:
            f = request.files["image"]
            img_bytes = jpeg_for_gemini(f.read())
            if img_bytes:
                resp = gclient.models.generate_content(
                    model=GEMINI_MODEL_NAME,
                    contents=[
                        genai.types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg"),
                        "Liệt kê các nguyên liệu thực phẩm nhìn thấy trong ảnh này bằng tiếng Việt, cách nhau bởi dấu phẩy (ngắn gọn).",
                    ],
                )
                extracted = (resp.text or "").strip()
                if extracted:
                    ingredients.extend([x.strip() for x in extracted.split(",") if x.strip()])
        except Exception:
            pass

    hp = health_rules.load_profile(user_key)
    conds = hp.get("conditions", []) if isinstance(hp, dict) else []
    alls = hp.get("allergies", []) if isinstance(hp, dict) else []

    res = active_learning.suggest_fridge_recipes(
        ingredients=ingredients,
        daily_goal=daily_goal,
        user_conditions=conds,
        user_allergies=alls,
    )
    return jsonify({"status": "ok", **res})




# ============================================================
# CONG DONG DAY AI MON MOI (CLIP + pgvector) - xem community_api.py
# ============================================================

community_api.init(app, supabase, _bearer_uid)
recipes_api.init(app, supabase, _bearer_uid)   # cong thuc cong dong


# ============================================================
# MAM COM GIA DINH (tach mon bang Gemini, chia phan) - xem family_api.py
# ============================================================

def _gemini_call(contents, config=None):
    """Goi Gemini 1 lan voi `contents` bat ky, tra ve text hoac None.
    Xoay key + thu lai khi qua tai (dung chung cho mam com gia dinh va chat agent)."""
    if not GEMINI_API_KEYS:
        return None

    keys_tried = 0
    max_keys = min(len(GEMINI_API_KEYS), 2)
    models_to_try = []
    for _m in (GEMINI_MODEL_NAME, "gemini-3.8-flash", "gemini-2.5-flash"):
        if _m and _m not in models_to_try:
            models_to_try.append(_m)

    while keys_tried < max_keys:
        client = get_gemini_client()

        if client is None:
            break

        for candidate_model in models_to_try:
            try:
                response = client.models.generate_content(
                    model=candidate_model,
                    contents=contents,
                    config=config or {},
                )
                return response.text
            except Exception as e:
                err_str = str(e)
                if "NOT_FOUND" in err_str or "404" in err_str:
                    continue
                if _is_temporary_error(err_str):
                    time.sleep(0.4)
                print(f"[gemini] loi: {e}")
                break

        keys_tried += 1

        if not switch_gemini_key():
            break

    return None


def _ask_gemini_with_image(image_bytes, prompt):
    """Hoi Gemini voi 1 anh JPEG, tra ve text (JSON) hoac None."""
    return _gemini_call(
        [types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"), prompt],
        {"response_mime_type": "application/json"},
    )


def _ask_gemini_chat(contents, system_text):
    """Chat nhieu luot voi system prompt, tra ve JSON text hoac None."""
    return _gemini_call(
        contents,
        {"system_instruction": system_text,
         "response_mime_type": "application/json"},
    )


def _daily_goal_of(user_key):
    """Muc tieu kcal/ngay tu ho so (mac dinh 2000)."""
    try:
        rows = (
            supabase.table("profiles").select("daily_goal")
            .eq("user_key", user_key).limit(1).execute()
        ).data
        return number_or_zero(rows[0].get("daily_goal")) or 2000 if rows else 2000
    except Exception:
        return 2000


def _family_warnings(user_key, dish_names, nutrition):
    """Canh bao suc khoe (di ung / benh ly) cho phan an cua nguoi dang dang nhap."""
    profile = health_rules.load_profile(user_key)
    return health_rules.check_warnings(profile, dish_names, [], nutrition)


family_api.init(app, supabase, _bearer_uid, _ask_gemini_with_image, _family_warnings)
chat_agent_api.init(app, supabase, _bearer_uid, _ask_gemini_chat,
                     _chat_context_parts, _daily_goal_of)


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