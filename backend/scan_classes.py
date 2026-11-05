"""
Quét toàn bộ file label .txt trong dataset/labels/{train,valid,test}
để tìm các class index đang được dùng, đếm số lượng mỗi class,
và tạo data.yaml với tên tạm (class_00, class_01, ...).

Chạy trong thư mục backend/ (nơi có dataset/):
    python scan_classes.py
"""
import os
from pathlib import Path
from collections import Counter

DATASET_DIR = Path("dataset")
SPLITS = ["train", "valid", "test"]

def scan_labels():
    counter = Counter()
    total_files = 0
    for split in SPLITS:
        label_dir = DATASET_DIR / "labels" / split
        if not label_dir.exists():
            print(f"  Bỏ qua {label_dir} (không tồn tại)")
            continue
        txt_files = list(label_dir.glob("*.txt"))
        print(f"  {split}: {len(txt_files)} file label")
        for txt_file in txt_files:
            total_files += 1
            with open(txt_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    class_id = int(line.split()[0])
                    counter[class_id] += 1
    return counter, total_files

def main():
    print("Đang quét label files...")
    counter, total_files = scan_labels()

    if not counter:
        print("Không tìm thấy class nào trong label files!")
        return

    max_class = max(counter.keys())
    num_classes = max_class + 1

    print(f"\nTổng số file label đã quét: {total_files}")
    print(f"Số class tìm thấy: {len(counter)} (index từ 0 đến {max_class})")
    print(f"\nSố lượng annotation theo từng class:")
    for class_id in sorted(counter.keys()):
        print(f"  class_{class_id:02d}: {counter[class_id]} annotations")

    missing = [i for i in range(num_classes) if i not in counter]
    if missing:
        print(f"\nCẢNH BÁO: các class index sau không xuất hiện trong data: {missing}")

    # Tạo data.yaml với tên tạm
    names_list = [f"class_{i:02d}" for i in range(num_classes)]
    yaml_content = f"""train: images/train
val: images/valid
test: images/test

nc: {num_classes}
names: {names_list}
"""
    with open(DATASET_DIR / "data.yaml", "w", encoding="utf-8") as f:
        f.write(yaml_content)

    print(f"\nĐã tạo {DATASET_DIR / 'data.yaml'} với {num_classes} class tạm (class_00 ... class_{num_classes-1:02d})")
    print("Bước tiếp theo: xem ảnh mẫu từng class để đặt tên tiếng Việt thật cho từng món.")

if __name__ == "__main__":
    main()