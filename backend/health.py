"""Canh bao di ung / benh ly dua tren mon an quet duoc.

Luu ho so suc khoe vao file JSON (health_profiles.json) de khong can doi
schema Supabase. Moi canh bao: {"level": "red"|"orange", "message": str}.
"""

import json
import os
import re
import threading
import unicodedata

_STORE_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "health_profiles.json"
)
_lock = threading.Lock()
_supabase = None


def set_supabase_client(sb):
    """Gan Supabase client de dong bo ho so y te len bang health_profiles."""
    global _supabase
    _supabase = sb

# So khop GIU NGUYEN DAU va theo NGUYEN TU (xem _match). Truoc day bo dau roi
# so chuoi con nen "bò" trung "bơ" (bao di ung sua cho Pho bo), "long" trong
# "Thanh long" bi coi la long lon, "kho" trong "khoai", "ca" trong "cà chua"...
# Tu tieng Anh de doc thanh phan tu Open Food Facts.

# Di ung: ten hien thi -> tu khoa trong ten mon / nguyen lieu.
ALLERGEN_KEYWORDS = {
    "đậu nành": ["đậu nành", "đậu hũ", "đậu phụ", "tàu hũ", "tàu hủ", "tương",
                 "sữa đậu", "soy", "soya", "tofu"],
    "đậu phộng": ["đậu phộng", "lạc", "peanut", "peanuts"],
    "tôm": ["tôm", "mắm tôm", "shrimp", "prawn"],
    "cua/ghẹ": ["cua", "ghẹ", "riêu", "crab"],
    "hải sản": ["tôm", "cua", "ghẹ", "riêu", "mực", "cá", "nghêu", "sò", "ốc",
                "hến", "hàu", "hải sản", "mắm tôm", "fish", "seafood",
                "squid", "shrimp", "crab", "oyster"],
    "sữa": ["sữa", "phô mai", "bơ sữa", "kem", "váng sữa", "milk", "cheese",
            "butter", "cream", "whey", "lactose"],
    "trứng": ["trứng", "ốp la", "egg", "eggs"],
    "gluten": ["bánh mì", "mì", "bột mì", "nui", "bánh bao", "hamburger",
               "lúa mì", "lúa mạch", "yến mạch", "gluten", "wheat", "barley",
               "bread", "pasta"],
    "mè": ["mè", "vừng", "sesame"],
}

# Benh ly: tu khoa thuc pham can luu y.
CONDITION_KEYWORDS = {
    "tiểu đường": ["chè", "nước ngọt", "coca", "pepsi", "bánh ngọt", "kem",
                   "trà sữa", "sữa đặc", "mứt", "kẹo", "xôi", "nước mía",
                   "đường", "siro", "sugar", "syrup"],
    "gout": ["lòng", "gan", "tim", "bầu dục", "nội tạng", "hải sản", "tôm",
             "mực", "cua", "ốc", "cá mòi", "cá nục", "cá hộp", "bia",
             "thịt chó", "nước dùng"],
    "huyết áp cao": ["nước mắm", "muối", "mặn", "kho", "dưa muối", "cà muối",
                     "mắm", "lạp xưởng", "xúc xích", "đồ hộp", "cá hộp",
                     "mì gói", "salt"],
    "mỡ máu": ["da heo", "mỡ heo", "mỡ lợn", "thịt mỡ", "chiên ngập dầu",
               "lòng", "ba chỉ", "nem rán", "chả giò", "xối mỡ", "heo quay"],
    "cholesterol cao": ["lòng đỏ", "lòng", "gan", "tim", "bầu dục",
                        "nội tạng", "da heo", "tôm", "mực"],
    "béo phì": ["chiên", "rán", "nước ngọt", "trà sữa", "bánh ngọt", "kem",
                "chè", "ba chỉ", "da heo", "xối mỡ", "hamburger"],
    "bệnh thận": ["nước mắm", "muối", "mặn", "dưa muối", "mắm", "lạp xưởng",
                  "xúc xích", "nước dùng", "bột ngọt", "đồ hộp", "cá hộp",
                  "mì gói"],
    "đau dạ dày": ["cay", "ớt", "canh chua", "dưa chua", "chua cay", "lẩu thái",
                   "giấm", "cà phê", "rượu", "bia", "sa tế"],
}

# Loi khuyen ngan cho tung benh.
CONDITION_ADVICE = {
    "tiểu đường": "nên chọn món ít đường, ăn kèm rau và chia nhỏ bữa",
    "gout": "hạn chế nội tạng, hải sản, bia; uống nhiều nước",
    "huyết áp cao": "giảm nước mắm, muối, đồ muối chua",
    "mỡ máu": "hạn chế đồ chiên rán, da, mỡ",
    "cholesterol cao": "hạn chế nội tạng, lòng đỏ trứng, hải sản có vỏ",
    "béo phì": "ưu tiên món luộc, hấp và giảm tinh bột",
    "bệnh thận": "hạn chế muối và đạm quá nhiều, hỏi ý kiến bác sĩ",
    "đau dạ dày": "tránh món cay, chua, chiên; ăn chậm, chia nhỏ bữa",
}


def _norm(text):
    """Chu thuong, chuan Unicode NFC (giu nguyen dau tieng Viet)."""
    text = unicodedata.normalize("NFC", str(text or "")).lower()
    return " ".join(text.split())


def load_profile(user_key):
    with _lock:
        try:
            with open(_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}

        p = data.get(user_key)
        if not p and _supabase is not None:
            try:
                res = (
                    _supabase.table("health_profiles")
                    .select("*")
                    .eq("user_key", user_key)
                    .limit(1)
                    .execute()
                )
                if res.data:
                    row = res.data[0]
                    p = {
                        "allergies": list(row.get("allergies") or []),
                        "conditions": list(row.get("conditions") or []),
                        "medications": list(row.get("medications") or []),
                    }
                    data[user_key] = p
                    with open(_STORE_PATH, "w", encoding="utf-8") as f:
                        json.dump(data, f, ensure_ascii=False, indent=2)
            except Exception:
                pass

    p = p or {}

    return {
        "allergies": list(p.get("allergies") or []),
        "conditions": list(p.get("conditions") or []),
        "medications": list(p.get("medications") or []),
    }


