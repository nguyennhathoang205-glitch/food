"""Mam com gia dinh - chup 1 mam nhieu mon, chia phan theo tung nguoi.

Chi chua logic (khong phu thuoc Flask) de de test. API nam o family_api.py.

Luong dung:
1. Chup anh ca mam -> Gemini tach tung MON rieng (ten, khoi luong, dinh duong
   cua ca dia). Day chi la UOC TINH nen nguoi dung duoc sua / xoa / them mon.
2. Khai bao nhung ai dang an: moi nguoi co "he so phan" (be 0.5, nguoi lon 1,
   nguoi an nhieu 1.5...) va co the KHONG AN mot so mon (vd me khong an ca).
3. Moi mon duoc chia cho nhung nguoi CO AN mon do, theo ti le he so phan.
   Tong phan cua moi nguoi = tong cac mon ho an.
4. Luu "phan cua toi" vao nhat ky (moi mon 1 dong).
"""

import io
import json
import re

from PIL import Image

MAX_DISHES = 12
MAX_MEMBERS = 8
MAX_NAME = 60
MAX_MEMBER_NAME = 30
MIN_WEIGHT, MAX_WEIGHT = 0.25, 3.0

DISH_PROMPT = """Day la anh chup 1 mam com / bua an gia dinh Viet Nam co NHIEU mon.
Hay tach thanh tung mon RIENG (khong gop lai, com trang tinh la 1 mon, nuoc cham
va rau song di kem thi bo qua tru khi chiem khoi luong dang ke).

Tra ve DUNG JSON, khong them chu nao khac:
{"dishes": [
  {"name_vi": "ten mon bang tieng Viet",
   "estimated_weight_g": khoi luong CA DIA/to/ chen do tren mam (so),
   "calories": tong kcal cua ca phan do (so),
   "protein_g": so, "fat_g": so, "carbs_g": so}
]}
Toi da 12 mon. Neu khong nhin thay mon an nao thi tra {"dishes": []}."""


# ------------------------------------------------------------------
# Anh -> danh sach mon
# ------------------------------------------------------------------

def prepare_image(raw_bytes, max_side=1600):
    """Bytes bat ky -> JPEG bytes (Gemini khong nhan application/octet-stream).
    Tra ve None neu khong phai anh."""
    try:
        image = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    except Exception:
        return None

    image.thumbnail((max_side, max_side))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def _number(value, low, high):
    if value in (None, ""):
        return None

    try:
        number = float(value)
    except (TypeError, ValueError):
        return None

    return number if low <= number <= high else None


def parse_gemini_dishes(text):
    """Chuoi tra ve cua Gemini -> list dict tho, hoac None neu khong doc duoc."""
    text = str(text or "").strip()
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.MULTILINE).strip()

    try:
        data = json.loads(text)
    except ValueError:
        return None

    dishes = data.get("dishes") if isinstance(data, dict) else data
    return dishes if isinstance(dishes, list) else None


def clean_dishes(raw):
    """Kiem tra danh sach mon (tu Gemini hoac tu app). Tra ve (list, loi).

    Mon thieu khoi luong hoac kcal bi bo (khong doan). dam/beo/bot co the None
    (nguoi dung them mon bang tay) -> danh dau macros_complete = False sau.
    """
    if not isinstance(raw, list):
        return None, "Danh sách món không hợp lệ."

    dishes = []

    for item in raw[:MAX_DISHES]:
        if not isinstance(item, dict):
            continue

        name = " ".join(str(item.get("name_vi") or item.get("name") or "").split())
        name = name[:MAX_NAME]
        grams = _number(
            item.get("estimated_weight_g", item.get("grams")), 1, 5000
        )
        calories = _number(item.get("calories"), 0, 5000)

        if len(name) < 2 or grams is None or calories is None:
            continue

        dishes.append({
            "name_vi": name,
            "grams": round(grams),
            "calories": round(calories, 1),
            "protein_g": _number(item.get("protein_g"), 0, 500),
            "fat_g": _number(item.get("fat_g"), 0, 500),
            "carbs_g": _number(item.get("carbs_g"), 0, 500),
        })

    return dishes, None


def analyze(image_bytes, ask_gemini):
    """ask_gemini(jpeg_bytes, prompt) -> text|None. Tra ve (dishes, loi)."""
    jpeg = prepare_image(image_bytes)

    if jpeg is None:
        return None, "Ảnh không hợp lệ."

    text = ask_gemini(jpeg, DISH_PROMPT)

    if text is None:
        return None, "AI chưa phân tích được ảnh (hết lượt hoặc lỗi). Thử lại sau hoặc thêm món bằng tay."

    raw = parse_gemini_dishes(text)

    if raw is None:
        return None, "AI trả về kết quả không đọc được, thử chụp lại."

    dishes, error = clean_dishes(raw)

    if error:
        return None, error

    if not dishes:
        return None, "Không nhận ra món nào trong ảnh. Hãy chụp rõ hơn hoặc thêm món bằng tay."

    return dishes, None


# ------------------------------------------------------------------
# Chia phan
# ------------------------------------------------------------------

