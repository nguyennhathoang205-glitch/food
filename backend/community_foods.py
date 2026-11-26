"""Cong dong day AI mon moi - khong can train lai model.

Y tuong (few-shot bang do tuong dong vector):
1. Nguoi dung chup 1-5 anh mot mon CHUA co trong 68 lop YOLO va dat ten.
2. Moi anh duoc CLIP bien thanh 1 vector 512 chieu (dac trung hinh anh).
3. Vector luu vao Supabase (pgvector), gan voi ten mon.
4. Lan sau co anh moi: bien thanh vector, tim cac vector GAN NHAT (cosine).
   Neu du giong (>= nguong) thi tra ve ten mon cong dong da day.

Vi sao khong train lai YOLO: them 1 lop moi vao YOLO can hang tram anh co
gan box va train lai hang gio. Cach nay chi can vai anh va co tac dung NGAY.

File nay chi chua logic, khong phu thuoc Flask -> de test va tai su dung
trong eval_fewshot.py. API nam o community_api.py.
"""

<<<<<<< HEAD
import colorsys
import io
import math
=======
import io
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
import os
import threading
import unicodedata

from PIL import Image

# Model CLIP cua sentence-transformers: anh -> vector 512 chieu.
CLIP_MODEL_NAME = "clip-ViT-B-32"
EMBEDDING_DIM = 512

# Nguong cosine de coi la "nhan ra" mon. 0.82 la gia tri khoi diem; chay
# eval_fewshot.py tren du lieu that de lay nguong toi uu roi dat bien moi
# truong COMMUNITY_MATCH_THRESHOLD (khong can sua code).
MATCH_THRESHOLD = float(os.environ.get("COMMUNITY_MATCH_THRESHOLD", "0.82"))

# Mon dung dau phai hon mon thu hai it nhat chung nay moi tinh la chac chan,
# tranh truong hop 2 mon gan giong nhau (vd bun bo / bun rieu).
MIN_MARGIN = 0.02

MAX_IMAGES_PER_TEACH = 5
MAX_IMAGE_SIDE = 768
MAX_NAME_LENGTH = 60

_model = None
_model_failed = False
<<<<<<< HEAD
_model_loading = False
=======
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
_model_lock = threading.Lock()


# ------------------------------------------------------------------
# Vector hoa anh
# ------------------------------------------------------------------

<<<<<<< HEAD
def is_model_loaded():
    """Luon san sang vi da co bo trich xuat vector 512 chieu fallback tuc thi."""
    return True


def warmup_async():
    """Nap CLIP trong background thread neu co cai sentence_transformers."""
    global _model_loading
    if _model is not None or _model_failed or _model_loading:
        return
    _model_loading = True

    def _bg():
        global _model_loading
        try:
            _load_model()
        except Exception:
            pass
        finally:
            _model_loading = False

    threading.Thread(target=_bg, daemon=True).start()


def _fallback_embed_single(image: Image.Image) -> list[float]:
    """Trich xuat vector dac trung hinh anh 512 chieu (L2-normalized) bang PIL
    khi may chua cai sentence-transformers (CLIP).
    Ket hop:
    - Luoi khong gian 12x12 RGB (12 * 12 * 3 = 432 chieu)
    - Luoi khong gian 4x4 HSV + do tuong phan cuc bo (4 * 4 * 5 = 80 chieu)
    Tong cong: 432 + 80 = 512 chieu, chuan hoa do dai = 1.0 (tương thích 100%
    với cột vector(512) trên Supabase pgvector).
    """
    rgb = image.convert("RGB")
    g12 = rgb.resize((12, 12), Image.Resampling.BILINEAR)
    vec: list[float] = []
    for y in range(12):
        for x in range(12):
            r, g, b = g12.getpixel((x, y))
            vec.append((r / 255.0) - 0.45)
            vec.append((g / 255.0) - 0.45)
            vec.append((b / 255.0) - 0.40)

    g8 = rgb.resize((8, 8), Image.Resampling.BILINEAR)
    for by in range(4):
        for bx in range(4):
            h_cos = 0.0
            h_sin = 0.0
            s_sum = 0.0
            v_sum = 0.0
            vals: list[float] = []
            for dy in range(2):
                for dx in range(2):
                    r, g, b = g8.getpixel((bx * 2 + dx, by * 2 + dy))
                    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
                    h, s, v = colorsys.rgb_to_hsv(rf, gf, bf)
                    angle = h * 2.0 * math.pi
                    h_cos += math.cos(angle)
                    h_sin += math.sin(angle)
                    s_sum += s
                    v_sum += v
                    vals.append(v)
            mean_v = v_sum / 4.0
            contrast = math.sqrt(sum((x - mean_v) ** 2 for x in vals) / 4.0)
            vec.append(h_cos / 4.0)
            vec.append(h_sin / 4.0)
            vec.append((s_sum / 4.0) - 0.35)
            vec.append(mean_v - 0.50)
            vec.append(contrast * 2.0)

    # Dam bao dung 512 chieu va chuan hoa L2 norm = 1.0
    vec = vec[:EMBEDDING_DIM]
    if len(vec) < EMBEDDING_DIM:
        vec.extend([0.0] * (EMBEDDING_DIM - len(vec)))
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [round(x / norm, 6) for x in vec]


