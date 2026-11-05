"""
Crop ra vài ảnh mẫu cho MỖI class (dựa theo bounding box trong label),
lưu vào class_samples/class_XX/ để xem và đặt tên món ăn thật.

Chạy trong thư mục backend/ (nơi có dataset/):
    pip install pillow
    python extract_class_samples.py
"""
import os
import random
from pathlib import Path
from collections import defaultdict
from PIL import Image

DATASET_DIR = Path("dataset")
OUTPUT_DIR = Path("class_samples")
SAMPLES_PER_CLASS = 5
SPLIT_TO_USE = "train"  # dùng train vì có nhiều ảnh nhất

def parse_label_line(line):
    parts = line.strip().split()
    class_id = int(parts[0])
    x_center, y_center, w, h = map(float, parts[1:5])
    return class_id, x_center, y_center, w, h

def crop_box(img, x_center, y_center, w, h):
    img_w, img_h = img.size
    x1 = int((x_center - w / 2) * img_w)
    y1 = int((y_center - h / 2) * img_h)
    x2 = int((x_center + w / 2) * img_w)
    y2 = int((y_center + h / 2) * img_h)
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(img_w, x2), min(img_h, y2)
    return img.crop((x1, y1, x2, y2))

def main():
    label_dir = DATASET_DIR / "labels" / SPLIT_TO_USE
    image_dir = DATASET_DIR / "images" / SPLIT_TO_USE

    label_files = list(label_dir.glob("*.txt"))
    print(f"Tổng số label file: {len(label_files)}")
    random.shuffle(label_files)

    # Gom danh sách (label_file, class_id, box) theo từng class
    class_boxes = defaultdict(list)
    for label_file in label_files:
        with open(label_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
        for line in lines:
            if not line.strip():
                continue
            class_id, x, y, w, h = parse_label_line(line)
            if len(class_boxes[class_id]) < SAMPLES_PER_CLASS * 3:
                # lưu nhiều hơn cần để sau random chọn, tránh ảnh trùng lặp quá nhiều
                class_boxes[class_id].append((label_file, x, y, w, h))

    OUTPUT_DIR.mkdir(exist_ok=True)
    print(f"Đang crop mẫu cho {len(class_boxes)} class...")

    for class_id in sorted(class_boxes.keys()):
        boxes = class_boxes[class_id][:SAMPLES_PER_CLASS]
        class_dir = OUTPUT_DIR / f"class_{class_id:02d}"
        class_dir.mkdir(exist_ok=True)

        for idx, (label_file, x, y, w, h) in enumerate(boxes):
            image_file = image_dir / (label_file.stem + ".jpg")
            if not image_file.exists():
                continue
            try:
                img = Image.open(image_file)
                crop = crop_box(img, x, y, w, h)
                crop.save(class_dir / f"sample_{idx}.jpg")
            except Exception as e:
                print(f"  Lỗi crop {image_file}: {e}")

        print(f"  class_{class_id:02d}: đã lưu {len(boxes)} ảnh mẫu")

    print(f"\nXong! Mở thư mục '{OUTPUT_DIR}' để xem ảnh mẫu từng class.")
    print("Mỗi class_XX/ chứa vài ảnh crop của món ăn thuộc class đó.")

if __name__ == "__main__":
    main()