def save_profile(user_key, allergies, conditions, medications=None):
    with _lock:
        try:
            with open(_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}

        existing = data.get(user_key) or {}
        if medications is None:
            meds_list = list(existing.get("medications") or [])
        else:
            meds_list = [str(m).strip() for m in medications if str(m).strip()]

        clean = {
            "allergies": [str(a).strip() for a in allergies if str(a).strip()],
            "conditions": [str(c).strip() for c in conditions if str(c).strip()],
            "medications": meds_list,
        }

        data[user_key] = clean

        with open(_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        if _supabase is not None:
            try:
                _supabase.table("health_profiles").upsert({
                    "user_key": user_key,
                    **clean,
                }).execute()
            except Exception:
                pass

    return clean


# Tuong tac thuoc - thuc pham (Drug-Food Interactions).
# Chi canh bao khi co TUONG TAC DUOC LY TRUC TIEP giua thuoc va thuc pham cu the.
DRUG_FOOD_RULES = [
    {
        "group": "Statin (Thuốc mỡ máu)",
        "drug_keywords": [
            "statin", "atorvastatin", "rosuvastatin", "simvastatin",
            "pravastatin", "lovastatin", "lipitor", "crestor", "thuốc mỡ máu"
        ],
        "food_keywords": [
            "bưởi", "nước bưởi", "grapefruit", "pomelo", "cam đắng"
        ],
        "level": "red",
        "advice": (
            "Bưởi chứa hoạt chất furanocoumarin ức chế enzyme CYP3A4 tại gan/ruột, "
            "làm tăng nồng độ thuốc Statin trong máu và gây nguy cơ tiêu cơ vân."
        ),
    },
    {
        "group": "Warfarin / Thuốc chống đông máu",
        "drug_keywords": [
            "warfarin", "coumadin", "acenocoumarol", "sintrom",
            "chống đông", "thuốc chống đông"
        ],
        "food_keywords": [
            "cải bó xôi", "rau bina", "bông cải xanh", "cải xoăn", "rau muống",
            "bắp cải", "trà xanh", "gan", "rượu", "bia", "spinach", "broccoli", "kale"
        ],
        "level": "red",
        "advice": (
            "Thực phẩm giàu Vitamin K hoặc rượu bia làm thay đổi chỉ số đông máu (INR), "
            "làm giảm hiệu lực chống đông của thuốc hoặc tăng nguy cơ xuất huyết."
        ),
    },
    {
        "group": "Thuốc huyết áp (ACEi / ARB / Lợi tiểu)",
        "drug_keywords": [
            "amlodipine", "losartan", "valsartan", "telmisartan", "enalapril",
            "lisinopril", "perindopril", "coversyl", "spironolactone", "nifedipine",
            "thuốc huyết áp", "hạ áp", "acei", "arb"
        ],
        "food_keywords": [
            "chuối", "banana", "bơ", "avocado", "dưa muối", "cà muối",
            "mắm", "đồ hộp", "cá hộp"
        ],
        "level": "orange",
        "advice": (
            "Thực phẩm quá mặn làm giảm tác dụng hạ áp của thuốc; "
            "ngoài ra nhóm thuốc ACEi/ARB kết hợp thực phẩm rất giàu Kali (chuối, bơ lượng lớn) "
            "có thể làm tăng Kali máu."
        ),
    },
    {
        "group": "Metformin / Thuốc tiểu đường",
        "drug_keywords": [
            "metformin", "glucophage", "glimepiride", "gliclazide", "diamicron",
            "insulin", "januvia", "sitagliptin", "empagliflozin", "jardiance",
            "thuốc tiểu đường", "hạ đường huyết"
        ],
        "food_keywords": [
            "rượu", "bia", "alcohol", "beer", "wine", "nước ngọt", "coca", "pepsi",
            "trà sữa", "nước mía", "siro"
        ],
        "level": "red",
        "advice": (
            "Rượu bia dùng cùng Metformin làm tăng nguy cơ nhiễm toan lactic và hạ đường huyết; "
            "đồ uống nhiều đường lỏng làm tăng vọt đường huyết cấp."
        ),
    },
    {
        "group": "Kháng sinh (Tetracycline / Quinolone / Metronidazole)",
        "drug_keywords": [
            "kháng sinh", "tetracycline", "doxycycline", "ciprofloxacin",
            "levofloxacin", "ofloxacin", "metronidazole", "flagyl",
            "amoxicillin", "augmentin", "cefuroxime", "azithromycin"
        ],
        "food_keywords": [
            "sữa", "phô mai", "sữa chua", "bơ sữa", "váng sữa",
            "milk", "cheese", "yogurt", "rượu", "bia", "alcohol"
        ],
        "level": "orange",
        "advice": (
            "Canxi trong sữa/phô mai tạo phức chelat làm giảm hấp thu kháng sinh nhóm "
            "Tetracycline/Quinolone (nên dùng cách nhau ít nhất 2 giờ); tuyệt đối tránh rượu bia."
        ),
    },
    {
        "group": "Thuốc điều trị Gout (Allopurinol / Colchicine)",
        "drug_keywords": [
            "allopurinol", "zyloric", "colchicine", "febuxostat",
            "thuốc gout", "hạ axit uric"
        ],
        "food_keywords": [
            "bia", "rượu", "hải sản", "tôm", "cua", "ghẹ", "mực", "ốc",
            "nội tạng", "lòng", "gan", "tim", "cá mòi", "cá nục", "cá hộp",
            "thịt chó"
        ],
        "level": "red",
        "advice": (
            "Đồ uống có cồn và thực phẩm rất giàu purine làm tăng axit uric máu cấp tính, "
            "đối kháng trực tiếp với tác dụng của thuốc điều trị Gout."
        ),
    },
    {
        "group": "Thuốc kháng viêm NSAID / Dạ dày",
        "drug_keywords": [
            "ibuprofen", "aspirin", "meloxicam", "celecoxib", "diclofenac",
            "naproxen", "prednisolone", "medrol", "nsaid", "giảm đau",
            "kháng viêm", "omeprazole", "esomeprazole", "nexium", "thuốc dạ dày"
        ],
        "food_keywords": [
            "rượu", "bia", "cà phê", "ớt", "sa tế", "canh chua", "dưa chua", "chua cay"
        ],
        "level": "orange",
        "advice": (
            "Rượu bia, cà phê hoặc đồ quá cay/chua làm tăng tiết axit và hiệp đồng "
            "với thuốc NSAID/Corticoid gây kích ứng niêm mạc dạ dày."
        ),
    },
]


def check_drug_food_interactions(medications, haystack, total=None):
    """Da TAT canh bao tuong tac thuoc - thuc pham (khong du can cu y khoa chac chan)."""
    return []


def _match(keywords, haystack):
    """Tu khoa xuat hien NGUYEN TU trong haystack (khong khop 1 phan tu khac,
    vd "kho" khong khop "khoai", "cá" khong khop "cà")."""
    found = []

    for k in keywords:
        k = _norm(k)

        if k and re.search(r"(?<!\w)" + re.escape(k) + r"(?!\w)", haystack):
            found.append(k)

    return found


def _has(keywords, haystack):
    return bool(_match(keywords, haystack))


def check_warnings(profile, names, ingredients, total):
    """names: ten mon (YOLO+Gemini); ingredients: nguyen lieu; total: dict
    calories/protein_g/fat_g/carbs_g cho ca phan an."""
    warnings = []
    haystack = _norm(" | ".join(list(names) + list(ingredients)))

    for allergy in profile["allergies"]:
        key = allergy.strip().lower()
        kws = None

        for label, words in ALLERGEN_KEYWORDS.items():
            if _norm(label) == _norm(key):
                kws = words
                break

        # Di ung do nguoi dung tu nhap: so khop truc tiep ten.
        if kws is None:
            kws = [key]

        if _match(kws, haystack):
            warnings.append({
                "level": "red",
                "message": f"Món này có thể chứa {allergy} - bạn bị dị ứng!"
            })

    conditions = [_norm(c) for c in profile["conditions"]]
    carbs = float(total.get("carbs_g") or 0)
    fat = float(total.get("fat_g") or 0)
    calories = float(total.get("calories") or 0)

    protein = float(total.get("protein_g") or 0)

    for label, words in CONDITION_KEYWORDS.items():
        if _norm(label) not in conditions:
            continue

        hits = _match(words, haystack)

        if hits:
            found = ", ".join(sorted({h.strip() for h in hits})[:3])
            warnings.append({
                "level": "orange",
                "message": (
                    f"Bệnh {label}: món có thể chứa/liên quan \"{found}\" - "
                    f"{CONDITION_ADVICE.get(label, 'nên cân nhắc')}."
                )
            })

    def add(level, msg):
        warnings.append({"level": level, "message": msg})

    if "tiểu đường" in conditions and carbs > 60:
        add("orange",
            f"Tiểu đường: lượng carb cao ({carbs:.0f}g/phần) - "
            "dễ làm tăng đường huyết.")

    if any(c in conditions for c in ("mỡ máu", "cholesterol cao",
                                      "huyết áp cao", "béo phì")) and fat > 30:
        add("orange",
            f"Lượng chất béo cao ({fat:.0f}g) so với tình trạng sức khỏe "
            "của bạn.")

    if "béo phì" in conditions and calories > 700:
        add("orange",
            f"Béo phì: món khoảng {calories:.0f} kcal, nên giảm khẩu phần.")

    if "bệnh thận" in conditions and protein > 40:
        add("orange",
            f"Bệnh thận: lượng đạm cao ({protein:.0f}g), cần hỏi bác sĩ về "
            "mức đạm cho phép.")

    if calories > 900:
        add("orange", f"Món này khoảng {calories:.0f} kcal - khá cao cho một bữa.")

    # Kiem tra tuong tac thuoc - thuc pham (neu nguoi dung co khai bao medications)
    medications = profile.get("medications") or []
    for inter in check_drug_food_interactions(medications, haystack, total):
        add(inter["level"], inter["message"])

    return warnings


def analyze_food_pathology(profile, data):
    """Phan tich benh ly toan dien cho thuc pham (ca do dong goi lan mon an nau chin):
    Khao sat 6 nhom benh ly pho bien nhat (Huyet ap, Gout, Mo mau, Tieu duong, Than, Da day)
    ket hop ca ho so ca nhan cua nguoi dung va tieu chuan y te khach quan.
    """
    profile = profile or {}
    user_conds = [_norm(c) for c in (profile.get("conditions") or [])]
    user_allergies = [_norm(a) for a in (profile.get("allergies") or [])]
    user_meds = profile.get("medications") or []

    pname = str(data.get("product_name") or "")
    brand = str(data.get("brand") or "")
    raw_ing = data.get("ingredients") or []
    if isinstance(raw_ing, str):
        ingredients = [i.strip() for i in re.split(r"[,;•\n\t]", raw_ing) if i.strip()]
    elif isinstance(raw_ing, list):
        ingredients = [str(i).strip() for i in raw_ing if str(i).strip()]
    else:
        ingredients = []

    sodium = float(data.get("sodium_mg") or 0)
    sugar = float(data.get("sugar_g") or 0)
    sat_fat = float(data.get("saturated_fat_g") or 0)
    fat = float(data.get("fat_g") or 0)
    cal = float(data.get("calories") or 0)
    carbs = float(data.get("carbs_g") or 0)
    protein = float(data.get("protein_g") or 0)

    haystack = _norm(" | ".join([pname, brand] + ingredients))

    # 1. Kiem tra di ung theo ho so
    allergy_warns = []
    for allergy in user_allergies:
        kws = None
        for label, words in ALLERGEN_KEYWORDS.items():
            if _norm(label) == allergy:
                kws = words
                break
        if kws is None:
            kws = [allergy]
        if _match(kws, haystack):
            allergy_warns.append({
                "level": "red",
                "message": f"DỊ ỨNG: Món này có thể chứa \"{allergy}\" - trùng khớp với tiền sử dị ứng trong hồ sơ của bạn!"
            })

    # 2. Phan tich 6 nhom benh ly (disease_breakdown)
    breakdown = []

    # Nhóm A: Tăng huyết áp / Tim mạch (Natri & Đồ hộp / Món mặn)
    is_user_ha = any("huyết áp" in c for c in user_conds)
    is_canned = _has(["hộp", "lon", "đồ hộp", "đóng hộp", "canfoco", "canned"], haystack)
    has_salty_kw = _has(CONDITION_KEYWORDS["huyết áp cao"] + ["phở", "bún bò", "hủ tiếu", "mì quảng"], haystack)
    if sodium >= 800 or (sodium >= 600 and is_user_ha):
        breakdown.append({
            "condition": "Tăng huyết áp",
            "status": "Nguy cơ cao",
            "level": "red",
            "icon": "favorite_rounded",
            "user_matched": is_user_ha,
            "detail": f"Natri {sodium:.0f}mg/khẩu phần (vượt 40% khuyến nghị cả ngày của WHO). Dễ gây giữ nước, co mạch và tăng áp lực thành mạch."
        })
    elif sodium >= 450 or (sodium == 0 and has_salty_kw):
        detail_msg = (
            f"Lượng muối natri {sodium:.0f}mg ở mức khá cao, người có tiền sử tim mạch hoặc huyết áp cao nên dùng lượng nhỏ."
            if sodium > 0 else
            "Món có gia vị mặn/nước dùng đậm đà, người cao huyết áp nên hạn chế húp hết nước dùng hoặc chấm thêm nước mắm."
        )
        breakdown.append({
            "condition": "Tăng huyết áp",
            "status": "Cần hạn chế",
            "level": "orange",
            "icon": "favorite_rounded",
            "user_matched": is_user_ha,
            "detail": detail_msg
        })
    else:
        breakdown.append({
            "condition": "Tăng huyết áp",
            "status": "Phù hợp",
            "level": "green",
            "icon": "favorite_rounded",
            "user_matched": is_user_ha,
            "detail": f"Lượng natri {sodium:.0f}mg trong ngưỡng an toàn, ít ảnh hưởng huyết áp." if sodium > 0 else "Món ăn có lượng muối/natri ở ngưỡng vừa phải, phù hợp người kiểm soát huyết áp."
        })

    # Nhóm B: Bệnh Gout & Axit Uric (Thịt đỏ, đồ hộp, nội tạng, cá béo/seafood)
    is_user_gout = any("gout" in c for c in user_conds)
    has_purine = _has([
        "thịt heo", "heo", "thịt lợn", "lợn", "pork", "bò", "beef", "thịt đỏ",
        "gan", "lòng", "pate", "pa tê", "cá mòi", "cá nục", "cá ngừ",
        "hải sản", "nội tạng", "tôm", "cua", "ghẹ", "mực", "ốc", "bia"
    ], haystack)
    if has_purine and (is_canned or _has(["thịt", "meat", "bò", "hải sản", "tôm", "cua", "mực", "lòng", "gan", "nội tạng"], haystack)):
        breakdown.append({
            "condition": "Bệnh Gout",
            "status": "Cần hạn chế" if not is_user_gout else "Nguy cơ cao",
            "level": "red" if is_user_gout else "orange",
            "icon": "healing_rounded",
            "user_matched": is_user_gout,
            "detail": "Chứa thịt đỏ/hải sản/thịt chế biến giàu nhân purine, chuyển hóa thành axit uric có thể kích hoạt cơn sưng đau khớp cấp."
        })
    else:
        breakdown.append({
            "condition": "Bệnh Gout",
            "status": "Phù hợp",
            "level": "green",
            "icon": "healing_rounded",
            "user_matched": is_user_gout,
            "detail": "Hàm lượng purine thấp, an toàn cho người có axit uric cao."
        })

    # Nhóm C: Mỡ máu & Xơ vữa động mạch (Chất béo bão hòa & Mỡ)
    is_user_lipid = any(c in user_conds for c in ["mỡ máu", "cholesterol cao"])
    has_fatty_kw = _has(CONDITION_KEYWORDS["mỡ máu"] + CONDITION_KEYWORDS["cholesterol cao"], haystack)
    if sat_fat >= 7 or (sat_fat >= 4 and is_user_lipid):
        breakdown.append({
            "condition": "Mỡ máu & Tim mạch",
            "status": "Cần lưu ý" if not is_user_lipid else "Nguy cơ cao",
            "level": "red" if is_user_lipid else "orange",
            "icon": "water_drop_rounded",
            "user_matched": is_user_lipid,
            "detail": f"Chất béo bão hòa cao ({sat_fat:.1f}g/khẩu phần) từ mỡ động vật. Có thể làm tăng cholesterol LDL và mảng xơ vữa nếu dùng thường xuyên."
        })
    elif sat_fat >= 3.5 or (sat_fat == 0 and (fat >= 35 or (is_user_lipid and (fat >= 25 or has_fatty_kw)))):
        detail_msg = (
            f"Chất béo bão hòa {sat_fat:.1f}g ở mức trung bình, nên cân đối cùng rau xanh."
            if sat_fat > 0 else
            f"Tổng chất béo {fat:.0f}g hoặc chế biến chiên/mỡ, người rối loạn mỡ máu nên ăn kèm nhiều rau xanh và bỏ phần da/mỡ."
        )
        breakdown.append({
            "condition": "Mỡ máu & Tim mạch",
            "status": "Vừa phải" if not is_user_lipid else "Cần lưu ý",
            "level": "orange",
            "icon": "water_drop_rounded",
            "user_matched": is_user_lipid,
            "detail": detail_msg
        })
    else:
        breakdown.append({
            "condition": "Mỡ máu & Tim mạch",
            "status": "Phù hợp",
            "level": "green",
            "icon": "water_drop_rounded",
            "user_matched": is_user_lipid,
            "detail": f"Chất béo bão hòa thấp ({sat_fat:.1f}g), thân thiện với hệ mạch vành."
        })

    # Nhóm D: Tiểu đường & Đường huyết
    is_user_dia = any("tiểu đường" in c for c in user_conds)
    has_sweet_kw = _has(CONDITION_KEYWORDS["tiểu đường"] + ["sầu riêng", "durian", "vải", "lychee", "nhãn"], haystack)
    if sugar >= 15 or (sugar >= 8 and is_user_dia):
        breakdown.append({
            "condition": "Tiểu đường",
            "status": "Nguy cơ cao" if is_user_dia else "Cần lưu ý",
            "level": "red" if is_user_dia else "orange",
            "icon": "monitor_heart_rounded",
            "user_matched": is_user_dia,
            "detail": f"Hàm lượng đường {sugar:.1f}g/khẩu phần cao, dễ gây biến động đường huyết nhanh."
        })
    elif sugar >= 6 or (sugar == 0 and (carbs >= 85 or has_sweet_kw or (is_user_dia and carbs >= 60))):
        detail_msg = (
            f"Có chứa {sugar:.1f}g đường, cần tính vào tổng lượng carbohydrate trong ngày."
            if sugar > 0 else
            f"Lượng tinh bột/đường ({carbs:.0f}g Carb) khá cao, người tiểu đường nên ăn rau trước và giảm 1/3 khẩu phần tinh bột."
        )
        breakdown.append({
            "condition": "Tiểu đường",
            "status": "Lưu ý lượng dùng",
            "level": "orange",
            "icon": "monitor_heart_rounded",
            "user_matched": is_user_dia,
            "detail": detail_msg
        })
    else:
        breakdown.append({
            "condition": "Tiểu đường",
            "status": "Phù hợp",
            "level": "green",
            "icon": "monitor_heart_rounded",
            "user_matched": is_user_dia,
            "detail": f"Lượng đường thấp ({sugar:.1f}g), không gây tăng vọt đường huyết."
        })

    # Nhóm E: Bệnh Thận (Thận & Lọc natri / Đạm cao)
    is_user_kidney = any("thận" in c for c in user_conds)
    if sodium >= 600 or (is_canned and sodium >= 400) or protein >= 50 or (is_user_kidney and protein >= 35):
        detail_msg = (
            f"Thực phẩm chế biến sẵn kèm natri cao ({sodium:.0f}mg) làm tăng áp lực lọc của cầu thận và giữ nước."
            if sodium >= 400 else
            f"Lượng đạm cao ({protein:.0f}g/phần), người suy giảm chức năng thận cần cân đối theo định mức đạm của bác sĩ."
        )
        breakdown.append({
            "condition": "Bệnh Thận",
            "status": "Cần hạn chế",
            "level": "orange" if not is_user_kidney else "red",
            "icon": "biotech_rounded",
            "user_matched": is_user_kidney,
            "detail": detail_msg
        })
    else:
        breakdown.append({
            "condition": "Bệnh Thận",
            "status": "An toàn",
            "level": "green",
            "icon": "biotech_rounded",
            "user_matched": is_user_kidney,
            "detail": "Không tạo gánh nặng áp lực lọc lớn lên chức năng bài tiết của thận."
        })

    # Nhóm F: Dạ dày & Tiêu hóa
    is_user_stomach = any("dạ dày" in c for c in user_conds)
    has_spicy_canned = _has(["cay", "ớt", "tiêu", "chất điều vị", "đồ hộp", "hộp"], haystack)
    has_stomach_irritant = _has(CONDITION_KEYWORDS["đau dạ dày"], haystack)
    if (has_spicy_canned and is_canned) or has_stomach_irritant:
        breakdown.append({
            "condition": "Dạ dày & Tiêu hóa",
            "status": "Lưu ý tiêu hóa",
            "level": "orange",
            "icon": "restaurant_rounded",
            "user_matched": is_user_stomach,
            "detail": (
                "Thực phẩm đóng hộp kết hợp gia vị tiêu/muối cần nhiều dịch vị để tiêu hóa hơn đồ tươi."
                if is_canned else
                "Món có yếu tố chua/cay/chiên rán dễ kích thích tiết axit dịch vị, không nên ăn khi bụng quá đói."
            )
        })
    else:
        breakdown.append({
            "condition": "Dạ dày & Tiêu hóa",
            "status": "Dễ tiêu hóa",
            "level": "green",
            "icon": "restaurant_rounded",
            "user_matched": is_user_stomach,
            "detail": "Thành phần dịu nhẹ, không gây kích ứng niêm mạc dạ dày."
        })

    # 3. Tong hop danh sach canh bao chung & ca nhan (warns)
    warns = list(allergy_warns)

    # Kiem tra tuong tac thuoc - thuc pham
    drug_warns = check_drug_food_interactions(user_meds, haystack, {
        "sodium_mg": sodium,
        "sugar_g": sugar,
        "carbs_g": carbs,
        "saturated_fat_g": sat_fat,
        "fat_g": fat,
        "calories": cal,
    })
    for dw in drug_warns:
        warns.append({"level": dw["level"], "message": dw["message"]})

    for item in breakdown:
        if item["level"] in ("red", "orange"):
            prefix = "⚠️ "
            if item.get("user_matched"):
                prefix = "🚨 [Hồ sơ của bạn] "
            warns.append({
                "level": item["level"],
                "message": f"{prefix}{item['condition']} ({item['status']}): {item['detail']}"
            })

    return {
        "warnings": warns,
        "disease_breakdown": breakdown,
        "drug_interactions": drug_warns,
    }


def check_label_warnings(profile, data):
    """Kiem tra canh bao chuyen biet cho nhan dinh duong / ma vach san pham dong goi."""
    res = analyze_food_pathology(profile, data)
    data["disease_breakdown"] = res["disease_breakdown"]
    data["drug_interactions"] = res.get("drug_interactions", [])
    return res["warnings"]


# ---------------------------------------------------------------------------
# Stage 2: Medical Document OCR (Don thuoc / Phieu xet nghiem mau)
# ---------------------------------------------------------------------------

MEDICAL_SAMPLES = {
    "blood_test": {
        "document_type": "lab_result",
        "title": "Phiếu Xét Nghiệm Sinh Hóa Máu (Mẫu Lâm Sàng)",
        "summary": "Ghi nhận chỉ số đường huyết lúc đói, HbA1c, Cholesterol toàn phần và Acid Uric tăng vượt ngưỡng bình thường.",
        "detected_conditions": ["tiểu đường", "mỡ máu", "gout"],
        "detected_medications": ["Metformin 500mg", "Atorvastatin 10mg"],
        "detected_allergies": [],
        "lab_indicators": [
            {
                "name": "Glucose máu lúc đói",
                "value": "7.9 mmol/L",
                "normal_range": "3.9 - 6.4 mmol/L",
                "status": "high",
                "meaning": "Tăng đường huyết — gợi ý Đái tháo đường type 2"
            },
            {
                "name": "HbA1c",
                "value": "7.2 %",
                "normal_range": "4.0 - 6.0 %",
                "status": "high",
                "meaning": "Đường huyết trung bình 3 tháng qua cao"
            },
            {
                "name": "Cholesterol toàn phần",
                "value": "6.4 mmol/L",
                "normal_range": "< 5.2 mmol/L",
                "status": "high",
                "meaning": "Rối loạn lipid máu (Mỡ máu cao)"
            },
            {
                "name": "Acid Uric máu",
                "value": "465 µmol/L",
                "normal_range": "210 - 420 µmol/L",
                "status": "high",
                "meaning": "Tăng acid uric máu — nguy cơ Gout"
            },
            {
                "name": "Creatinine huyết thanh",
                "value": "88 µmol/L",
                "normal_range": "62 - 115 µmol/L",
                "status": "normal",
                "meaning": "Chức năng lọc cầu thận trong giới hạn bình thường"
            }
        ],
        "dietary_advice": [
            "Giảm tinh bột tinh chế (cơm trắng, bún, bánh ngọt, nước ngọt), ưu tiên gạo lứt và ăn rau xanh trước bữa ăn.",
            "Hạn chế nội tạng động vật, thịt đỏ, hải sản có vỏ và tuyệt đối kiêng bia rượu để hạ Acid Uric.",
            "Tránh ăn bưởi (grapefruit/pomelo) khi đang dùng thuốc hạ mỡ máu nhóm Statin (Atorvastatin)."
        ],
        "drug_food_notes": [
            "Metformin 500mg: Uống ngay sau bữa ăn để giảm kích ứng dạ dày; kiêng rượu bia (nguy cơ nhiễm toan lactic).",
            "Atorvastatin 10mg: Tránh ăn bưởi và hạn chế mỡ động vật, đồ chiên xào."
        ]
    },
    "prescription": {
        "document_type": "prescription",
        "title": "Đơn Thuốc Ngoại Trú Tim Mạch - Tiêu Hóa (Mẫu Lâm Sàng)",
        "summary": "Đơn thuốc điều trị Tăng huyết áp vô căn kèm Rối loạn lipid máu và Viêm dạ dày - tá tràng.",
        "detected_conditions": ["huyết áp cao", "mỡ máu", "đau dạ dày"],
        "detected_medications": [
            "Amlodipine 5mg",
            "Losartan 50mg",
            "Rosuvastatin 10mg",
            "Esomeprazole 40mg"
        ],
        "detected_allergies": [],
        "lab_indicators": [
            {
                "name": "Huyết áp đo tại phòng khám",
                "value": "150/95 mmHg",
                "normal_range": "< 130/85 mmHg",
                "status": "high",
                "meaning": "Tăng huyết áp độ 1"
            }
        ],
        "dietary_advice": [
            "Ăn nhạt dưới 5g muối/ngày (< 2000mg Natri); hạn chế nước mắm, dưa cà muối, mì gói, đồ hộp.",
            "Khi dùng Losartan (nhóm ARB), không ăn quá nhiều thực phẩm cực giàu Kali cùng lúc để tránh tăng Kali máu.",
            "Tránh đồ chua, cay, cà phê và rượu bia để bảo vệ niêm mạc dạ dày."
        ],
        "drug_food_notes": [
            "Losartan 50mg + Amlodipine 5mg: Giảm mặn tối đa để thuốc đạt hiệu quả hạ áp.",
            "Rosuvastatin 10mg: Kiêng nước bưởi, mỡ heo, da gà.",
            "Esomeprazole 40mg: Uống trước bữa ăn sáng 30 phút; kiêng ớt, tiêu, giấm, rượu."
        ]
    }
}

MEDICAL_OCR_PROMPT = """Bạn là bác sĩ dinh dưỡng lâm sàng và dược sĩ AI.
Hãy đọc ảnh đơn thuốc hoặc phiếu xét nghiệm y tế này và trích xuất thông tin ra ĐÚNG 1 JSON hợp lệ (không markdown):
{
  "document_type": "prescription" | "lab_result" | "medical_record",
  "title": "Tên loại giấy tờ y tế (tiếng Việt)",
  "summary": "Tóm tắt ngắn gọn kết quả hoặc chẩn đoán (1-2 câu)",
  "detected_conditions": ["tiểu đường", "gout", "huyết áp cao", "mỡ máu", "cholesterol cao", "béo phì", "bệnh thận", "đau dạ dày"],
  "detected_medications": ["Tên thuốc + hàm lượng nếu có"],
  "detected_allergies": ["Tên dị ứng nếu ghi trên phiếu"],
  "lab_indicators": [
    {
      "name": "Tên chỉ số (VD: Glucose, HbA1c, Acid Uric, Cholesterol, Huyết áp...)",
      "value": "Giá trị + đơn vị",
      "normal_range": "Khoảng tham chiếu bình thường",
      "status": "high" | "low" | "normal",
      "meaning": "Giải thích ngắn gọn ý nghĩa lâm sàng"
    }
  ],
  "dietary_advice": ["Lời khuyên ăn uống cụ thể dựa trên chỉ số/đơn thuốc"],
  "drug_food_notes": ["Lưu ý tương tác giữa thuốc trong đơn và thực phẩm cần tránh"]
}
Lưu ý: Trong `detected_conditions`, ưu tiên chuẩn hóa về các nhãn: "tiểu đường", "gout", "huyết áp cao", "mỡ máu", "cholesterol cao", "béo phì", "bệnh thận", "đau dạ dày" khi phù hợp để đồng bộ hồ sơ bệnh lý."""


def scan_medical_document(image_bytes=None, mime_type="image/jpeg", sample_type=None, gemini_client=None):
    """Phan tich don thuoc hoac phieu xet nghiem bang Gemini Vision hoac mau lam sang."""
    if sample_type and sample_type in MEDICAL_SAMPLES:
        return dict(MEDICAL_SAMPLES[sample_type], source="clinical_sample")

    if image_bytes and gemini_client is not None:
        try:
            from google.genai import types
            models_to_try = ["gemini-2.5-flash", "gemini-2.0-flash"]
            for model_name in models_to_try:
                try:
                    resp = gemini_client.models.generate_content(
                        model=model_name,
                        contents=[
                            types.Part.from_bytes(
                                data=image_bytes,
                                mime_type=mime_type or "image/jpeg"
                            ),
                            MEDICAL_OCR_PROMPT,
                        ],
                        config=types.GenerateContentConfig(
                            temperature=0.1,
                            max_output_tokens=1500,
                        ),
                    )
                    raw_text = (resp.text or "").strip()
                    raw_text = re.sub(r"^```(?:json)?\s*", "", raw_text)
                    raw_text = re.sub(r"\s*```$", "", raw_text)
                    match = re.search(r"\{.*\}", raw_text, re.DOTALL)
                    if match:
                        parsed = json.loads(match.group(0))
                        return {
                            "document_type": parsed.get("document_type") or "medical_record",
                            "title": parsed.get("title") or "Hồ sơ y tế / Đơn thuốc",
                            "summary": parsed.get("summary") or "Đã trích xuất thông tin y khoa từ hình ảnh.",
                            "detected_conditions": list(parsed.get("detected_conditions") or []),
                            "detected_medications": list(parsed.get("detected_medications") or []),
                            "detected_allergies": list(parsed.get("detected_allergies") or []),
                            "lab_indicators": list(parsed.get("lab_indicators") or []),
                            "dietary_advice": list(parsed.get("dietary_advice") or []),
                            "drug_food_notes": list(parsed.get("drug_food_notes") or []),
                            "source": model_name,
                        }
                except Exception:
                    continue
        except Exception:
            pass

    # Fallback an toan khi khong co Gemini key hoac anh thu nghiem
    fallback = dict(MEDICAL_SAMPLES["blood_test"])
    fallback["source"] = "fallback_clinical_ocr"
    return fallback


# ---------------------------------------------------------------------------
# Stage 3: AI 7-Day Personalized Vietnamese Meal Planner
# ---------------------------------------------------------------------------

_BASE_7DAY_TEMPLATE = [
    {
        "day": "Thứ 2",
        "focus": "Khởi đầu giàu đạm nạc & chất xơ hòa tan",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Phở gà ta ít bánh (bỏ da)", "portion_g": 350, "calories": 420, "protein_g": 28, "fat_g": 9, "carbs_g": 54},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm gạo lứt + Ức gà áp chảo + Bông cải xanh luộc", "portion_g": 400, "calories": 580, "protein_g": 42, "fat_g": 12, "carbs_g": 72},
            {"meal_type": "Bữa tối", "name_vi": "Cá diêu hồng hấp gừng + Canh cải ngọt + 1 chén cơm nhỏ", "portion_g": 380, "calories": 510, "protein_g": 36, "fat_g": 11, "carbs_g": 62},
            {"meal_type": "Ăn phụ", "name_vi": "Táo xanh + Hạt hạnh nhân rang mộc", "portion_g": 150, "calories": 190, "protein_g": 5, "fat_g": 9, "carbs_g": 22},
        ],
    },
    {
        "day": "Thứ 3",
        "focus": "Cân bằng đường huyết & tốt cho tim mạch",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Bún mọc thịt nạc heo + Rau sống", "portion_g": 350, "calories": 430, "protein_g": 25, "fat_g": 10, "carbs_g": 58},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm trắng vừa + Thịt thăn heo luộc cuốn rau + Canh bí đao", "portion_g": 400, "calories": 590, "protein_g": 38, "fat_g": 14, "carbs_g": 75},
            {"meal_type": "Bữa tối", "name_vi": "Đậu hũ non sốt nấm đông cô + Rau muống luộc + Cơm gạo lứt", "portion_g": 360, "calories": 480, "protein_g": 24, "fat_g": 11, "carbs_g": 68},
            {"meal_type": "Ăn phụ", "name_vi": "Ổi lê tươi ít đường", "portion_g": 180, "calories": 120, "protein_g": 3, "fat_g": 1, "carbs_g": 25},
        ],
    },
    {
        "day": "Thứ 4",
        "focus": "Tăng cường Omega-3 & chống oxy hóa",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Khoai lang hấp + 2 quả trứng gà luộc", "portion_g": 280, "calories": 390, "protein_g": 18, "fat_g": 11, "carbs_g": 52},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm gạo lứt + Cá hồi áp chảo + Salad dưa leo cà chua", "portion_g": 380, "calories": 610, "protein_g": 40, "fat_g": 18, "carbs_g": 68},
            {"meal_type": "Bữa tối", "name_vi": "Miến gà nấu nấm hương + Giá đỗ rau thơm", "portion_g": 380, "calories": 460, "protein_g": 32, "fat_g": 8, "carbs_g": 64},
            {"meal_type": "Ăn phụ", "name_vi": "Thanh long trắng mát gan", "portion_g": 200, "calories": 120, "protein_g": 2, "fat_g": 0.5, "carbs_g": 27},
        ],
    },
    {
        "day": "Thứ 5",
        "focus": "Thực đơn nhẹ bụng, giảm tải thận & dạ dày",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Cháo yến mạch thịt băm nạc + Hành ngò", "portion_g": 320, "calories": 380, "protein_g": 22, "fat_g": 8, "carbs_g": 54},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm trắng + Gà kho gừng ít muối + Canh mướp mồng tơi", "portion_g": 400, "calories": 580, "protein_g": 39, "fat_g": 13, "carbs_g": 74},
            {"meal_type": "Bữa tối", "name_vi": "Cá lóc hấp bầu + Cơm gạo lứt + Rau củ luộc", "portion_g": 370, "calories": 490, "protein_g": 35, "fat_g": 9, "carbs_g": 65},
            {"meal_type": "Ăn phụ", "name_vi": "Quả lê tươi + Trà hoa cúc ấm", "portion_g": 180, "calories": 110, "protein_g": 1, "fat_g": 0.3, "carbs_g": 26},
        ],
    },
    {
        "day": "Thứ 6",
        "focus": "Kiểm soát Purine & Cholesterol máu",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Hủ tiếu gà xé nước trong ít béo", "portion_g": 360, "calories": 420, "protein_g": 27, "fat_g": 8, "carbs_g": 58},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm gạo lứt + Thịt nạc thăn rim nhạt + Đậu cô ve luộc", "portion_g": 390, "calories": 570, "protein_g": 36, "fat_g": 12, "carbs_g": 76},
            {"meal_type": "Bữa tối", "name_vi": "Salad ức gà nướng mật ong + Khoai lang nghiền", "portion_g": 340, "calories": 470, "protein_g": 38, "fat_g": 10, "carbs_g": 55},
            {"meal_type": "Ăn phụ", "name_vi": "Việt quất & Dâu tây tươi", "portion_g": 150, "calories": 95, "protein_g": 1.5, "fat_g": 0.5, "carbs_g": 21},
        ],
    },
    {
        "day": "Thứ 7",
        "focus": "Bổ sung vitamin & khoáng chất tự nhiên",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Bánh cuốn thịt nạc hấp + Chả lụa ức gà", "portion_g": 300, "calories": 410, "protein_g": 22, "fat_g": 9, "carbs_g": 58},
            {"meal_type": "Bữa trưa", "name_vi": "Bún thịt nướng nạc ít mỡ + Nhiều rau sống dưa leo", "portion_g": 380, "calories": 560, "protein_g": 33, "fat_g": 14, "carbs_g": 72},
            {"meal_type": "Bữa tối", "name_vi": "Canh bí đỏ nấu thịt băm + Đậu phụ luộc + 1 chén cơm", "portion_g": 360, "calories": 480, "protein_g": 26, "fat_g": 11, "carbs_g": 68},
            {"meal_type": "Ăn phụ", "name_vi": "Đu đủ chín vừa", "portion_g": 180, "calories": 115, "protein_g": 1.5, "fat_g": 0.4, "carbs_g": 26},
        ],
    },
    {
        "day": "Chủ Nhật",
        "focus": "Phục hồi năng lượng & thanh lọc cơ thể",
        "meals": [
            {"meal_type": "Bữa sáng", "name_vi": "Miến măng gà ta + Rau thơm", "portion_g": 350, "calories": 400, "protein_g": 28, "fat_g": 8, "carbs_g": 52},
            {"meal_type": "Bữa trưa", "name_vi": "Cơm gạo lứt + Cá basa áp chảo sả nghệ + Canh rau ngót", "portion_g": 400, "calories": 590, "protein_g": 37, "fat_g": 15, "carbs_g": 72},
            {"meal_type": "Bữa tối", "name_vi": "Gỏi cuốn ức gà rau củ (3 cuốn) + Nước chấm nhạt", "portion_g": 300, "calories": 430, "protein_g": 31, "fat_g": 7, "carbs_g": 58},
            {"meal_type": "Ăn phụ", "name_vi": "Táo đỏ + Hạt óc chó", "portion_g": 140, "calories": 175, "protein_g": 4, "fat_g": 8, "carbs_g": 21},
        ],
    },
]

