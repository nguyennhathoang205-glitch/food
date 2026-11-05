"""Phan tich Nhan dinh duong (Nutrition Facts) va Tra cuu Ma vach (Barcode).

Ket hop:
1. Gemini Vision: OCR nhan dinh duong tren bao bi (tieng Viet + Anh), trich xuat
   product_name, brand, serving_size, calories, protein, fat, carbs, sugar, sodium,
   ingredients, barcode (neu nhin thay tren vo).
2. Open Food Facts: Co so du lieu thuc pham toan cau tra cuu ma vach truc tiep.
3. Health Rules: Canh bao di ung, benh ly (tieu duong, huyet ap cao, gout, than...)
"""

import json
import os
import re
import time
import requests
from google import genai
from google.genai import types

from dotenv import load_dotenv

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_env_file = os.path.join(_BASE_DIR, ".env")
if os.path.exists(_env_file):
    load_dotenv(_env_file)
else:
    load_dotenv()

import health as health_rules


def _get_api_keys():
    raw = os.environ.get("GEMINI_API_KEY", "")
    return [k.strip() for k in raw.split(",") if k.strip()]


MODELS_TO_TRY = ["gemini-3.6-flash", "gemini-3.8-flash"]


LABEL_ANALYSIS_PROMPT = """Bạn là chuyên gia thị giác máy tính và OCR phân tích thực phẩm đóng gói cao cấp.
Nhiệm vụ: Phân tích ảnh chụp bao bì / vỏ hộp / vỏ lon / gói / chai thực phẩm hoặc bảng Nutrition Facts, đọc chính xác chữ in và phân tích dinh dưỡng.

QUY TRÌNH PHÂN TÍCH BẮT BUỘC (CHAIN-OF-THOUGHT):
1. BƯỚC 1 - OCR ĐỌC TẤT CẢ VĂN BẢN TRÊN ẢNH:
   - Đọc và ghi lại TẤT CẢ các dòng chữ, tên gọi, thương hiệu, số gram/khối lượng in trên bao bì/vỏ lon/vỏ hộp vào trường 'detected_text'.
   - Chú ý đọc chuẩn xác chữ in to nhất và rõ nhất trên mặt trước hoặc nhãn phụ.

2. BƯỚC 2 - XÁC ĐỊNH SẢN PHẨM & THƯƠNG HIỆU:
   - 'product_name': Phải dựa 100% vào các từ ngữ đọc được trong 'detected_text'. Tuyệt đối KHÔNG suy đoán sang sản phẩm khác nếu chữ trên nhãn đã ghi rõ.
   - 'brand': Tên nhà sản xuất hoặc nhãn hiệu in trên vỏ hộp (nếu có, ví dụ: Hạ Long Canfoco, Vissan, Vinamilk, Orion, Masan...). Nếu không thấy ghi null.

3. BƯỚC 3 - THÀNH PHẦN & NGUYÊN LIỆU:
   - 'ingredients': Danh sách thành phần. Nếu có danh sách nguyên liệu in trên bao bì thì trích xuất đầy đủ. Nếu chỉ có mặt trước, hãy liệt kê chính xác các nguyên liệu điển hình của ĐÚNG SẢN PHẨM ĐÓ (để phục vụ kiểm tra dị ứng và bệnh lý).

4. BƯỚC 4 - BẢNG DINH DƯỠNG (NUTRITION FACTS):
   - Đọc các chỉ số calo, protein, fat, carbs, sugar, sodium trên bảng Nutrition Facts nếu có.
   - Nếu chụp mặt trước không có bảng số liệu, hãy ước tính chuẩn xác theo dữ liệu dinh dưỡng tiêu chuẩn của đúng loại thực phẩm đó.

XUẤT ĐÚNG ĐỊNH DẠNG JSON DUY NHẤT (không bọc trong markdown ngoài):
{
  "detected_text": "Tất cả các dòng chữ in đọc được trên vỏ sản phẩm",
  "product_name": "Tên sản phẩm đúng theo chữ trên bao bì",
  "brand": "Thương hiệu in trên sản phẩm hoặc null",
  "serving_size": "Khẩu phần (vd: 1 lon 150g, 1 gói 75g, 100g...)",
  "serving_size_g": 100.0,
  "servings_per_container": 1.0,
  "calories": 180.0,
  "protein_g": 12.0,
  "fat_g": 11.0,
  "saturated_fat_g": 4.0,
  "carbs_g": 3.0,
  "sugar_g": 1.5,
  "sodium_mg": 520.0,
  "fiber_g": 0.5,
  "ingredients": ["Nguyên liệu chính", "Gia vị", "Chất điều vị..."],
  "barcode": null,
  "health_rating": "Tốt" | "Trung bình" | "Cần hạn chế",
  "summary": "1 câu nhận xét khách quan, chính xác về giá trị dinh dưỡng và lưu ý sức khỏe cho đúng sản phẩm này."
}"""

