"""
Train YOLOv8 tren dataset VietFood67 (68 class).

Chay trong thu muc backend/ (da active venv, da co dataset/data.yaml):
    python train.py

GPU: toi uu cho GTX 1660 Super 6GB VRAM.
"""
from ultralytics import YOLO

def main():
    # yolov8s = base tot cho may 6GB VRAM (nhanh, do chinh xac kha)
    model = YOLO("yolov8s.pt")

    model.train(
        data="dataset/data.yaml",
        epochs=30,          # giam so epoch vi dataset da rat lon (nhieu anh augment san)
        imgsz=480,          # giam tu 640 xuong 480 de giam tai GPU
        batch=16,
        device=0,
        workers=2,          # giam tu 4 xuong 2 de tranh het RAM he thong
        patience=10,        # dung som neu 10 epoch lien tiep khong cai thien
        project="runs_food_detect",
        name="v1",
        amp=True,
        fraction=0.3,       # chi dung 30% dataset moi epoch (~48k anh), du vi da co augment san
    )

    print("\nTrain xong! Model tot nhat luu tai: runs_food_detect/v1/weights/best.pt")

if __name__ == "__main__":
    main()