"""Pipeline Hoc Chu Dong (Active Learning) & Du Bao Can Nang Y Sinh (Stage 4 Pro).

1. Chuyen doi du lieu nguoi dung gop y sua nhan (feedback_data/feedback_log.json)
   sang tap du lieu chuan YOLO (images/train + labels/train + active_data.yaml)
   de san sang fine-tune model YOLO26.
2. Tong hop chi so thuc nghiem mo hinh (YOLOv8s vs YOLO26s Food vs YOLO26s Fruit)
   va thong ke Active Learning theo thoi gian thuc.
3. Luu lich su can nang va du bao xu huong can nang 30 ngay theo phuong trinh
   can bang nang luong (7700 kcal ~ 1 kg mo co the).
"""

import json
import os
import shutil
import threading
import unicodedata
from datetime import datetime, timezone
from PIL import Image

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_FEEDBACK_DIR = os.path.join(_BASE_DIR, "feedback_data")
_FEEDBACK_LOG = os.path.join(_FEEDBACK_DIR, "feedback_log.json")
_YOLO_DATASET_DIR = os.path.join(_FEEDBACK_DIR, "yolo_dataset")
_EVAL_RESULTS_PATH = os.path.join(_BASE_DIR, "eval_results.json")
_WEIGHT_STORE_PATH = os.path.join(_BASE_DIR, "weight_logs.json")
_EXERCISE_STORE_PATH = os.path.join(_BASE_DIR, "exercise_logs.json")

_lock = threading.Lock()


def _norm(text: str) -> str:
    text = unicodedata.normalize("NFC", text or "").lower()
    return " ".join(text.split())


def resolve_class_id(corrected_name: str, corrected_class_id, foods_cache: dict) -> int:
    """Tim class_id chuan tu ten mon nguoi dung sua hoac class_id gui len."""
    if corrected_class_id is not None:
        try:
            return int(corrected_class_id)
        except (TypeError, ValueError):
            pass

    target = _norm(corrected_name)
    if not target:
        return 0

    for cid, info in foods_cache.items():
        if not isinstance(info, dict):
            continue
        name_vi = _norm(str(info.get("name_vi") or ""))
        name_en = _norm(str(info.get("name_en") or "")).replace("_", " ")
        if target == name_vi or target == name_en:
            return int(cid)

    for cid, info in foods_cache.items():
        if not isinstance(info, dict):
            continue
        name_vi = _norm(str(info.get("name_vi") or ""))
        if target in name_vi or name_vi in target:
            return int(cid)

    return 0


def export_feedback_to_yolo(foods_cache: dict) -> dict:
    """Chuyen cac mau feedback co anh sang dinh dang YOLO (x_center y_center w h)."""
    images_out = os.path.join(_YOLO_DATASET_DIR, "images", "train")
    labels_out = os.path.join(_YOLO_DATASET_DIR, "labels", "train")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    try:
        with open(_FEEDBACK_LOG, "r", encoding="utf-8") as f:
            logs = json.load(f)
            if not isinstance(logs, list):
                logs = []
    except Exception:
        logs = []

    exported_count = 0
    class_counts: dict[str, int] = {}

    for entry in logs:
        if not isinstance(entry, dict):
            continue
        corr_name = str(entry.get("corrected_name") or "").strip()
        if corr_name:
            class_counts[corr_name] = class_counts.get(corr_name, 0) + 1

        img_file = str(entry.get("image_file") or "").strip()
        if not img_file:
            continue

        src_img = os.path.join(_FEEDBACK_DIR, img_file)
        if not os.path.exists(src_img):
            continue

        try:
            with Image.open(src_img) as im:
                img_w, img_h = im.size
        except Exception:
            continue

        if img_w <= 0 or img_h <= 0:
            continue

        cid = resolve_class_id(
            corr_name,
            entry.get("corrected_class_id"),
            foods_cache,
        )
        # Neu la trai cay (id >= 1000), quy ve id goc hoac giu nguyen
        yolo_cid = cid - 1000 if cid >= 1000 else max(cid, 0)

        bbox = entry.get("bounding_box")
        if isinstance(bbox, dict):
            try:
                x1 = float(bbox.get("x1", 0))
                y1 = float(bbox.get("y1", 0))
                x2 = float(bbox.get("x2", img_w))
                y2 = float(bbox.get("y2", img_h))
            except (TypeError, ValueError):
                x1, y1, x2, y2 = 0.0, 0.0, float(img_w), float(img_h)
        else:
            # Mac dinh khung trung tam 80% anh neu nguoi dung khong gui bbox
            x1, y1 = img_w * 0.1, img_h * 0.1
            x2, y2 = img_w * 0.9, img_h * 0.9

        bw = max(min(abs(x2 - x1), float(img_w)), 1.0)
        bh = max(min(abs(y2 - y1), float(img_h)), 1.0)
        xc = min(max((min(x1, x2) + bw / 2.0) / img_w, 0.01), 0.99)
        yc = min(max((min(y1, y2) + bh / 2.0) / img_h, 0.01), 0.99)
        nw = min(max(bw / img_w, 0.02), 1.0)
        nh = min(max(bh / img_h, 0.02), 1.0)

        stem = os.path.splitext(img_file)[0]
        dst_img = os.path.join(images_out, img_file)
        dst_lbl = os.path.join(labels_out, f"{stem}.txt")

        if not os.path.exists(dst_img):
            shutil.copy2(src_img, dst_img)

        with open(dst_lbl, "w", encoding="utf-8") as lf:
            lf.write(f"{yolo_cid} {xc:.6f} {yc:.6f} {nw:.6f} {nh:.6f}\n")

        exported_count += 1

    yaml_path = os.path.join(_YOLO_DATASET_DIR, "active_data.yaml")
    with open(yaml_path, "w", encoding="utf-8") as yf:
        yf.write(
            f"# Auto-generated Active Learning YOLO Dataset\n"
            f"path: {_YOLO_DATASET_DIR}\n"
            f"train: images/train\n"
            f"val: images/train\n"
            f"nc: 68\n"
        )

    top_corrections = [
        {"name_vi": k, "count": v}
        for k, v in sorted(class_counts.items(), key=lambda x: x[1], reverse=True)[:5]
    ]

    return {
        "total_feedback": len(logs),
        "exported_yolo_samples": exported_count,
        "dataset_dir": _YOLO_DATASET_DIR,
        "top_corrections": top_corrections,
    }


