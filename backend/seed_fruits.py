"""
Nap dinh duong trai cay vao bang 'foods' tren Supabase.

Trai cay dung id = 1000 + class_id (class cua model trai cay bat dau lai tu 0,
nen cong 1000 de khong trung voi 68 mon an id 0-67). app.py tra cuu theo
dung quy uoc nay (FRUIT_ID_OFFSET).

Truoc khi chay: dien day du cot name_vi va dinh duong (tren 100g) trong
dataset_fruit/fruit_nutrition.csv (co the lay tu bang dinh duong trai cay
cua do an FruitScan AI).

Chay trong thu muc backend/:
    python seed_fruits.py
Sau do: curl -X POST http://localhost:5000/foods/reload-cache
"""
import csv
import os

from dotenv import load_dotenv
from supabase import create_client

CSV_PATH = "dataset_fruit/fruit_nutrition.csv"
FRUIT_ID_OFFSET = 1000
NUMBER_FIELDS = ["calories_per_100g", "protein_g", "fat_g", "carbs_g", "fiber_g"]

load_dotenv()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def main():
    with open(CSV_PATH, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    missing = [r["name_en"] for r in rows if not r["name_vi"].strip() or not r["calories_per_100g"].strip()]
    if missing:
        print("Chua dien du name_vi / calories_per_100g cho:", ", ".join(missing))
        print("Dien xong roi chay lai.")
        return

    ok, failed = 0, 0
    for r in rows:
        record = {
            "id": FRUIT_ID_OFFSET + int(r["class_id"]),
            "name_en": r["name_en"].strip(),
            "name_vi": r["name_vi"].strip(),
            "category": "trái cây",
        }
        for field in NUMBER_FIELDS:
            value = r.get(field, "").strip()
            record[field] = float(value) if value else 0

        try:
            supabase.table("foods").upsert(record).execute()
            ok += 1
        except Exception as e:
            failed += 1
            print(f"  Loi voi {record['name_en']}: {e}")

    print(f"\nHoan tat: {ok} thanh cong, {failed} loi.")
    print("Nho goi: curl -X POST http://localhost:5000/foods/reload-cache")


if __name__ == "__main__":
    main()