def _clean_json_text(text):
    text = (text or "").strip()
    if text.startswith("```"):
        first_newline = text.find("\n")
        if first_newline != -1:
            text = text[first_newline + 1:]
        if text.endswith("```"):
            text = text[:-3].strip()
    return text.strip()


def _is_temp_err(err_msg):
    msg = str(err_msg).upper()
    return "503" in msg or "UNAVAILABLE" in msg or "RESOURCE_EXHAUSTED" in msg


def call_gemini_vision(image_bytes, mime_type="image/jpeg", prompt=LABEL_ANALYSIS_PROMPT):
    """Goi Gemini doc anh nhan bao bi voi xoay vong key va retry."""
    keys = _get_api_keys()
    if not keys:
        return None

    last_error = None
    for model_name in MODELS_TO_TRY:
        for key in keys:
            client = genai.Client(api_key=key)
            retries = 2
            while retries >= 0:
                try:
                    response = client.models.generate_content(
                        model=model_name,
                        contents=[
                            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                            prompt
                        ],
                        config={"response_mime_type": "application/json"}
                    )
                    cleaned = _clean_json_text(response.text)
                    return json.loads(cleaned)
                except Exception as e:
                    last_error = str(e)
                    retries -= 1
                    if _is_temp_err(last_error) and retries >= 0:
                        time.sleep(1.2)
                        continue
                    break

    print(f"[label_scan] Gemini OCR loi: {last_error}")
    return None


def lookup_openfoodfacts(barcode):
    """Tra cuu san pham tren Open Food Facts theo ma vach."""
    barcode = str(barcode).strip()
    if not barcode or not re.match(r"^\d{6,16}$", barcode):
        return None

    url = f"https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
    headers = {"User-Agent": "FoodScanApp - Android - Version 1.0"}

    try:
        resp = requests.get(url, headers=headers, timeout=5)
        if resp.status_code != 200:
            return None
        payload = resp.json()
        if payload.get("status") != 1:
            return None

        p = payload.get("product") or {}
        nutri = p.get("nutriments") or {}

        # Ten san pham
        name = (
            p.get("product_name_vi")
            or p.get("product_name")
            or p.get("product_name_en")
            or "Sản phẩm đóng gói"
        )
        brand = p.get("brands") or ""

        # Khau phan
        serving_size = p.get("serving_size") or "100g"
        serving_g = 100.0
        try:
            m = re.search(r"(\d+(?:\.\d+)?)", serving_size)
            if m:
                serving_g = float(m.group(1))
        except Exception:
            pass

        # Dinh duong (uu tien theo serving neu co, nguoc lai theo 100g)
        def _get_val(keys):
            for k in keys:
                v = nutri.get(k)
                if v is not None:
                    try:
                        return float(v)
                    except (ValueError, TypeError):
                        pass
            return 0.0

        cal = _get_val(["energy-kcal_serving", "energy-kcal_100g", "energy-kcal"])
        protein = _get_val(["proteins_serving", "proteins_100g"])
        fat = _get_val(["fat_serving", "fat_100g"])
        sat_fat = _get_val(["saturated-fat_serving", "saturated-fat_100g"])
        carbs = _get_val(["carbohydrates_serving", "carbohydrates_100g"])
        sugar = _get_val(["sugars_serving", "sugars_100g"])
        sodium_g = _get_val(["sodium_serving", "sodium_100g"])
        sodium_mg = sodium_g * 1000.0 if sodium_g < 20 else sodium_g
        fiber = _get_val(["fiber_serving", "fiber_100g"])

        # Danh sach nguyen lieu
        ing_text = (
            p.get("ingredients_text_vi")
            or p.get("ingredients_text")
            or p.get("ingredients_text_en")
            or ""
        )
        ingredients = [
            i.strip()
            for i in re.split(r"[,;•\n\t]", ing_text)
            if i.strip() and len(i.strip()) > 1
        ]

        return {
            "barcode": barcode,
            "product_name": name,
            "brand": brand,
            "serving_size": serving_size,
            "serving_size_g": serving_g,
            "servings_per_container": float(p.get("serving_quantity") or 1.0),
            "calories": cal,
            "protein_g": protein,
            "fat_g": fat,
            "saturated_fat_g": sat_fat,
            "carbs_g": carbs,
            "sugar_g": sugar,
            "sodium_mg": sodium_mg,
            "fiber_g": fiber,
            "ingredients": ingredients,
            "image_url": p.get("image_front_url") or p.get("image_url") or "",
            "health_rating": _calc_rating(cal, sugar, sodium_mg, sat_fat),
            "source": "openfoodfacts",
        }
    except Exception as e:
        print(f"[label_scan] OpenFoodFacts error: {e}")
        return None


