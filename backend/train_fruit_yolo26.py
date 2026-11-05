"""
Train YOLO26 nhan dien trai cay tren dataset da tu gan box (autolabel_fruit.py).

Chay trong thu muc backend/:
    python train_fruit_yolo26.py

Train xong copy best.pt thanh models/fruit_detector.pt, khoi dong lai
server: app se tu quet CHUNG do an + trai cay.
"""
from pathlib import Path

from ultralytics import YOLO

DATA_YAML = str(Path(__file__).resolve().parent / "dataset_fruit" / "data.yaml")
BASE_MODEL = "yolo26s.pt"
# Duong dan TUYET DOI: ultralytics ban moi tu nhet thu muc tuong doi vao
# runs/detect/..., lam lech cho luu va hong che do resume.
BACKEND_DIR = Path(__file__).resolve().parent
PROJECT = str(BACKEND_DIR / "runs_fruit_detect")
RUN_NAME = "yolo26s_fruit"

EPOCHS = 60
IMGSZ = 512
BATCH = 8          # "CUDA out of memory" -> giam xuong 4
WORKERS = 2
PATIENCE = 15


def main():
    last_ckpt = Path(PROJECT) / RUN_NAME / "weights" / "last.pt"

    if not last_ckpt.exists() and not Path(DATA_YAML).exists():
        print(f"Khong tim thay {DATA_YAML}")
        print("Chay python autolabel_fruit.py truoc de tao dataset trai cay.")
        return

    if last_ckpt.exists():
        print(f"Tim thay checkpoint {last_ckpt} -> tiep tuc train (resume).")
        YOLO(str(last_ckpt)).train(resume=True)
    else:
        YOLO(BASE_MODEL).train(
            data=DATA_YAML,
            epochs=EPOCHS,
            imgsz=IMGSZ,
            batch=BATCH,
            device=0,
            workers=WORKERS,
            patience=PATIENCE,
            cache=False,
            amp=True,
            project=PROJECT,
            name=RUN_NAME,
            exist_ok=True,
            plots=True,
        )

    best = Path(PROJECT) / RUN_NAME / "weights" / "best.pt"
    print(f"\nTrain xong! Copy {best} thanh models/fruit_detector.pt")


if __name__ == "__main__":
    main()