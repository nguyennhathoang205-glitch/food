"""
Tu dong dien ten tieng Viet + dinh duong (tren 100g) vao
dataset_fruit/fruit_nutrition.csv dua theo ten thu muc lop (cot name_en).

Chay trong thu muc backend/:
    python fill_fruit_nutrition.py
    python seed_fruits.py

- Nhan ca ten tieng Anh (Apple Red 1, Banana Lady Finger...) lan tieng Viet
  khong dau (tao, chuoi, xoai, thanh_long...).
- Chi dien dong con TRONG, khong ghi de dong ban da tu dien.
- Lop nao khong nhan ra se in ra cuoi cung -> mo file CSV dien tay dong do.

So lieu la gia tri tham khao pho bien (tuong duong USDA FoodData Central).
Truoc khi dua vao bao cao nen doi chieu lai voi Bang thanh phan thuc pham
Viet Nam (Vien Dinh duong Quoc gia).
"""
import csv
import unicodedata

CSV_PATH = "dataset_fruit/fruit_nutrition.csv"

# (cac ten nhan dien, ten tieng Viet, kcal, dam, beo, carb, xo) tren 100g
FRUITS = [
    (["custard apple", "sugar apple", "mang cau", "na"], "Mãng cầu ta", 101, 1.7, 0.6, 25.2, 2.4),
    (["soursop", "mang cau xiem"], "Mãng cầu xiêm", 66, 1.0, 0.3, 16.8, 3.3),
    (["pineapple", "dua thom", "thom", "khom"], "Dứa (thơm)", 50, 0.5, 0.1, 13.1, 1.4),
    (["watermelon", "dua hau"], "Dưa hấu", 30, 0.6, 0.2, 7.6, 0.4),
    (["cantaloupe", "melon", "dua luoi", "dua gang"], "Dưa lưới", 34, 0.8, 0.2, 8.2, 0.9),
    (["coconut", "dua xiem", "dua tuoi"], "Dừa (cơm dừa)", 354, 3.3, 33.5, 15.2, 9.0),
    (["grapefruit", "pomelo", "buoi"], "Bưởi", 38, 0.8, 0.0, 9.6, 1.0),
    (["dragon fruit", "dragonfruit", "pitahaya", "pitaya", "thanh long", "dragon"], "Thanh long", 60, 1.2, 0.0, 13.0, 3.0),
    (["blackberry", "mam xoi den"], "Mâm xôi đen", 43, 1.4, 0.5, 9.6, 5.3),
    (["star fruit", "starfruit", "carambola", "khe"], "Khế", 31, 1.0, 0.3, 6.7, 2.8),
    (["passion fruit", "passionfruit", "maracuja", "chanh day"], "Chanh dây", 97, 2.2, 0.7, 23.4, 10.4),
    (["apple", "tao"], "Táo", 52, 0.3, 0.2, 13.8, 2.4),
    (["banana", "chuoi"], "Chuối", 89, 1.1, 0.3, 22.8, 2.6),
    (["mandarin", "tangerine", "quyt"], "Quýt", 53, 0.8, 0.3, 13.3, 1.8),
    (["orange", "cam"], "Cam", 47, 0.9, 0.1, 11.8, 2.4),
    (["mango", "xoai"], "Xoài", 60, 0.8, 0.4, 15.0, 1.6),
    (["grape", "nho"], "Nho", 69, 0.7, 0.2, 18.1, 0.9),
    (["strawberry", "dau tay", "dau"], "Dâu tây", 32, 0.7, 0.3, 7.7, 2.0),
    (["blueberry", "viet quat"], "Việt quất", 57, 0.7, 0.3, 14.5, 2.4),
    (["raspberry", "mam xoi"], "Mâm xôi", 52, 1.2, 0.7, 11.9, 6.5),
    (["papaya", "du du"], "Đu đủ", 43, 0.5, 0.3, 10.8, 1.7),
    (["guava", "oi"], "Ổi", 68, 2.6, 1.0, 14.3, 5.4),
    (["lemon", "chanh vang"], "Chanh vàng", 29, 1.1, 0.3, 9.3, 2.8),
    (["lime", "chanh"], "Chanh", 30, 0.7, 0.2, 10.5, 2.8),
    (["kiwi"], "Kiwi", 61, 1.1, 0.5, 14.7, 3.0),
    (["pear", "le"], "Lê", 57, 0.4, 0.1, 15.2, 3.1),
    (["peach", "nectarine", "dao"], "Đào", 39, 0.9, 0.3, 9.5, 1.5),
    (["plum", "man"], "Mận", 46, 0.7, 0.3, 11.4, 1.4),
    (["cherry", "anh dao"], "Cherry", 63, 1.1, 0.2, 16.0, 2.1),
    (["apricot", "mo"], "Mơ", 48, 1.4, 0.4, 11.1, 2.0),
    (["avocado", "bo"], "Bơ", 160, 2.0, 14.7, 8.5, 6.7),
    (["pomegranate", "luu"], "Lựu", 83, 1.7, 1.2, 18.7, 4.0),
    (["durian", "sau rieng"], "Sầu riêng", 147, 1.5, 5.3, 27.1, 3.8),
    (["jackfruit", "mit"], "Mít", 95, 1.7, 0.6, 23.2, 1.5),
    (["longan", "nhan"], "Nhãn", 60, 1.3, 0.1, 15.1, 1.1),
    (["lychee", "litchi", "vai"], "Vải", 66, 0.8, 0.4, 16.5, 1.3),
    (["rambutan", "chom chom"], "Chôm chôm", 82, 0.7, 0.2, 20.9, 0.9),
    (["mangosteen", "mang cut"], "Măng cụt", 73, 0.4, 0.6, 18.0, 1.8),
    (["sapodilla", "hong xiem", "sapoche"], "Hồng xiêm", 83, 0.4, 1.1, 20.0, 5.3),
    (["persimmon", "kaki", "hong"], "Hồng", 70, 0.6, 0.2, 18.6, 3.6),
    (["tomato", "ca chua"], "Cà chua", 18, 0.9, 0.2, 3.9, 1.2),
]