def _calc_rating(calories, sugar, sodium, sat_fat):
    score = 0
    if sugar > 15:
        score += 2
    elif sugar > 8:
        score += 1
    if sodium > 800:
        score += 2
    elif sodium > 400:
        score += 1
    if sat_fat > 5:
        score += 1
    if calories > 450:
        score += 1

    if score <= 1:
        return "Tốt"
    elif score <= 3:
        return "Trung bình"
    return "Cần hạn chế"


def scan_nutrition_label(image_bytes, mime_type="image/jpeg", user_key="demo-user"):
    """Doc nhan dinh duong qua Gemini Vision + doi chieu benh ly & di ung."""
    data = call_gemini_vision(image_bytes, mime_type)
    if not data:
        return {
            "status": "error",
            "message": "Không thể đọc thông tin trên nhãn. Vui lòng chụp rõ nét hơn hoặc đủ ánh sáng."
        }

    # Chuan hoa ten san pham va thuong hieu
    pname = str(data.get("product_name") or "").strip()
    brand = str(data.get("brand") or "").strip()
    lower_pname = pname.lower()
    if not pname or "khong xac dinh" in lower_pname or "không xác định" in lower_pname:
        if brand and "null" not in brand.lower():
            data["product_name"] = f"Sản phẩm {brand}"
        else:
            data["product_name"] = "Thực phẩm đóng gói"

    # Chuan hoa ingredients thanh list chuoi
    raw_ing = data.get("ingredients")
    if isinstance(raw_ing, str):
        data["ingredients"] = [
            i.strip() for i in re.split(r"[,;•\n\t]", raw_ing)
            if i.strip() and len(i.strip()) > 1
        ]
    elif not isinstance(raw_ing, list):
        data["ingredients"] = []

    # Tinh toan calo neu bi thieu/bang 0 tu cac chat da luong
    cal = float(data.get("calories") or 0)
    pro = float(data.get("protein_g") or 0)
    fat = float(data.get("fat_g") or 0)
    carb = float(data.get("carbs_g") or 0)
    if cal <= 0 and (pro > 0 or fat > 0 or carb > 0):
        data["calories"] = round(pro * 4.0 + fat * 9.0 + carb * 4.0)

    # Neu Gemini doc duoc barcode va muon lam giau du lieu bang OpenFoodFacts:
    found_barcode = data.get("barcode")
    if found_barcode and re.match(r"^\d{8,16}$", str(found_barcode)):
        off_data = lookup_openfoodfacts(str(found_barcode))
        if off_data and off_data.get("product_name"):
            data["off_verified"] = True
            if not data.get("brand") and off_data.get("brand"):
                data["brand"] = off_data["brand"]
            if not data.get("ingredients") and off_data.get("ingredients"):
                data["ingredients"] = off_data["ingredients"]

    # Kiem tra canh bao suc khoe
    profile = health_rules.load_profile(user_key)
    warnings = health_rules.check_label_warnings(profile, data)

    return {
        "status": "ok",
        "data": data,
        "warnings": warnings,
        "source": "gemini_label_ocr"
    }


def lookup_barcode_with_health(barcode, user_key="demo-user"):
    """Tra cuu barcode tren Open Food Facts, neu khong co tra ve huong dan chup nhan."""
    off_data = lookup_openfoodfacts(barcode)
    if not off_data:
        return {
            "status": "not_found",
            "message": f"Không tìm thấy mã vạch {barcode} trong kho dữ liệu mở. Bạn hãy chụp trực tiếp bảng thành phần dinh dưỡng để AI quét nhé!",
            "barcode": barcode
        }

    profile = health_rules.load_profile(user_key)
    warnings = health_rules.check_label_warnings(profile, off_data)

    return {
        "status": "ok",
        "data": off_data,
        "warnings": warnings,
        "source": "openfoodfacts"
    }
