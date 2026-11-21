"""Danh gia "day AI mon moi bang vai anh" (few-shot) - lay so lieu cho bao cao.

Cau hoi can tra loi: neu cong dong chi day moi mon bang K anh (K = 1, 3, 5),
he thong nhan dung bao nhieu phan tram? Va nguong do tuong dong nen dat bao nhieu?

Cach lam (khong can Supabase, chay hoan toan tren may):
1. Cat cac mon tu tap TEST cua VietFood68 theo bounding box -> anh tung mon.
2. Voi moi lop: lay ngau nhien K anh lam "anh cong dong day" (support),
   cac anh con lai lam "anh nguoi dung chup" (query).
3. Vector hoa bang CLIP, xep hang bang DUNG ham rank_foods() ma server dung.
4. Lap lai voi nhieu hat giong ngau nhien, lay trung binh.

Chay trong thu muc backend/ (can dataset/images/test va dataset/labels/test):
    python eval_fewshot.py

Ket qua: in bang + luu eval_fewshot_results.json.
"""

import json
import random
from collections import defaultdict
from pathlib import Path

from PIL import Image

import community_foods

BACKEND_DIR = Path(__file__).resolve().parent
IMAGE_DIR = BACKEND_DIR / "dataset" / "images" / "test"
LABEL_DIR = BACKEND_DIR / "dataset" / "labels" / "test"
OUTPUT = BACKEND_DIR / "eval_fewshot_results.json"

K_VALUES = (1, 3, 5)
SEEDS = (0, 1, 2)
QUERIES_PER_CLASS = 15      # so anh thu cho moi lop
MIN_CROP_SIDE = 64          # bo qua box qua nho (khong du chi tiet)
THRESHOLDS = [round(0.60 + 0.02 * i, 2) for i in range(18)]   # 0.60 .. 0.94


def collect_crops(max_per_class):
    """Tra ve {class_id: [anh PIL da cat]} tu tap test."""
    boxes_by_class = defaultdict(list)

    for label_file in sorted(LABEL_DIR.glob("*.txt")):
        for line in label_file.read_text(encoding="utf-8").splitlines():
            parts = line.split()

            if len(parts) < 5:
                continue

            class_id = int(parts[0])
            boxes_by_class[class_id].append(
                (label_file.stem, tuple(float(v) for v in parts[1:5]))
            )

    rng = random.Random(1234)
    crops = {}

    for class_id, boxes in sorted(boxes_by_class.items()):
        rng.shuffle(boxes)
        kept = []

        for stem, (xc, yc, w, h) in boxes:
            if len(kept) >= max_per_class:
                break

            image_path = next(
                (IMAGE_DIR / f"{stem}{ext}" for ext in (".jpg", ".jpeg", ".png")
                 if (IMAGE_DIR / f"{stem}{ext}").exists()),
                None,
            )

            if image_path is None:
                continue

            try:
                image = Image.open(image_path).convert("RGB")
            except Exception:
                continue

            iw, ih = image.size
            box = (
                int((xc - w / 2) * iw), int((yc - h / 2) * ih),
                int((xc + w / 2) * iw), int((yc + h / 2) * ih),
            )
            box = (max(0, box[0]), max(0, box[1]), min(iw, box[2]), min(ih, box[3]))

            if box[2] - box[0] < MIN_CROP_SIDE or box[3] - box[1] < MIN_CROP_SIDE:
                continue

            kept.append(image.crop(box))

        if len(kept) > max(K_VALUES):
            crops[class_id] = kept

    return crops


def cosine(a, b):
    """Vector da chuan hoa -> cosine = tich vo huong."""
    return sum(x * y for x, y in zip(a, b))


