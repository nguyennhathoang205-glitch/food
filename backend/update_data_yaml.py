"""
Đọc class_names_suggested.json (sau khi đã review/sửa tay)
và cập nhật lại dataset/data.yaml với tên thật.

Chạy trong thư mục backend/:
    python update_data_yaml.py
"""
import json
from pathlib import Path

SUGGESTED_FILE = Path("class_names_suggested.json")
DATA_YAML = Path("dataset") / "data.yaml"

def main():
    with open(SUGGESTED_FILE, "r", encoding="utf-8") as f:
        suggestions = json.load(f)

    num_classes = len(suggestions)
    names = []
    for i in range(num_classes):
        key = f"class_{i:02d}"
        entry = suggestions.get(key, {"name_en": key})
        names.append(entry["name_en"])

    yaml_content = f"""train: images/train
val: images/valid
test: images/test

nc: {num_classes}
names: {names}
"""
    with open(DATA_YAML, "w", encoding="utf-8") as f:
        f.write(yaml_content)

    print(f"Đã cập nhật {DATA_YAML} với {num_classes} tên món thật.")
    print("Danh sách:")
    for i, name in enumerate(names):
        print(f"  {i}: {name}")

if __name__ == "__main__":
    main()