"""
Tu dong gan bounding box cho dataset trai cay cua do an cu (FruitScan AI).

Dataset cu dung cho MobileNetV2 (phan loai) nen chi co THU MUC THEO LOP,
khong co toa do box. Script nay dung YOLO-World (mo hinh nhan dien theo
tu khoa, khong can train) de tim khung trai cay trong tung anh, con TEN LOP
lay theo ten thu muc chua anh. Ket qua la dataset dinh dang YOLO de train
YOLO26.

Chay trong thu muc backend/:
    python autolabel_fruit.py

Ho tro 2 kieu sap xep dataset cu:
    fruit_dataset/<lop>/*.jpg                    -> tu chia train/val/test 80/10/10
    fruit_dataset/train|val|valid|test/<lop>/*.jpg -> giu nguyen cach chia

Dau ra (thu muc dataset_fruit/):
    images/{train,val,test}/..., labels/{train,val,test}/...
    data.yaml                -> dung de train
    fruit_nutrition.csv      -> MAU dinh duong, can dien so lieu roi chay seed_fruits.py
    review_list.txt          -> anh KHONG tim thay khung (da gan khung ca anh), nen xem lai
    preview/                 -> 40 anh ve san khung de kiem tra bang mat

Lan dau chay, ultralytics se tu tai model YOLO-World va thu vien CLIP
(can co git tren may).
"""
import csv
import random
import shutil
from pathlib import Path

from PIL import Image, ImageDraw
from ultralytics import YOLO

# ---------------- CAU HINH ----------------
SRC = Path("fruit_dataset")        # thu muc dataset trai cay cu
OUT = Path("dataset_fruit")
WORLD_MODEL = "yolov8s-worldv2.pt"
PROMPTS = ["fruit"]                # tu khoa de YOLO-World tim khung
CONF = 0.10                        # nguong thap vi chi can tim VI TRI, ten lop da biet
MAX_BOXES_PER_IMAGE = 10
PREVIEW_COUNT = 40
SPLIT_RATIO = (0.8, 0.1, 0.1)
SEED = 42
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
VAL_FROM_TRAIN = 0.1   # neu dataset cu khong co thu muc val thi tach 10% train ra lam val
# ------------------------------------------


def list_images(folder):
    return sorted(p for p in folder.rglob("*") if p.suffix.lower() in IMAGE_EXTS)


def split_of(folder_name):
    """Nhan dien thu muc chia tap theo TU KHOA trong ten, vd Training_New,
    TestImages, valid... Tra ve None neu khong phai thu muc chia tap."""
    name = folder_name.lower()
    if "train" in name:
        return "train"
    if "val" in name:
        return "val"
    if "test" in name:
        return "test"
    return None


def class_root(split_dir):
    """Neu thu muc chia tap chi boc them 1 tang (vd Training_New/Training/...)
    thi di xuong tang chua cac thu muc lop."""
    current = split_dir
    while True:
        subdirs = [d for d in current.iterdir() if d.is_dir()]
        direct_images = [p for p in current.iterdir() if p.suffix.lower() in IMAGE_EXTS]
        if len(subdirs) == 1 and not direct_images:
            current = subdirs[0]
        else:
            return current


def collect_items():
    """Tra ve (danh sach lop, danh sach (duong dan anh, ten lop, split))."""
    subdirs = [d for d in SRC.iterdir() if d.is_dir()]
    has_splits = any(split_of(d.name) for d in subdirs)

    items = []
    class_names = set()

    if has_splits:
        for split_dir in subdirs:
            split = split_of(split_dir.name)
            if split is None:
                print(f"[Bo qua] {split_dir.name}: khong phai thu muc train/val/test")
                continue

            root = class_root(split_dir)
            loose = [p for p in root.iterdir() if p.suffix.lower() in IMAGE_EXTS]
            if loose:
                print(f"[Bo qua] {len(loose)} anh nam truc tiep trong {root} "
                      "(khong nam trong thu muc loai nao nen khong biet nhan)")

            class_dirs = sorted(d for d in root.iterdir() if d.is_dir())
            print(f"{split_dir.name} -> tap {split}: {len(class_dirs)} loai")
            for class_dir in class_dirs:
                class_names.add(class_dir.name)
                for img in list_images(class_dir):
                    items.append((img, class_dir.name, split))

        # Thieu tap val (vd chi co Training/ va Test/): tach mot phan train ra
        if not any(split == "val" for _, _, split in items):
            rng = random.Random(SEED)
            by_class = {}
            for i, (img, name, split) in enumerate(items):
                if split == "train":
                    by_class.setdefault(name, []).append(i)
            for indices in by_class.values():
                rng.shuffle(indices)
                for i in indices[: max(1, int(len(indices) * VAL_FROM_TRAIN))]:
                    img, name, _ = items[i]
                    items[i] = (img, name, "val")
            print(f"Khong co thu muc val -> da tach {int(VAL_FROM_TRAIN * 100)}% train lam val.")
    else:
        rng = random.Random(SEED)
        for class_dir in sorted(subdirs):
            class_names.add(class_dir.name)
            images = list_images(class_dir)
            rng.shuffle(images)
            n = len(images)
            n_train = int(n * SPLIT_RATIO[0])
            n_val = int(n * SPLIT_RATIO[1])
            for i, img in enumerate(images):
                split = "train" if i < n_train else "val" if i < n_train + n_val else "test"
                items.append((img, class_dir.name, split))

    return sorted(class_names), items


