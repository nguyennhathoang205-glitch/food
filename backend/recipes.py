"""Cong thuc cong dong - dang cong thuc, tu tinh dinh duong, an theo cong thuc.

Chi chua logic (khong phu thuoc Flask) de de test. API nam o recipes_api.py.

Y tuong:
1. Nguoi dung dang cong thuc gom nguyen lieu + so gram + so phan an.
2. Server tu tinh kcal / dam / beo / tinh bot cho ca mon va cho 1 phan.
   Nguyen lieu pho bien lay tu bang tham khao trong file nay; nguyen lieu la
   thi nguoi dung tu nhap so lieu /100g (khong doan bua).
3. Nhan ("Giau dam", "It beo"...) duoc TINH tu so lieu 1 phan, kem so cu the.
   Khong bao gio gan nhan kieu "An toan" / "Tot cho benh X".
4. "An theo cong thuc nay" ghi 1 dong vao nhat ky (meal_logs) nhu mon quet.
5. Neu co anh, ve thumbnail nho + (tuy chon) day AI nhan ra mon do bang
   community_foods.teach() - chi luu vector, khong luu anh goc to.
"""

import base64
import io
import re
import unicodedata

from PIL import Image

import community_foods

MAX_TITLE = 80
MAX_DESCRIPTION = 300
MAX_INGREDIENTS = 30
MAX_STEPS = 20
MAX_STEP_LENGTH = 500
MAX_SERVINGS = 20
MAX_GRAMS = 5000
MAX_IMAGES = 3
THUMB_SIDE = 320

# Nguong gan nhan - tinh tren 1 PHAN AN.
LOW_KCAL = 350
HIGH_KCAL = 700
HIGH_PROTEIN_G = 20
LOW_FAT_G = 8
HIGH_FAT_G = 25
LOW_CARBS_G = 20
HIGH_CARBS_G = 70

# Bang tham khao: ten -> (kcal, dam, beo, tinh bot) tren 100g.
# Cac mon tinh bot da nau (com, bun, khoai luoc) tinh theo khoi luong DA NAU;
# thit/ca/rau tinh theo khoi luong SONG. Chi la gia tri tham khao.
_REFERENCE = [
    (("cơm", "cơm trắng"), 130, 2.7, 0.3, 28),
    (("gạo",), 360, 7, 0.6, 79),
    (("bún", "bún tươi"), 110, 1.7, 0.1, 25),
    (("bánh phở", "phở"), 130, 2.5, 0.3, 29),
    (("bánh mì",), 265, 9, 3.2, 49),
    (("khoai lang",), 90, 2, 0.1, 21),
    (("khoai tây",), 77, 2, 0.1, 17),
    (("yến mạch",), 389, 17, 7, 66),
    (("bột mì",), 364, 10, 1, 76),
    (("thịt heo nạc", "thịt nạc", "nạc heo"), 143, 21, 6, 0),
    (("thịt ba chỉ", "ba chỉ", "ba rọi"), 518, 9.3, 53, 0),
    (("thịt heo", "thịt lợn"), 242, 17, 19, 0),
    (("thịt bò",), 150, 21, 7, 0),
    (("ức gà",), 120, 22.5, 2.6, 0),
    (("đùi gà",), 175, 17, 11, 0),
    (("cánh gà",), 203, 17.5, 14, 0),
    (("thịt gà", "gà ta"), 215, 18.6, 15.1, 0),
    (("trứng gà", "trứng"), 143, 12.6, 9.5, 0.7),
    (("trứng vịt",), 185, 12.8, 13.8, 1.5),
    (("tôm",), 85, 20, 0.5, 0),
    (("cá thu",), 205, 19, 14, 0),
    (("cá hồi",), 208, 20, 13, 0),
    (("cá",), 120, 20, 4, 0),
    (("mực",), 92, 15.6, 1.4, 3.1),
    (("đậu hũ", "đậu phụ", "tàu hũ"), 95, 10, 5.5, 1.5),
    (("rau muống",), 19, 2.6, 0.2, 3.1),
    (("rau cải", "cải thìa", "cải ngọt", "cải xanh"), 13, 1.5, 0.2, 2.2),
    (("cà chua",), 18, 0.9, 0.2, 3.9),
    (("dưa leo", "dưa chuột"), 15, 0.7, 0.1, 3.6),
    (("cà rốt",), 41, 0.9, 0.2, 9.6),
    (("hành tây",), 40, 1.1, 0.1, 9.3),
    (("bắp cải",), 25, 1.3, 0.1, 5.8),
    (("súp lơ", "bông cải"), 25, 1.9, 0.3, 5),
    (("nấm",), 22, 3.1, 0.3, 3.3),
    (("giá đỗ", "giá"), 30, 3, 0.2, 5.9),
    (("đậu que", "đậu cove"), 31, 1.8, 0.2, 7),
    (("bí đỏ",), 26, 1, 0.1, 6.5),
    (("bí xanh", "bí đao"), 13, 0.4, 0.2, 3),
    (("cà tím",), 25, 1, 0.2, 5.9),
    (("tỏi",), 149, 6.4, 0.5, 33),
    (("hành lá",), 32, 1.8, 0.2, 7.3),
    (("dầu ăn",), 884, 0, 100, 0),
    (("mỡ heo",), 902, 0, 100, 0),
    (("bơ lạt",), 717, 0.9, 81, 0.1),
    (("nước mắm",), 35, 5, 0, 3.6),
    (("đường",), 387, 0, 0, 100),
    (("sữa tươi",), 61, 3.2, 3.3, 4.8),
    (("sữa chua",), 61, 3.5, 3.3, 4.7),
    (("nước cốt dừa",), 197, 2, 21, 2.8),
    (("đậu phộng", "lạc"), 567, 26, 49, 16),
    (("chuối",), 89, 1.1, 0.3, 23),
    (("táo",), 52, 0.3, 0.2, 14),
    (("cam",), 47, 0.9, 0.1, 12),
    (("quả bơ", "trái bơ"), 160, 2, 15, 9),
]