def clean_members(raw, dish_count):
    """Tra ve (members, loi). Moi nguoi: name, weight, skip (chi so mon khong an),
    goal_kcal (muc tieu ngay, khong bat buoc)."""
    if not isinstance(raw, list) or not raw:
        return None, "Cần ít nhất 1 người ăn."

    if len(raw) > MAX_MEMBERS:
        return None, f"Tối đa {MAX_MEMBERS} người."

    members = []

    for i, item in enumerate(raw):
        if not isinstance(item, dict):
            return None, "Thông tin người ăn không hợp lệ."

        weight = _number(item.get("weight", 1), MIN_WEIGHT, MAX_WEIGHT)

        if weight is None:
            return None, f"Hệ số phần phải từ {MIN_WEIGHT} đến {MAX_WEIGHT}."

        skip = set()

        for index in item.get("skip") or []:
            try:
                index = int(index)
            except (TypeError, ValueError):
                continue

            if 0 <= index < dish_count:
                skip.add(index)

        name = " ".join(str(item.get("name") or "").split())[:MAX_MEMBER_NAME]

        members.append({
            "name": name or f"Người {i + 1}",
            "weight": weight,
            "skip": skip,
            "goal_kcal": _number(item.get("goal_kcal"), 500, 6000),
        })

    return members, None


def split(dishes, members):
    """Chia tung mon cho nhung nguoi CO AN mon do, theo ti le he so phan.

    Bao toan: tong phan cua moi nguoi = tong cac mon co nguoi an (mon ma ca nha
    deu khong an duoc dua vao "uneaten", khong tinh vao ai).
    """
    macros_complete = all(
        d["protein_g"] is not None and d["fat_g"] is not None
        and d["carbs_g"] is not None
        for d in dishes
    )

    result_members = [
        {"name": m["name"], "weight": m["weight"], "goal_kcal": m["goal_kcal"],
         "grams": 0.0, "calories": 0.0, "protein_g": 0.0, "fat_g": 0.0,
         "carbs_g": 0.0, "dishes": []}
        for m in members
    ]
    result_dishes = []
    total = {"grams": 0.0, "calories": 0.0, "protein_g": 0.0, "fat_g": 0.0,
             "carbs_g": 0.0}

    for d_index, dish in enumerate(dishes):
        eaters = [i for i, m in enumerate(members) if d_index not in m["skip"]]
        weight_sum = sum(members[i]["weight"] for i in eaters)

        result_dishes.append({
            "name_vi": dish["name_vi"], "grams": dish["grams"],
            "calories": dish["calories"], "eaten_by": eaters,
            "uneaten": not eaters,
        })

        if not eaters:
            continue

        parts = {
            "grams": dish["grams"], "calories": dish["calories"],
            "protein_g": dish["protein_g"] or 0.0,
            "fat_g": dish["fat_g"] or 0.0, "carbs_g": dish["carbs_g"] or 0.0,
        }

        for key, value in parts.items():
            total[key] += value

        for i in eaters:
            share = members[i]["weight"] / weight_sum
            row = result_members[i]
            piece = {k: v * share for k, v in parts.items()}

            for key, value in piece.items():
                row[key] += value

            row["dishes"].append({
                "name_vi": dish["name_vi"],
                **{k: round(v, 1) for k, v in piece.items()},
            })

    for row in result_members:
        for key in ("grams", "calories", "protein_g", "fat_g", "carbs_g"):
            row[key] = round(row[key], 1)

        goal = row["goal_kcal"]
        row["goal_percent"] = (
            round(row["calories"] / goal * 100) if goal else None
        )

    return {
        "dishes": result_dishes,
        "members": result_members,
        "total": {k: round(v, 1) for k, v in total.items()},
        "macros_complete": macros_complete,
    }


def compute(raw_dishes, raw_members):
    """Kiem tra + chia. Tra ve (ket_qua, loi)."""
    dishes, error = clean_dishes(raw_dishes)

    if error:
        return None, error

    if not dishes:
        return None, "Cần ít nhất 1 món."

    members, error = clean_members(raw_members, len(dishes))

    if error:
        return None, error

    return split(dishes, members), None


def log_member(supabase, user_key, meal_type, raw_dishes, raw_members, me_index):
    """Ghi PHAN CUA 1 NGUOI (me_index) vao nhat ky, moi mon 1 dong.
    Tra ve (danh_sach_dong_da_luu, loi, ma_http)."""
    meal_type = " ".join(str(meal_type or "").split())

    if not meal_type:
        return None, "Thiếu bữa ăn.", 400

    result, error = compute(raw_dishes, raw_members)

    if error:
        return None, error, 400

    try:
        me = result["members"][int(me_index)]
    except (TypeError, ValueError, IndexError):
        return None, "Không xác định được phần của bạn.", 400

    if not me["dishes"]:
        return None, "Bạn không ăn món nào trong mâm này.", 400

    rows = [
        {
            "user_key": user_key,
            "food_name": d["name_vi"],
            "meal_type": meal_type,
            "portion_g": max(int(round(d["grams"])), 10),
            "calories": d["calories"],
            "protein_g": d["protein_g"],
            "fat_g": d["fat_g"],
            "carbs_g": d["carbs_g"],
        }
        for d in me["dishes"]
    ]

    saved = supabase.table("meal_logs").insert(rows).execute()
    return {
        "meals": saved.data,
        "calories": me["calories"],
        "macros_complete": result["macros_complete"],
    }, None, 200