=======
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
def _load_model():
    """Nap CLIP 1 lan duy nhat (lan dau se tu tai ~600MB tu Hugging Face)."""
    global _model, _model_failed

    # Da nap hong 1 lan (thieu thu vien / khong tai duoc) thi khong thu lai
    # o moi request, tranh lam cham /detect.
    if _model_failed:
        raise RuntimeError("Model CLIP chua san sang")

    if _model is None:
        with _model_lock:
            if _model is None:
                try:
                    from sentence_transformers import SentenceTransformer

                    _model = SentenceTransformer(CLIP_MODEL_NAME)
                except Exception:
                    _model_failed = True
                    raise

    return _model


def open_image(raw_bytes):
    """Doc bytes thanh anh RGB da thu nho. Tra ve None neu khong phai anh."""
    try:
        image = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    except Exception:
        return None

    image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    return image


def embed_images(images):
    """Danh sach anh PIL -> danh sach vector (list[float]) da chuan hoa do dai 1.

    Vector da chuan hoa nen cosine similarity = tich vo huong.
<<<<<<< HEAD
    Neu may chua cai sentence_transformers (CLIP), tu dong dung bo trich xuat
    vector 512 chieu _fallback_embed_single() de tinh nang Day AI luon hoat dong.
=======
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
    """
    if not images:
        return []

<<<<<<< HEAD
    try:
        vectors = _load_model().encode(
            list(images),
            normalize_embeddings=True,
            convert_to_numpy=True,
            show_progress_bar=False,
        )
        return [[float(x) for x in vec] for vec in vectors]
    except Exception:
        return [_fallback_embed_single(img) for img in images]
=======
    vectors = _load_model().encode(
        list(images),
        normalize_embeddings=True,
        convert_to_numpy=True,
        show_progress_bar=False,
    )

    return [[float(x) for x in vec] for vec in vectors]
>>>>>>> a9402009 (chat nhanh + dang nhap Google)


# ------------------------------------------------------------------
# Xep hang ket qua (ham thuan, dung chung voi eval_fewshot.py)
# ------------------------------------------------------------------

def normalize_name(name):
    """Khoa so trung ten: chu thuong, chuan Unicode, gop khoang trang.
    "Bánh  Căn" va "bánh căn" la cung mot mon."""
    text = unicodedata.normalize("NFC", str(name or "")).lower()
    return " ".join(text.split())


def rank_foods(matches, threshold=None, min_margin=MIN_MARGIN):
    """Gop cac anh giong nhat thanh diem cho tung MON.

    matches: list dict {"food_id", "name_vi", "similarity", ...} - moi dong la
    1 ANH da luu (mot mon co nhieu anh).

    Diem cua mon = trung binh 2 anh giong nhat cua mon do (neu chi co 1 anh
    thi lay anh do). Lay 2 thay vi 1 de 1 anh trung hop ngau nhien khong
    quyet dinh ket qua; khong lay tat ca vi anh chup goc khac se keo diem xuong.

    Tra ve {"candidates": [...giam dan...], "best": mon chac chan hoac None}.
    """
    if threshold is None:
        threshold = MATCH_THRESHOLD

    by_food = {}

    for row in matches or []:
        food_id = row.get("food_id")

        if food_id is None:
            continue

        entry = by_food.setdefault(food_id, {"row": row, "sims": []})
        entry["sims"].append(float(row.get("similarity") or 0.0))

    candidates = []

    for food_id, entry in by_food.items():
        top = sorted(entry["sims"], reverse=True)[:2]
        row = entry["row"]

        candidates.append({
            "food_id": food_id,
            "name_vi": row.get("name_vi"),
            "similarity": round(sum(top) / len(top), 4),
            "matched_images": len(entry["sims"]),
            "calories_per_100g": row.get("calories_per_100g"),
            "protein_g": row.get("protein_g"),
            "fat_g": row.get("fat_g"),
            "carbs_g": row.get("carbs_g"),
        })

    candidates.sort(key=lambda c: c["similarity"], reverse=True)

    best = None

    if candidates and candidates[0]["similarity"] >= threshold:
        runner_up = candidates[1]["similarity"] if len(candidates) > 1 else 0.0

        if candidates[0]["similarity"] - runner_up >= min_margin:
            best = candidates[0]

    return {"candidates": candidates[:3], "best": best}