def normalize(text):
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = text.replace("đ", "d").replace("Đ", "D").lower()
    for ch in "_-./()":
        text = text.replace(ch, " ")
    text = "".join(c for c in text if not c.isdigit())
    return " " + " ".join(text.split()) + " "


# Ten dai duoc so truoc (vd "pineapple" truoc "apple", "dua hau" truoc "dua")
ALIASES = sorted(
    ((alias, entry) for entry in FRUITS for alias in entry[0]),
    key=lambda pair: -len(pair[0]),
)


def find(name_en):
    norm = normalize(name_en)
    for alias, entry in ALIASES:
        if f" {alias} " in norm:
            return entry
    return None


def main():
    with open(CSV_PATH, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
        fields = list(rows[0].keys()) if rows else []

    filled, unknown = 0, []
    for row in rows:
        if row["name_vi"].strip() and row["calories_per_100g"].strip():
            continue  # dong da dien tay -> giu nguyen
        entry = find(row["name_en"])
        if entry is None:
            unknown.append(row["name_en"])
            continue
        _, name_vi, kcal, protein, fat, carbs, fiber = entry
        row.update({
            "name_vi": name_vi,
            "calories_per_100g": kcal,
            "protein_g": protein,
            "fat_g": fat,
            "carbs_g": carbs,
            "fiber_g": fiber,
        })
        filled += 1

    with open(CSV_PATH, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Da dien {filled}/{len(rows)} lop.")
    if unknown:
        print("Khong nhan ra cac lop sau, mo file CSV dien tay:")
        for name in unknown:
            print("  -", name)
    else:
        print("Day du! Chay tiep: python seed_fruits.py")


if __name__ == "__main__":
    main()