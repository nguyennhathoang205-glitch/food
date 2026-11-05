"""
Dung Gemini Vision (google-genai SDK moi) tu dong nhan dien ten mon an
cho moi class, dua tren anh mau da crop trong class_samples/class_XX/.

Ho tro NHIEU API KEY (xoay vong khi 1 key het quota) - dat trong .env
dang: GEMINI_API_KEY=key1,key2,key3

Cai thu vien truoc khi chay:
    pip install google-genai

Chay trong thu muc backend/ (da co .env voi GEMINI_API_KEY):
    python auto_label_classes.py
"""
import os
import json
import time
from pathlib import Path
from dotenv import load_dotenv
from google import genai

load_dotenv()

API_KEYS_RAW = os.environ.get("GEMINI_API_KEY", "")
API_KEYS = [k.strip() for k in API_KEYS_RAW.split(",") if k.strip()]
if not API_KEYS:
    raise SystemExit("Chua co GEMINI_API_KEY trong .env, them vao roi chay lai.")

print(f"Da nap {len(API_KEYS)} API key.")

MODEL_NAME = "gemini-3.6-flash"
SAMPLES_DIR = Path("class_samples")
OUTPUT_FILE = Path("class_names_suggested.json")

MAX_RETRIES = 4
RETRY_DELAY_SECONDS = 8

PROMPT = """Day la {n} anh crop can canh cua CUNG MOT loai mon an Viet Nam
(duoc cat ra tu nhieu tam anh khac nhau bang bounding box, nen goc chup/do ro co the khac nhau).

Hay xac dinh day la mon gi. Tra loi CHINH XAC theo format JSON sau, khong them chu nao khac:
{{"name_vi": "<ten mon tieng Viet, viet hoa chu cai dau>", "name_en": "<ten khong dau, snake_case, vd: com_tam>", "confidence": "<high/medium/low>"}}

Neu khong chac chan la mon gi, van doan ten kha di nhat va de confidence la "low".
"""

# Con tro toi key dang dung, chuyen sang key ke tiep khi gap 429 (het quota)
current_key_index = 0

def get_client():
    global current_key_index
    return genai.Client(api_key=API_KEYS[current_key_index])

def switch_to_next_key():
    global current_key_index
    if current_key_index < len(API_KEYS) - 1:
        current_key_index += 1
        print(f"  -> Chuyen sang API key #{current_key_index + 1}/{len(API_KEYS)}")
        return True
    return False  # da het key de chuyen

def load_existing_results():
    if OUTPUT_FILE.exists():
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def save_results(results):
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

def label_class(class_dir):
    image_files = sorted(class_dir.glob("*.jpg"))[:5]
    if not image_files:
        return None

    for attempt in range(1, MAX_RETRIES + 1):
        client = get_client()
        try:
            uploaded = [client.files.upload(file=str(f)) for f in image_files]
            prompt = PROMPT.format(n=len(uploaded))
            response = client.models.generate_content(
                model=MODEL_NAME,
                contents=[prompt, *uploaded],  # type: ignore
            )
            text = (response.text or "").strip()
            if text.startswith("```"):
                text = text.split("```")[1]
                if text.startswith("json"):
                    text = text[4:]
            return json.loads(text.strip())
        except Exception as e:
            error_str = str(e)
            print(f"  Lan {attempt}/{MAX_RETRIES} loi: {e}")
            if "RESOURCE_EXHAUSTED" in error_str or "429" in error_str:
                if switch_to_next_key():
                    continue  # thu lai ngay voi key moi, khong tinh vao so lan retry cho lich su
                else:
                    print("  Da het tat ca API key, dung script tai day.")
                    return "NO_MORE_KEYS"
            if attempt < MAX_RETRIES:
                print(f"  Doi {RETRY_DELAY_SECONDS}s roi thu lai...")
                time.sleep(RETRY_DELAY_SECONDS)
    return None

def main():
    class_dirs = sorted(SAMPLES_DIR.glob("class_*"))
    print(f"Tim thay {len(class_dirs)} class can nhan dien.\n")

    results = load_existing_results()
    already_done = {
        k for k, v in results.items()
        if v.get("name_en") not in (None, "unknown", "UNKNOWN")
    }
    if already_done:
        print(f"Da co ket qua cho {len(already_done)} class tu lan chay truoc, se bo qua.\n")

    for class_dir in class_dirs:
        class_id = class_dir.name
        if class_id in already_done:
            print(f"Bo qua {class_id} (da co ket qua: {results[class_id]['name_en']})")
            continue

        print(f"Dang xu ly {class_id}...")
        result = label_class(class_dir)

        if result == "NO_MORE_KEYS":
            print("\nDa dung het quota tat ca key. Chay lai script nay (ngay mai hoac khi co key moi) de tiep tuc.")
            break

        if result:
            results[class_id] = result
            print(f"  -> {result['name_vi']} ({result['name_en']}) [{result['confidence']}]")
        else:
            results[class_id] = {"name_vi": "UNKNOWN", "name_en": "unknown", "confidence": "low"}
            print(f"  -> Khong xac dinh duoc sau {MAX_RETRIES} lan thu")

        save_results(results)
        time.sleep(1)

    print(f"\nDa luu ket qua vao {OUTPUT_FILE}")
    unknown_count = sum(1 for v in results.values() if v.get("name_en") == "unknown")
    done_count = sum(1 for v in results.values() if v.get("name_en") not in (None, "unknown"))
    print(f"Da xong: {done_count}/68 class. Con lai: {68 - done_count}.")
    if unknown_count == 0 and done_count == 68:
        print("Tat ca 68 class deu da co ket qua!")

if __name__ == "__main__":
    main()