_RADICAL = ("khô", "chiên", "rán", "giòn", "sấy", "xối mỡ")

_ALIASES = []   # (alias_chuan_hoa, (kcal, dam, beo, bot)), alias dai xep truoc

for _names, _k, _p, _f, _c in _REFERENCE:
    for _alias in _names:
        _ALIASES.append((community_foods.normalize_name(_alias), (_k, _p, _f, _c)))

_ALIASES.sort(key=lambda item: len(item[0]), reverse=True)


def lookup_reference(name):
    """Tim nguyen lieu trong bang tham khao. Khop CA CUM TU, uu tien cum dai
    nhat ("ức gà luộc" -> ức gà, "thịt heo nạc" khong bi nhan thanh "thịt heo").
    Tra ve (kcal, dam, beo, bot) /100g hoac None."""
    text = community_foods.normalize_name(name)

    # Che bien lam doi han mat do nang luong (tom kho, ca chien...) -> khong
    # doan theo nguyen lieu song, de nguoi dung tu nhap.
    if re.search(rf"(?<!\w)(?:{'|'.join(_RADICAL)})(?!\w)", text):
        return None

    for alias, values in _ALIASES:
        if re.search(rf"(?<!\w){re.escape(alias)}(?!\w)", text):
            return values

    return None


# ------------------------------------------------------------------
# Kiem tra dau vao + tinh dinh duong
# ------------------------------------------------------------------

def _number(value, low, high):
    """So trong [low, high] hoac None (rong / sai dinh dang / ngoai khoang)."""
    if value in (None, ""):
        return None

    try:
        number = float(value)
    except (TypeError, ValueError):
        return None

    return number if low <= number <= high else None


def parse_ingredients(raw):
    """Tra ve (danh_sach_sach, loi)."""
    if not isinstance(raw, list) or not raw:
        return None, "Cần ít nhất 1 nguyên liệu."

    if len(raw) > MAX_INGREDIENTS:
        return None, f"Tối đa {MAX_INGREDIENTS} nguyên liệu."

    cleaned = []

    for item in raw:
        if not isinstance(item, dict):
            return None, "Nguyên liệu không hợp lệ."

        name = " ".join(str(item.get("name") or "").split())[:60]
        grams = _number(item.get("grams"), 1, MAX_GRAMS)

        if len(name) < 2:
            return None, "Tên nguyên liệu quá ngắn."

        if grams is None:
            return None, f"Khối lượng của \"{name}\" phải từ 1 đến {MAX_GRAMS} g."

        custom = {
            "kcal": _number(item.get("kcal_per_100g"), 0, 900),
            "protein": _number(item.get("protein_per_100g"), 0, 100),
            "fat": _number(item.get("fat_per_100g"), 0, 100),
            "carbs": _number(item.get("carbs_per_100g"), 0, 100),
        }
        cleaned.append({"name": name, "grams": grams, "custom": custom})

    return cleaned, None