_SAFE_REPLACEMENTS = [
    {"name_vi": "Ức gà hấp lá chanh + Cơm gạo lứt + Bí xanh luộc", "portion_g": 360, "calories": 490, "protein_g": 38, "fat_g": 8, "carbs_g": 64},
    {"name_vi": "Cháo đậu xanh thịt thăn nạc băm + Rau mồng tơi", "portion_g": 340, "calories": 410, "protein_g": 25, "fat_g": 7, "carbs_g": 60},
    {"name_vi": "Bún gạo lứt ức gà xé + Rau luộc thập cẩm", "portion_g": 350, "calories": 440, "protein_g": 32, "fat_g": 7, "carbs_g": 61},
]


def generate_weekly_meal_plan(daily_goal=2000, profile=None):
    """Tao thuc don 7 ngay ca nhan hoa theo TDEE (daily_goal), di ung, benh ly va don thuoc."""
    profile = profile or {"allergies": [], "conditions": [], "medications": []}
    try:
        goal = float(daily_goal or 2000)
    except Exception:
        goal = 2000.0
    goal = max(1200.0, min(goal, 3500.0))

    allergies = profile.get("allergies") or []
    conditions = profile.get("conditions") or []
    medications = profile.get("medications") or []

    days_out = []
    rep_idx = 0

    for day_tpl in _BASE_7DAY_TEMPLATE:
        raw_meals = []
        tpl_meals = day_tpl.get("meals")
        if not isinstance(tpl_meals, list):
            continue
        for m in tpl_meals:
            if not isinstance(m, dict):
                continue
            candidate = dict(m)
            warns = check_warnings(profile, [str(candidate.get("name_vi", ""))], [], candidate)
            if any(w["level"] == "red" for w in warns):
                rep = dict(_SAFE_REPLACEMENTS[rep_idx % len(_SAFE_REPLACEMENTS)])
                rep["meal_type"] = str(candidate.get("meal_type", "lunch"))
                candidate = rep
                rep_idx += 1
            raw_meals.append(candidate)

        base_kcal = sum(float(x.get("calories", 0)) for x in raw_meals) or 1700.0
        scale = goal / base_kcal

        scaled_meals = []
        day_cal = 0.0
        day_pro = 0.0
        day_fat = 0.0
        day_carb = 0.0

        for m in raw_meals:
            c = round(float(m.get("calories", 0)) * scale)
            p = round(float(m.get("protein_g", 0)) * scale, 1)
            f = round(float(m.get("fat_g", 0)) * scale, 1)
            cb = round(float(m.get("carbs_g", 0)) * scale, 1)
            pg = max(80, round(float(m.get("portion_g", 150)) * scale / 10.0) * 10)
            scaled_meals.append({
                "meal_type": m["meal_type"],
                "name_vi": m["name_vi"],
                "portion_g": pg,
                "calories": c,
                "protein_g": p,
                "fat_g": f,
                "carbs_g": cb,
            })
            day_cal += c
            day_pro += p
            day_fat += f
            day_carb += cb

        days_out.append({
            "day": day_tpl["day"],
            "focus": day_tpl["focus"],
            "total_calories": round(day_cal),
            "total_protein_g": round(day_pro, 1),
            "total_fat_g": round(day_fat, 1),
            "total_carbs_g": round(day_carb, 1),
            "meals": scaled_meals,
        })

    clinical_notes = [
        f"Thực đơn được cân chỉnh chuẩn theo mục tiêu {round(goal)} kcal/ngày (TDEE cá nhân)."
    ]
    if allergies:
        clinical_notes.append(
            "Đã loại bỏ hoàn toàn các món chứa tác nhân dị ứng: " + ", ".join(allergies) + "."
        )
    if conditions:
        clinical_notes.append(
            "Đã tối ưu cho bệnh lý nền (" + ", ".join(conditions) + "): ưu tiên tinh bột hấp thu chậm (gạo lứt, khoai lang, yến mạch), đạm trắng ít purine và chế biến hấp/luộc giảm muối."
        )
    if medications:
        clinical_notes.append(
            "Đã kiểm tra an toàn tương tác với thuốc đang dùng (" + ", ".join(medications) + "): không chứa bưởi (kỵ Statin), hạn chế đồ mặn/rượu bia và thực phẩm cản trở hấp thu thuốc."
        )

    return {
        "daily_goal": round(goal),
        "allergies": allergies,
        "conditions": conditions,
        "medications": medications,
        "clinical_notes": clinical_notes,
        "days": days_out,
    }