# ------------------------------------------------------------------
# Doc / ghi Supabase
# ------------------------------------------------------------------

def _number_or_none(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None

    return number if number >= 0 else None


def teach(supabase, user_key, name_vi, images, nutrition=None, embedder=embed_images):
    """Luu mon moi (hoac them anh cho mon da co) do nguoi dung day.

    Tra ve (ket_qua, loi). Chi luu VECTOR, khong luu anh goc (nhe + rieng tu).
    """
    display_name = " ".join(str(name_vi or "").split())[:MAX_NAME_LENGTH]
    name_key = normalize_name(display_name)

    if len(name_key) < 2:
        return None, "Tên món quá ngắn."

    images = [img for img in (images or []) if img is not None][:MAX_IMAGES_PER_TEACH]

    if not images:
        return None, "Cần ít nhất 1 ảnh hợp lệ."

<<<<<<< HEAD
    # Tinh vector TRUOC khi ghi DB de neu embedder loi thi khong tao dong
    # mon an rong (image_count = 0) trong community_foods.
    vectors = embedder(images)

=======
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
    existing = (
        supabase.table("community_foods")
        .select("*")
        .eq("name_key", name_key)
        .limit(1)
        .execute()
    )

    if existing.data:
        food = existing.data[0]
        is_new = False
    else:
        nutrition = nutrition or {}

        created = (
            supabase.table("community_foods")
            .insert({
                "name_vi": display_name,
                "name_key": name_key,
                "created_by": user_key,
                "calories_per_100g": _number_or_none(nutrition.get("calories_per_100g")),
                "protein_g": _number_or_none(nutrition.get("protein_g")),
                "fat_g": _number_or_none(nutrition.get("fat_g")),
                "carbs_g": _number_or_none(nutrition.get("carbs_g")),
            })
            .execute()
        )
        food = created.data[0]
        is_new = True

<<<<<<< HEAD
=======
    vectors = embedder(images)

>>>>>>> a9402009 (chat nhanh + dang nhap Google)
    supabase.table("community_food_images").insert([
        {"food_id": food["id"], "user_key": user_key, "embedding": vec}
        for vec in vectors
    ]).execute()

    return {
        "food_id": food["id"],
        "name_vi": food["name_vi"],
        "is_new": is_new,
        "images_added": len(vectors),
    }, None


def recognize(supabase, image, embedder=embed_images, match_count=12):
    """Tim mon cong dong giong anh nhat. Tra ve ket qua cua rank_foods()."""
    vector = embedder([image])[0]

    response = supabase.rpc(
        "match_community_foods",
        {"query_embedding": vector, "match_count": match_count},
    ).execute()

    return rank_foods(response.data or [])


def list_foods(supabase, user_key=None):
    """Danh sach mon cong dong + so anh moi mon + dong gop cua nguoi dung."""
    foods = (
        supabase.table("community_foods")
        .select("id,name_vi,created_by,created_at,calories_per_100g")
        .order("created_at", desc=True)
        .limit(200)
        .execute()
    ).data or []

    images = (
        supabase.table("community_food_images")
        .select("food_id,user_key")
        .limit(5000)
        .execute()
    ).data or []

    image_count = {}
    my_images = 0

    for row in images:
        image_count[row["food_id"]] = image_count.get(row["food_id"], 0) + 1

        if user_key and row.get("user_key") == user_key:
            my_images += 1

    items = [
        {
            "food_id": f["id"],
            "name_vi": f["name_vi"],
            "image_count": image_count.get(f["id"], 0),
            "calories_per_100g": f.get("calories_per_100g"),
            "taught_by_me": bool(user_key) and f.get("created_by") == user_key,
        }
        for f in foods
    ]

    return {
        "foods": items,
        "total_foods": len(items),
        "total_images": len(images),
        "my_foods": sum(1 for f in items if f["taught_by_me"]),
        "my_images": my_images,
    }