def compute_nutrition(ingredients, servings):
    """Tinh dinh duong tu danh sach da qua parse_ingredients().

    Tra ve dict co "unknown" = ten cac nguyen lieu chua co so lieu (khi do
    khong tinh duoc - phai de nguoi dung tu nhap, khong duoc doan).
    """
    rows = []
    unknown = []
    total = {"kcal": 0.0, "protein": 0.0, "fat": 0.0, "carbs": 0.0}
    total_grams = 0.0
    macros_complete = True

    for ing in ingredients:
        custom = ing["custom"]

        if custom["kcal"] is not None:
            # Nguoi dung tu nhap: chi tin so ho nhap. Thieu dam/beo/bot thi
            # danh dau "chua du" thay vi coi la 0.
            per100 = (
                custom["kcal"], custom["protein"], custom["fat"], custom["carbs"]
            )
            source = "user"
        else:
            ref = lookup_reference(ing["name"])

            if ref is None:
                unknown.append(ing["name"])
                continue

            per100 = ref
            source = "reference"

        factor = ing["grams"] / 100.0
        known_macros = all(v is not None for v in per100[1:])

        if not known_macros:
            macros_complete = False

        total["kcal"] += per100[0] * factor
        total["protein"] += (per100[1] or 0.0) * factor
        total["fat"] += (per100[2] or 0.0) * factor
        total["carbs"] += (per100[3] or 0.0) * factor
        total_grams += ing["grams"]

        rows.append({
            "name": ing["name"],
            "grams": ing["grams"],
            "kcal": round(per100[0] * factor),
            "source": source,
        })

    servings = max(int(servings), 1)

    def rounded(values, divisor=1):
        return {
            "kcal": round(values["kcal"] / divisor),
            "protein_g": round(values["protein"] / divisor, 1),
            "fat_g": round(values["fat"] / divisor, 1),
            "carbs_g": round(values["carbs"] / divisor, 1),
        }

    return {
        "ok": not unknown,
        "unknown": unknown,
        "ingredients": rows,
        "servings": servings,
        "total_grams": round(total_grams),
        "grams_per_serving": round(total_grams / servings),
        "total": rounded(total),
        "per_serving": rounded(total, servings),
        "macros_complete": macros_complete,
    }


def make_labels(per_serving, macros_complete=True):
    """Nhan TINH TU SO LIEU 1 phan, luon kem con so de nguoi xem tu danh gia.
    Tuyet doi khong tra ve nhan kieu 'an toan' hay 'tot cho benh X'."""
    labels = []
    kcal = per_serving["kcal"]

    if kcal <= LOW_KCAL:
        labels.append(f"Ít calo · {kcal} kcal/phần")
    elif kcal >= HIGH_KCAL:
        labels.append(f"Năng lượng cao · {kcal} kcal/phần")

    # Thieu so lieu dam/beo/bot thi khong gan nhan dua tren chung.
    if not macros_complete:
        return labels

    protein, fat, carbs = (
        per_serving["protein_g"], per_serving["fat_g"], per_serving["carbs_g"]
    )

    if protein >= HIGH_PROTEIN_G:
        labels.append(f"Giàu đạm · {protein:g} g/phần")

    if fat <= LOW_FAT_G:
        labels.append(f"Ít béo · {fat:g} g/phần")
    elif fat >= HIGH_FAT_G:
        labels.append(f"Nhiều béo · {fat:g} g/phần")

    if carbs <= LOW_CARBS_G:
        labels.append(f"Ít tinh bột · {carbs:g} g/phần")
    elif carbs >= HIGH_CARBS_G:
        labels.append(f"Nhiều tinh bột · {carbs:g} g/phần")

    return labels


# ------------------------------------------------------------------
# Anh
# ------------------------------------------------------------------

def make_thumbnail(image):
    """Anh PIL -> chuoi base64 JPEG nho (~10-20KB) de luu thang trong bang."""
    thumb = image.convert("RGB")
    thumb.thumbnail((THUMB_SIDE, THUMB_SIDE))
    buffer = io.BytesIO()
    thumb.save(buffer, format="JPEG", quality=72)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


