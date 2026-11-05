"""
Danh gia va so sanh cac model tren CUNG mot tap test (lay so lieu cho bao cao).

Chay trong thu muc backend/:
    python eval_models.py

Ket qua:
- In bang so sanh ra man hinh
- Luu eval_results.json (de dan vao bao cao)
- Moi model co thu muc runs_eval/<ten>/ chua confusion matrix, PR curve
"""
import json
import time
from pathlib import Path

from ultralytics import YOLO

BACKEND_DIR = Path(__file__).resolve().parent
DATA_YAML = str(BACKEND_DIR / "dataset" / "data.yaml")
IMGSZ = 480
SPLIT = "test"   # tap test doc lap; neu data.yaml khong co test thi doi thanh "val"

# Ten hien thi -> duong dan file trong so. File nao chua co se tu bo qua.
MODELS = {
    "YOLOv8s (cu, 30% data)": str(BACKEND_DIR / "models" / "food_detector.pt"),
    "YOLO26s (moi)": str(BACKEND_DIR / "models" / "food_detector_yolo26.pt"),
}


def model_size_mb(path):
    return Path(path).stat().st_size / (1024 * 1024)


def evaluate(name, path):
    model = YOLO(path)
    metrics = model.val(
        data=DATA_YAML,
        split=SPLIT,
        imgsz=IMGSZ,
        batch=8,
        device=0,
        plots=True,
        project=str(BACKEND_DIR / "runs_eval"),
        name=name.split(" ")[0],
        exist_ok=True,
        verbose=False,
    )
    speed = metrics.speed  # ms / anh: preprocess, inference, postprocess
    return {
        "model": name,
        "weights": path,
        "mAP50": round(float(metrics.box.map50), 4),
        "mAP50_95": round(float(metrics.box.map), 4),
        "precision": round(float(metrics.box.mp), 4),
        "recall": round(float(metrics.box.mr), 4),
        "inference_ms_per_image": round(float(speed.get("inference", 0)), 2),
        "size_mb": round(model_size_mb(path), 1),
    }


def main():
    results = []
    for name, path in MODELS.items():
        if not Path(path).exists():
            print(f"[Bo qua] Chua co file: {path}")
            continue
        print(f"\n=== Dang danh gia: {name} ===")
        start = time.time()
        results.append(evaluate(name, path))
        print(f"Xong sau {time.time() - start:.0f}s")

    if not results:
        print("Khong co model nao de danh gia.")
        return

    header = f"{'Model':<26}{'mAP50':>8}{'mAP50-95':>10}{'P':>8}{'R':>8}{'ms/anh':>9}{'MB':>7}"
    print("\n" + header)
    print("-" * len(header))
    for r in results:
        print(
            f"{r['model']:<26}{r['mAP50']:>8}{r['mAP50_95']:>10}"
            f"{r['precision']:>8}{r['recall']:>8}"
            f"{r['inference_ms_per_image']:>9}{r['size_mb']:>7}"
        )

    with open(BACKEND_DIR / "eval_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("\nDa luu eval_results.json va bieu do trong runs_eval/")


if __name__ == "__main__":
    main()