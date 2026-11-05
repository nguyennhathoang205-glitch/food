"""
Train YOLO26 tren dataset VietFood68 (68 mon an Viet).

Chay trong thu muc backend/ (da active venv, da co dataset/data.yaml):
    pip install -U ultralytics      # can ban moi de co YOLO26
    python train_yolo26.py

- Tu dong RESUME neu lan truoc bi ngat giua chung (mat dien, tat may...).
- Toi uu cho GTX 1660 Super 6GB VRAM + 16GB RAM.
- Model YOLOv8 cu (models/food_detector.pt) giu nguyen de so sanh trong bao cao.
"""
from pathlib import Path

from ultralytics import YOLO

# ---------------- CAU HINH ----------------
DATA_YAML = str(Path(__file__).resolve().parent / "dataset" / "data.yaml")
BASE_MODEL = "yolo26s.pt"      # ban s: can bang do chinh xac / toc do cho GPU 6GB
# Duong dan TUYET DOI: ultralytics ban moi tu nhet thu muc tuong doi vao
# runs/detect/..., lam lech cho luu va hong che do resume.
BACKEND_DIR = Path(__file__).resolve().parent
PROJECT = str(BACKEND_DIR / "runs_food_detect")
RUN_NAME = "yolo26s_30pct"

EPOCHS = 30                    # giong YOLOv8 cu de so sanh cong bang
IMGSZ = 480                    # giong YOLOv8 cu de so sanh cong bang
BATCH = 12                     # neu bao "CUDA out of memory" thi giam xuong 8
WORKERS = 2                    # 4 worker lam het RAM 16GB luc validate (da gap loi) -> 2
PATIENCE = 15                  # dung som neu 15 epoch lien tiep khong cai thien

# Dataset co ~160k anh train (phan lon la ban augment san cua ~33k anh goc).
# Train 100% mat ~4 tieng/epoch tren GTX 1660 Super -> dung 30% nhu YOLOv8 cu:
# vua kip thoi gian, vua so sanh cong bang (cung du lieu, epoch, kich thuoc anh).
FRACTION = 0.3
# ------------------------------------------


def main():
    last_ckpt = Path(PROJECT) / RUN_NAME / "weights" / "last.pt"

    if not last_ckpt.exists() and not Path(DATA_YAML).exists():
        print(f"Khong tim thay {DATA_YAML}")
        print("Dataset VietFood68 phai nam o backend/dataset/ (co data.yaml, images/, labels/).")
        return

    if last_ckpt.exists():
        print(f"Tim thay checkpoint {last_ckpt} -> tiep tuc train (resume).")
        model = YOLO(str(last_ckpt))
        model.train(resume=True)
    else:
        model = YOLO(BASE_MODEL)
        model.train(
            data=DATA_YAML,
            epochs=EPOCHS,
            imgsz=IMGSZ,
            batch=BATCH,
            device=0,
            workers=WORKERS,
            patience=PATIENCE,
            fraction=FRACTION,
            cache=False,        # khong cache anh vao RAM (dataset qua lon cho 16GB)
            amp=True,
            project=PROJECT,
            name=RUN_NAME,
            exist_ok=True,
            plots=True,         # luu bieu do loss, PR curve, confusion matrix
        )

    best = Path(PROJECT) / RUN_NAME / "weights" / "best.pt"
    print("\nTrain xong!")
    print(f"Model tot nhat: {best}")
    print("Buoc tiep theo: copy file nay vao models/food_detector_yolo26.pt")
    print("roi chay: python eval_models.py")


if __name__ == "__main__":
    main()