def evaluate(vectors, k, seed, thresholds=THRESHOLDS):
    """vectors: {class_id: [vector]}. Tra ve so lieu cho 1 lan chay.

    - top1 / top3: xep hang dung mon (khong xet nguong).
    - Theo tung nguong: accept_correct = ti le anh duoc nhan DUNG va vuot nguong;
      false_accept = ti le anh cua mon CHUA AI DAY nhung van bi nhan thanh mon
      khac (mo phong bang cach bo lop do ra khoi kho, kieu "leave-one-class-out").
    """
    rng = random.Random(seed)
    support = []   # (class_id, vector)
    queries = []   # (class_id, vector)

    for class_id, vecs in vectors.items():
        order = list(range(len(vecs)))
        rng.shuffle(order)

        for i in order[:k]:
            support.append((class_id, vecs[i]))

        for i in order[k:k + QUERIES_PER_CLASS]:
            queries.append((class_id, vecs[i]))

    top1 = top3 = 0
    accept_correct = {t: 0 for t in thresholds}
    false_accept = {t: 0 for t in thresholds}

    for true_class, qvec in queries:
        sims = [
            {"food_id": cid, "name_vi": str(cid), "similarity": cosine(qvec, svec)}
            for cid, svec in support
        ]

        # 1) Mon DA duoc day: xep hang tren toan bo kho
        nearest = sorted(sims, key=lambda r: r["similarity"], reverse=True)[:12]
        ranked = community_foods.rank_foods(nearest, threshold=0.0, min_margin=0.0)
        names = [c["food_id"] for c in ranked["candidates"]]

        top1 += names[:1] == [true_class]
        top3 += true_class in names

        for t in thresholds:
            best = community_foods.rank_foods(nearest, threshold=t)["best"]
            accept_correct[t] += bool(best) and best["food_id"] == true_class

        # 2) Mon CHUA duoc day: bo lop that ra khoi kho, he thong phai tu choi
        others = [r for r in sims if r["food_id"] != true_class]
        nearest_others = sorted(others, key=lambda r: r["similarity"], reverse=True)[:12]

        for t in thresholds:
            best = community_foods.rank_foods(nearest_others, threshold=t)["best"]
            false_accept[t] += bool(best)

    n = max(len(queries), 1)

    return {
        "queries": len(queries),
        "top1": top1 / n,
        "top3": top3 / n,
        "accept_correct": {t: v / n for t, v in accept_correct.items()},
        "false_accept": {t: v / n for t, v in false_accept.items()},
    }


def average(runs, thresholds=THRESHOLDS):
    m = len(runs)

    return {
        "queries": runs[0]["queries"],
        "top1": sum(r["top1"] for r in runs) / m,
        "top3": sum(r["top3"] for r in runs) / m,
        "accept_correct": {
            t: sum(r["accept_correct"][t] for r in runs) / m for t in thresholds
        },
        "false_accept": {
            t: sum(r["false_accept"][t] for r in runs) / m for t in thresholds
        },
    }


def best_threshold(result, max_false_accept=0.05, thresholds=THRESHOLDS):
    """Nguong THAP nhat ma ti le nhan nham mon chua day <= 5% (giu duoc nhieu
    lan nhan dung nhat trong khi van an toan)."""
    for t in thresholds:
        if result["false_accept"][t] <= max_false_accept:
            return t

    return thresholds[-1]


def main():
    if not LABEL_DIR.exists() or not IMAGE_DIR.exists():
        print(f"Khong thay {IMAGE_DIR} / {LABEL_DIR}.")
        print("Can tap TEST cua VietFood68 trong backend/dataset/.")
        return

    print("Dang cat anh tung mon tu tap test...")
    crops = collect_crops(max_per_class=max(K_VALUES) + QUERIES_PER_CLASS)
    total = sum(len(v) for v in crops.values())
    print(f"{len(crops)} lop, {total} anh. Dang vector hoa bang CLIP...")

    vectors = {}

    for class_id, images in crops.items():
        vectors[class_id] = community_foods.embed_images(images)

    results = {}

    for k in K_VALUES:
        runs = [evaluate(vectors, k, seed) for seed in SEEDS]
        results[k] = average(runs)

    header = f"{'So anh day (K)':<16}{'Top-1':>8}{'Top-3':>8}{'Nguong':>9}{'Nhan dung':>11}{'Nhan nham':>11}"
    print("\n" + header)
    print("-" * len(header))

    summary = []

    for k in K_VALUES:
        r = results[k]
        t = best_threshold(r)
        row = {
            "k": k,
            "classes": len(vectors),
            "queries": r["queries"],
            "top1": round(r["top1"], 4),
            "top3": round(r["top3"], 4),
            "suggested_threshold": t,
            "accept_correct_at_threshold": round(r["accept_correct"][t], 4),
            "false_accept_at_threshold": round(r["false_accept"][t], 4),
            "by_threshold": {
                str(th): {
                    "accept_correct": round(r["accept_correct"][th], 4),
                    "false_accept": round(r["false_accept"][th], 4),
                }
                for th in THRESHOLDS
            },
        }
        summary.append(row)
        print(
            f"{k:<16}{row['top1']:>8.1%}{row['top3']:>8.1%}{t:>9.2f}"
            f"{row['accept_correct_at_threshold']:>11.1%}"
            f"{row['false_accept_at_threshold']:>11.1%}"
        )

    OUTPUT.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nDa luu {OUTPUT.name}.")
    print("Dat nguong de xuat (dong K=3) vao .env: COMMUNITY_MATCH_THRESHOLD=<nguong>")


if __name__ == "__main__":
    main()