# ------------------------------------------------------------------
# Doc / ghi Supabase
# ------------------------------------------------------------------

def _clean_steps(raw):
    if raw is None:
        return [], None

    if not isinstance(raw, list):
        return None, "Các bước làm không hợp lệ."

    steps = [" ".join(str(s or "").split())[:MAX_STEP_LENGTH] for s in raw]
    steps = [s for s in steps if s]

    if len(steps) > MAX_STEPS:
        return None, f"Tối đa {MAX_STEPS} bước."

    return steps, None


def preview(payload):
    """Tinh thu (chua luu). Tra ve (ket_qua, loi)."""
    ingredients, error = parse_ingredients(payload.get("ingredients"))

    if error:
        return None, error

    servings = _number(payload.get("servings"), 1, MAX_SERVINGS)

    if servings is None:
        return None, f"Số phần ăn phải từ 1 đến {MAX_SERVINGS}."

    result = compute_nutrition(ingredients, int(servings))
    result["labels"] = (
        make_labels(result["per_serving"], result["macros_complete"])
        if result["ok"] else []
    )
    return result, None


def create_recipe(supabase, user_key, display_name, payload, images=None,
                  teach_ai=True, embedder=community_foods.embed_images):
    """Dang cong thuc. Tra ve (ket_qua, loi, ma_loi_http)."""
    title = " ".join(str(payload.get("title") or "").split())[:MAX_TITLE]

    if len(title) < 3:
        return None, "Tên công thức quá ngắn.", 400

    steps, error = _clean_steps(payload.get("steps"))

    if error:
        return None, error, 400

    result, error = preview(payload)

    if error:
        return None, error, 400

    if not result["ok"]:
        names = ", ".join(result["unknown"])
        return None, (
            f"Chưa có số liệu dinh dưỡng cho: {names}. "
            "Hãy nhập kcal/100g cho nguyên liệu đó."
        ), 400

    images = [img for img in (images or []) if img is not None][:MAX_IMAGES]
    thumb = make_thumbnail(images[0]) if images else None

    row = {
        "title": title,
        "description": " ".join(
            str(payload.get("description") or "").split()
        )[:MAX_DESCRIPTION],
        "servings": result["servings"],
        "ingredients": result["ingredients"],
        "steps": steps,
        "nutrition": {
            "total": result["total"],
            "per_serving": result["per_serving"],
            "total_grams": result["total_grams"],
            "grams_per_serving": result["grams_per_serving"],
            "macros_complete": result["macros_complete"],
        },
        "labels": result["labels"],
        "thumb": thumb,
        "created_by": user_key,
        "display_name": (display_name or "Người dùng FoodScan")[:40],
    }

    created = supabase.table("recipes").insert(row).execute()
    recipe = created.data[0]

    # Day AI nhan ra mon tu anh dang kem (neu co). Loi o day KHONG duoc lam
    # hong viec dang cong thuc.
    ai_learned = False

    if teach_ai and images:
        try:
            total_grams = max(result["total_grams"], 1)
            per100 = {
                "calories_per_100g": result["total"]["kcal"] / total_grams * 100,
            }

            if result["macros_complete"]:
                per100.update({
                    "protein_g": result["total"]["protein_g"] / total_grams * 100,
                    "fat_g": result["total"]["fat_g"] / total_grams * 100,
                    "carbs_g": result["total"]["carbs_g"] / total_grams * 100,
                })

            taught, teach_error = community_foods.teach(
                supabase, user_key, title, images, nutrition=per100,
                embedder=embedder,
            )
            ai_learned = taught is not None and teach_error is None
        except Exception as e:
            print(f"[recipes] khong day duoc AI tu anh: {e}")

    return {"recipe_id": recipe["id"], "ai_learned": ai_learned,
            "labels": result["labels"]}, None, 200


def _like_info(supabase, user_key):
    likes = (
        supabase.table("recipe_likes").select("recipe_id,user_key").limit(10000)
        .execute()
    ).data or []

    counts, mine = {}, set()

    for row in likes:
        counts[row["recipe_id"]] = counts.get(row["recipe_id"], 0) + 1

        if row.get("user_key") == user_key:
            mine.add(row["recipe_id"])

    return counts, mine


