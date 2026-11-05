"""
Goi lai Gemini rieng cho cac class bi trung ten, yeu cau doan ten CU THE hon
(vd: thay vi chi noi "banh mi" chung chung, co gang phan biet "banh mi thit",
"banh mi trung", "banh mi cha"...) vi day la cac class KHAC NHAU trong dataset.

Chay trong thu muc backend/ (da co .env voi GEMINI_API_KEY, co the nhieu key
cach nhau bang dau phay):
    python relabel_duplicates.py
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
    raise SystemExit("Chua co GEMINI_API_KEY trong .env")

MODEL_NAME = "gemini-3.6-flash"
SAMPLES_DIR = Path("class_samples")
SUGGESTED_FILE = Path("class_names_suggested.json")

current_key_index = 0

def get_client():
    return genai.Client(api_key=API_KEYS[current_key_index])

def switch_key():
    global current_key_index
    if current_key_index < len(API_KEYS) - 1:
        current_key_index += 1
        return True
    return False

PROMPT = """Day la {n} anh crop can canh cua CUNG MOT loai mon an Viet Nam.

QUAN TRONG: Lan truoc ban da doan mon nay la "{previous_guess}", nhung day THUC RA
la mot class RIENG BIET voi cac class khac cung ten trong dataset nay. Cac class
trung ten hien tai: {sibling_classes}.

Hay nhin that ky va co gang xac dinh BIEN THE CU THE cua mon nay de phan biet voi
cac class kia - vi du neu la "banh mi" thi phan biet ro la banh mi gi (banh mi thit,
banh mi trung, banh mi cha, banh mi xiu mai, banh mi op la...), neu la "bun bo hue"
thi xem co phai bien the khac nhu "bun bo hue chay", "bun bo gio heo"...

Neu that su khong the phan biet duoc (anh qua giong het nhau, khong co chi tiet gi
khac), thi giu nguyen ten cu va ghi ro trong "note".

Tra loi CHINH XAC theo JSON, khong them chu nao khac:
{{"name_vi": "<ten mon tieng Viet cu the>", "name_en": "<ten khong dau, snake_case>", "confidence": "<high/medium/low>", "note": "<giai thich ngan gon tai sao chon ten nay, hoac neu khong phan biet duoc>"}}
"""

def relabel_class(class_dir, previous_guess, sibling_classes):
    image_files = sorted(class_dir.glob("*.jpg"))[:5]
    if not image_files:
        return None

    prompt = PROMPT.format(
        n=len(image_files),
        previous_guess=previous_guess,
        sibling_classes=", ".join(sibling_classes),
    )

    for attempt in range(3):
        client = get_client()
        try:
            uploaded = [client.files.upload(file=str(f)) for f in image_files]
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
            print(f"    Loi: {e}")
            if "RESOURCE_EXHAUSTED" in str(e) or "429" in str(e):
                if switch_key():
                    print(f"    -> Chuyen key #{current_key_index + 1}")
                    continue
                else:
                    return "NO_MORE_KEYS"
            time.sleep(5)
    return None

def main():
    with open(SUGGESTED_FILE, "r", encoding="utf-8") as f:
        results = json.load(f)

    # Tim cac name_en bi trung
    name_to_classes = {}
    for class_id, info in results.items():
        name = info.get("name_en", "")
        name_to_classes.setdefault(name, []).append(class_id)

    duplicate_groups = {name: ids for name, ids in name_to_classes.items() if len(ids) > 1}

    if not duplicate_groups:
        print("Khong tim thay class nao bi trung ten!")
        return

    print(f"Tim thay {len(duplicate_groups)} nhom bi trung ten:")
    for name, ids in duplicate_groups.items():
        print(f"  '{name}': {ids}")
    print()

    for name, class_ids in duplicate_groups.items():
        print(f"\n=== Xu ly nhom '{name}' ({class_ids}) ===")
        for class_id in class_ids:
            class_dir = SAMPLES_DIR / class_id
            print(f"  Dang xu ly {class_id}...")
            sibling_classes = [f"{cid} (cung ten '{name}')" for cid in class_ids if cid != class_id]
            result = relabel_class(class_dir, name, sibling_classes)

            if result == "NO_MORE_KEYS":
                print("  Het quota tat ca key, dung tai day. Chay lai script sau de tiep tuc.")
                with open(SUGGESTED_FILE, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False, indent=2)
                return

            if result:
                results[class_id] = {
                    "name_vi": result["name_vi"],
                    "name_en": result["name_en"],
                    "confidence": result["confidence"],
                }
                note = result.get("note", "")
                print(f"    -> {result['name_vi']} ({result['name_en']}) [{result['confidence']}] - {note}")
            else:
                print(f"    -> Khong xu ly duoc, giu nguyen ten cu")

            time.sleep(1)

    with open(SUGGESTED_FILE, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print(f"\nDa cap nhat {SUGGESTED_FILE}. Xem lai ket qua, sau do chay update_data_yaml.py")
    print("va cap nhat lai seed_foods.py + chay lai (upsert an toan).")

if __name__ == "__main__":
    main()