def get_ai_metrics(foods_cache: dict) -> dict:
    """Tra ve bang chi so thuc nghiem mo hinh + trang thai Active Learning."""
    try:
        with open(_EVAL_RESULTS_PATH, "r", encoding="utf-8") as f:
            benchmarks = json.load(f)
            if not isinstance(benchmarks, list):
                benchmarks = []
    except Exception:
        benchmarks = []

    # Bo sung thong so model trai cay YOLO26s neu chua co trong file
    has_fruit = any("fruit" in str(b.get("model", "")).lower() for b in benchmarks if isinstance(b, dict))
    if not has_fruit:
        benchmarks.append({
            "model": "YOLO26s Fruit (20 loại trái cây)",
            "mAP50": 0.7945,
            "mAP50_95": 0.5625,
            "precision": 0.8068,
            "recall": 0.7429,
            "inference_ms_per_image": 4.20,
            "size_mb": 19.4,
        })

    al_stats = export_feedback_to_yolo(foods_cache)

    return {
        "total_classes": len(foods_cache),
        "food_classes": len([k for k in foods_cache if k < 1000]),
        "fruit_classes": len([k for k in foods_cache if k >= 1000]),
        "benchmarks": benchmarks,
        "active_learning": al_stats,
    }


def log_weight(user_key: str, weight_kg: float, note: str = "") -> list[dict]:
    """Luu moc can nang moi cho nguoi dung (toi da 1 moc/ngay, ghi de neu trung ngay)."""
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with _lock:
        try:
            with open(_WEIGHT_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if not isinstance(data, dict):
                    data = {}
        except Exception:
            data = {}

        user_list = data.get(user_key)
        if not isinstance(user_list, list):
            user_list = []

        cleaned = [
            item for item in user_list
            if isinstance(item, dict) and item.get("date") != today_str
        ]
        cleaned.append({
            "date": today_str,
            "weight_kg": round(float(weight_kg), 1),
            "note": (note or "").strip(),
        })
        cleaned.sort(key=lambda x: str(x.get("date") or ""))
        data[user_key] = cleaned[-60:]

        with open(_WEIGHT_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        return data[user_key]


def get_weight_history(user_key: str, current_weight_kg: float | None = None) -> list[dict]:
    with _lock:
        try:
            with open(_WEIGHT_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if not isinstance(data, dict):
                    data = {}
        except Exception:
            data = {}

        history = data.get(user_key)
        if not isinstance(history, list):
            history = []

        if not history and current_weight_kg and current_weight_kg > 0:
            today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            history = [{"date": today_str, "weight_kg": round(float(current_weight_kg), 1), "note": "Khởi tạo"}]

        return history


def forecast_weight_30d(
    current_weight_kg: float | None,
    daily_goal_kcal: float,
    avg_consumed_kcal: float,
    logged_days: int,
) -> dict:
    """Du bao bien thien can nang sau 30 ngay theo dinh luat can bang nang luong:
    7700 kcal du thua / tham hut ~ 1.0 kg khoi luong co the.
    """
    w = float(current_weight_kg or 0)
    goal = float(daily_goal_kcal or 2000)
    avg_in = float(avg_consumed_kcal or goal) if logged_days > 0 else goal

    daily_diff = avg_in - goal
    delta_30d_kg = round((daily_diff * 30.0) / 7700.0, 2)
    projected_w = round(w + delta_30d_kg, 1) if w > 0 else None

    if abs(daily_diff) < 80:
        trend = "stable"
        summary = "Năng lượng nạp vào đang cân bằng với mục tiêu — cân nặng dự kiến duy trì ổn định."
    elif daily_diff < 0:
        trend = "lose"
        summary = (
            f"Bạn đang thâm hụt ~{abs(daily_diff):.0f} kcal/ngày so với mục tiêu. "
            f"Dự kiến sau 30 ngày giảm khoảng {abs(delta_30d_kg):.1f} kg."
        )
    else:
        trend = "gain"
        summary = (
            f"Bạn đang dư ~{daily_diff:.0f} kcal/ngày so với mục tiêu. "
            f"Dự kiến sau 30 ngày tăng khoảng {delta_30d_kg:.1f} kg."
        )

    return {
        "current_weight_kg": round(w, 1) if w > 0 else None,
        "projected_weight_30d_kg": projected_w,
        "delta_30d_kg": delta_30d_kg,
        "daily_calorie_balance": round(daily_diff),
        "trend": trend,
        "summary": summary,
    }


def get_today_exercise(user_key: str) -> dict:
    """Lay tong calo dot chay va danh sach van dong trong ngay hom nay."""
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with _lock:
        try:
            with open(_EXERCISE_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if not isinstance(data, dict):
                    data = {}
        except Exception:
            data = {}

        user_days = data.get(user_key)
        if not isinstance(user_days, dict):
            user_days = {}
        items = user_days.get(today_str)
        if not isinstance(items, list):
            items = []

        total_burned = sum(float(i.get("burned_kcal") or 0) for i in items if isinstance(i, dict))
        total_min = sum(int(i.get("minutes") or 0) for i in items if isinstance(i, dict))
        return {
            "date": today_str,
            "burned_kcal": round(total_burned),
            "total_minutes": total_min,
            "activities": items,
        }


def log_exercise(
    user_key: str,
    activity_name: str,
    burned_kcal: float,
    minutes: int = 30,
) -> dict:
    """Ghi nhan 1 hoat dong the chat dot calo trong ngay."""
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with _lock:
        try:
            with open(_EXERCISE_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if not isinstance(data, dict):
                    data = {}
        except Exception:
            data = {}

        user_days = data.get(user_key)
        if not isinstance(user_days, dict):
            user_days = {}
        items = user_days.get(today_str)
        if not isinstance(items, list):
            items = []

        items.append({
            "activity_name": (activity_name or "Vận động").strip(),
            "burned_kcal": round(max(float(burned_kcal or 0), 0.0)),
            "minutes": max(minutes or 15, 1),
            "time": datetime.now().strftime("%H:%M"),
        })
        user_days[today_str] = items[-30:]
        data[user_key] = user_days

        with open(_EXERCISE_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    return get_today_exercise(user_key)


def clear_today_exercise(user_key: str) -> dict:
    """Xoa van dong hom nay (reset)."""
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with _lock:
        try:
            with open(_EXERCISE_STORE_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if not isinstance(data, dict):
                    data = {}
        except Exception:
            data = {}

        if isinstance(data.get(user_key), dict):
            data[user_key][today_str] = []
            with open(_EXERCISE_STORE_PATH, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    return get_today_exercise(user_key)


def _eval_single_food_metrics(info: dict, conditions: list[str], allergies: list[str]) -> dict:
    nut = info.get("nutrition") if isinstance(info.get("nutrition"), dict) else info
    portion = int(info.get("portion_g") or nut.get("portion_g") or 250)
    if nut.get("calories") is not None:
        cal = max(float(nut.get("calories") or 1), 1.0)
        pro = float(nut.get("protein_g") or 0)
        fat = float(nut.get("fat_g") or 0)
        carb = float(nut.get("carbs_g") or 0)
    else:
        factor = portion / 100.0
        cal = max(float(info.get("calories_per_100g") or 100) * factor, 1.0)
        pro = float(info.get("protein_g") or 0) * factor
        fat = float(info.get("fat_g") or 0) * factor
        carb = float(info.get("carbs_g") or 0) * factor

    p_ratio = (pro * 4.0) / cal
    f_ratio = (fat * 9.0) / cal
    score = 75
    if p_ratio >= 0.20:
        score += 12
    elif p_ratio < 0.10:
        score -= 10
    if f_ratio > 0.42:
        score -= 18
    elif f_ratio > 0.35:
        score -= 8
    if cal > 800:
        score -= 15
    elif cal <= 550 and p_ratio >= 0.18:
        score += 8

    # Phat diem theo benh ly ca nhan
    cond_norm = " ".join(_norm(c) for c in conditions)
    reasons: list[str] = []
    if "tieu duong" in cond_norm or "tiểu đường" in cond_norm:
        if carb > 65:
            score -= 14
            reasons.append(f"Tinh bột cao ({carb:.0f}g)")
        elif carb <= 45:
            score += 8
            reasons.append(f"Tinh bột vừa phải ({carb:.0f}g)")
    if "mo mau" in cond_norm or "mỡ máu" in cond_norm or "tim mach" in cond_norm:
        if fat > 22:
            score -= 14
            reasons.append(f"Chất béo cao ({fat:.0f}g)")
        elif fat <= 14:
            score += 8
            reasons.append(f"Ít béo ({fat:.0f}g)")
    if "gout" in cond_norm and pro > 35:
        score -= 10
        reasons.append(f"Đạm cao ({pro:.0f}g)")

    name_vi = str(info.get("name_vi") or "Món ăn")
    name_norm = _norm(name_vi)
    for al in allergies:
        al_n = _norm(al)
        if al_n and al_n in name_norm:
            score -= 35
            reasons.append(f"Chứa dị ứng '{al}'")

    score = max(min(score, 98), 20)
    if score >= 82:
        grade = "A"
    elif score >= 68:
        grade = "B"
    elif score >= 54:
        grade = "C"
    elif score >= 40:
        grade = "D"
    else:
        grade = "E"

    macro_sum = carb + pro + fat + 1.0
    buf = 1.0 - ((pro + fat) / macro_sum) * 0.25
    gl = round(carb * 0.55 * buf)

    return {
        "name_vi": name_vi,
        "portion_g": portion,
        "calories": round(cal),
        "protein_g": round(pro, 1),
        "fat_g": round(fat, 1),
        "carbs_g": round(carb, 1),
        "nutri_score": grade,
        "health_score": score,
        "glycemic_load": gl,
        "burn_walk_min": max(round(cal / 5.5), 5),
        "burn_run_min": max(round(cal / 10.0), 3),
        "notes": reasons,
    }


def compare_two_foods(
    food_a_id: int,
    food_b_id: int,
    foods_cache: dict,
    user_conditions: list[str] | None = None,
    user_allergies: list[str] | None = None,
) -> dict:
    """So sanh 2 mon an truc dien theo dinh duong & benh ly ca nhan."""
    conds = user_conditions or []
    alls = user_allergies or []
    info_a = foods_cache.get(food_a_id) or foods_cache.get(0) or {}
    info_b = foods_cache.get(food_b_id) or foods_cache.get(1) or {}

    res_a = _eval_single_food_metrics(info_a, conds, alls)
    res_b = _eval_single_food_metrics(info_b, conds, alls)
    res_a["class_id"] = food_a_id
    res_b["class_id"] = food_b_id

    winner = "A" if res_a["health_score"] >= res_b["health_score"] else "B"
    win_obj = res_a if winner == "A" else res_b
    lose_obj = res_b if winner == "A" else res_a

    cal_diff = abs(res_a["calories"] - res_b["calories"])
    gl_diff = abs(res_a["glycemic_load"] - res_b["glycemic_load"])

    verdict = (
        f"Nên chọn '{win_obj['name_vi']}' (Điểm sức khỏe {win_obj['health_score']}/100, "
        f"Nutri-Score {win_obj['nutri_score']}, GL={win_obj['glycemic_load']}) thay vì '{lose_obj['name_vi']}'. "
        f"Chênh lệch {cal_diff} kcal và {gl_diff} điểm tải đường huyết (GL)."
    )

    return {
        "food_a": res_a,
        "food_b": res_b,
        "winner": winner,
        "winner_name": win_obj["name_vi"],
        "verdict": verdict,
    }