def _public(recipe, counts, mine, user_key, with_details):
    item = {
        "id": recipe["id"],
        "title": recipe["title"],
        "description": recipe.get("description") or "",
        "servings": recipe.get("servings") or 1,
        "labels": recipe.get("labels") or [],
        "per_serving": (recipe.get("nutrition") or {}).get("per_serving"),
        "thumb": recipe.get("thumb"),
        "author": recipe.get("display_name") or "Người dùng FoodScan",
        "created_at": recipe.get("created_at"),
        "like_count": counts.get(recipe["id"], 0),
        "liked_by_me": recipe["id"] in mine,
        "is_mine": recipe.get("created_by") == user_key,
    }

    if with_details:
        item["ingredients"] = recipe.get("ingredients") or []
        item["steps"] = recipe.get("steps") or []
        item["nutrition"] = recipe.get("nutrition") or {}

    return item


def list_recipes(supabase, user_key, sort="new", mine_only=False):
    query = supabase.table("recipes").select("*")

    if mine_only:
        query = query.eq("created_by", user_key)

    recipes = query.order("created_at", desc=True).limit(60).execute().data or []
    counts, mine = _like_info(supabase, user_key)

    items = [_public(r, counts, mine, user_key, False) for r in recipes]

    if sort == "top":
        items.sort(key=lambda r: r["like_count"], reverse=True)

    return items


def get_recipe(supabase, user_key, recipe_id):
    found = (
        supabase.table("recipes").select("*").eq("id", recipe_id).limit(1)
        .execute()
    ).data

    if not found:
        return None

    counts, mine = _like_info(supabase, user_key)
    return _public(found[0], counts, mine, user_key, True)


def toggle_like(supabase, user_key, recipe_id):
    """Tra ve (liked, like_count) hoac None neu khong co cong thuc."""
    if not (
        supabase.table("recipes").select("id").eq("id", recipe_id).limit(1)
        .execute()
    ).data:
        return None

    existing = (
        supabase.table("recipe_likes").select("*")
        .eq("recipe_id", recipe_id).eq("user_key", user_key).limit(1)
        .execute()
    ).data

    if existing:
        (supabase.table("recipe_likes").delete()
         .eq("recipe_id", recipe_id).eq("user_key", user_key).execute())
        liked = False
    else:
        supabase.table("recipe_likes").insert(
            {"recipe_id": recipe_id, "user_key": user_key}
        ).execute()
        liked = True

    counts, _ = _like_info(supabase, user_key)
    return liked, counts.get(recipe_id, 0)


def delete_recipe(supabase, user_key, recipe_id):
    """Chi chu cong thuc moi xoa duoc. Tra ve True neu da xoa."""
    found = (
        supabase.table("recipes").select("id")
        .eq("id", recipe_id).eq("created_by", user_key).limit(1)
        .execute()
    ).data

    if not found:
        return False

    supabase.table("recipes").delete().eq("id", recipe_id).execute()
    return True


def eat_recipe(supabase, user_key, recipe_id, meal_type, portions=1.0):
    """Ghi vao nhat ky dung luong 'portions' phan an. Tra ve (meal, loi, http)."""
    meal_type = " ".join(str(meal_type or "").split())

    if not meal_type:
        return None, "Thiếu bữa ăn.", 400

    portions = _number(portions, 0.25, 10)

    if portions is None:
        return None, "Số phần ăn phải từ 0.25 đến 10.", 400

    found = (
        supabase.table("recipes").select("*").eq("id", recipe_id).limit(1)
        .execute()
    ).data

    if not found:
        return None, "Không tìm thấy công thức.", 404

    recipe = found[0]
    nutrition = recipe.get("nutrition") or {}
    per = nutrition.get("per_serving") or {}

    meal = {
        "user_key": user_key,
        "food_name": recipe["title"],
        "meal_type": meal_type,
        "portion_g": max(
            int(round((nutrition.get("grams_per_serving") or 0) * portions)), 10
        ),
        "calories": round((per.get("kcal") or 0) * portions, 1),
        "protein_g": round((per.get("protein_g") or 0) * portions, 1),
        "fat_g": round((per.get("fat_g") or 0) * portions, 1),
        "carbs_g": round((per.get("carbs_g") or 0) * portions, 1),
    }

    saved = supabase.table("meal_logs").insert(meal).execute()
    return {
        "meal": saved.data[0],
        "macros_complete": bool(nutrition.get("macros_complete", True)),
    }, None, 200