def find_boxes(model, img_path):
    """Tra ve danh sach box (xc, yc, w, h) chuan hoa 0-1. Rong neu khong tim thay."""
    result = model.predict(str(img_path), conf=CONF, verbose=False)[0]
    if result.boxes is None or len(result.boxes) == 0:
        return []

    order = result.boxes.conf.argsort(descending=True)[:MAX_BOXES_PER_IMAGE]
    return [tuple(float(v) for v in result.boxes.xywhn[i].tolist()) for i in order]


def draw_preview(src, dst, boxes, label):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    draw = ImageDraw.Draw(im)
    for xc, yc, bw, bh in boxes:
        x1, y1 = (xc - bw / 2) * w, (yc - bh / 2) * h
        x2, y2 = (xc + bw / 2) * w, (yc + bh / 2) * h
        draw.rectangle([x1, y1, x2, y2], outline=(255, 80, 0), width=3)
        draw.text((x1 + 4, y1 + 4), label, fill=(255, 80, 0))
    im.save(dst)


def main():
    if not SRC.exists():
        print(f"Khong thay thu muc {SRC}. Sua bien SRC o dau file cho dung.")
        return

    class_names, items = collect_items()
    if not items:
        print("Khong tim thay anh nao.")
        return

    class_to_id = {name: i for i, name in enumerate(class_names)}
    print(f"{len(class_names)} lop, {len(items)} anh.")

    if OUT.exists():
        shutil.rmtree(OUT)
    for split in ("train", "val", "test"):
        (OUT / "images" / split).mkdir(parents=True)
        (OUT / "labels" / split).mkdir(parents=True)
    (OUT / "preview").mkdir()

    model = YOLO(WORLD_MODEL)
    model.set_classes(PROMPTS)

    review = []
    previews_done = 0

    for idx, (img_path, class_name, split) in enumerate(items, 1):
        class_id = class_to_id[class_name]
        stem = f"{class_name}_{img_path.stem}_{idx}"
        dst_img = OUT / "images" / split / f"{stem}{img_path.suffix.lower()}"
        dst_lbl = OUT / "labels" / split / f"{stem}.txt"

        shutil.copy2(img_path, dst_img)

        try:
            boxes = find_boxes(model, img_path)
        except Exception as e:
            print(f"  Loi doc anh {img_path}: {e}")
            dst_img.unlink(missing_ok=True)
            continue

        if not boxes:
            # Anh phan loai thuong chi chua trai cay, nen gan khung gan ca anh
            boxes = [(0.5, 0.5, 0.96, 0.96)]
            review.append(str(dst_img))

        with open(dst_lbl, "w", encoding="utf-8") as f:
            for xc, yc, bw, bh in boxes:
                f.write(f"{class_id} {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}\n")

        if previews_done < PREVIEW_COUNT and idx % max(1, len(items) // PREVIEW_COUNT) == 0:
            draw_preview(img_path, OUT / "preview" / f"{stem}.jpg", boxes, class_name)
            previews_done += 1

        if idx % 200 == 0:
            print(f"  {idx}/{len(items)} anh...")

    data_yaml = (
        f"path: {OUT.resolve().as_posix()}\n"
        "train: images/train\n"
        "val: images/val\n"
        "test: images/test\n\n"
        f"nc: {len(class_names)}\n"
        f"names: {class_names}\n"
    )
    (OUT / "data.yaml").write_text(data_yaml, encoding="utf-8")

    with open(OUT / "fruit_nutrition.csv", "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["class_id", "name_en", "name_vi", "calories_per_100g",
                         "protein_g", "fat_g", "carbs_g", "fiber_g"])
        for name, cid in class_to_id.items():
            writer.writerow([cid, name, "", "", "", "", "", ""])

    (OUT / "review_list.txt").write_text("\n".join(review), encoding="utf-8")

    print("\nXong!")
    print(f"- Dataset YOLO: {OUT}/ (data.yaml da tao)")
    print(f"- {len(review)} anh khong tim thay khung, da gan khung ca anh -> xem review_list.txt")
    print(f"- Xem thu {previews_done} anh trong {OUT}/preview/ de kiem tra khung")
    print(f"- Dien dinh duong vao {OUT}/fruit_nutrition.csv roi chay: python seed_fruits.py")


if __name__ == "__main__":
    main()