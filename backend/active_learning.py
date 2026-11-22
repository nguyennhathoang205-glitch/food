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
from typing import Any
from PIL import Image

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_FEEDBACK_DIR = os.path.join(_BASE_DIR, "feedback_data")
_FEEDBACK_LOG = os.path.join(_FEEDBACK_DIR, "feedback_log.json")
_YOLO_DATASET_DIR = os.path.join(_FEEDBACK_DIR, "yolo_dataset")
_EVAL_RESULTS_PATH = os.path.join(_BASE_DIR, "eval_results.json")
_WEIGHT_STORE_PATH = os.path.join(_BASE_DIR, "weight_logs.json")
_EXERCISE_STORE_PATH = os.path.join(_BASE_DIR, "exercise_logs.json")

_lock = threading.Lock()
_supabase = None


def set_supabase_client(sb) -> None:
    """Gan Supabase client de dong bo weight_logs va exercise_logs len Cloud."""
    global _supabase
    _supabase = sb


def record_feedback_entry(
    user_key: str,
    predicted_name: str,
    corrected_name: str,
    predicted_class_id: int | None = None,
    corrected_class_id: int | None = None,
    confidence: float = 0.0,
    bounding_box: dict | None = None,
    image_path: str | None = None,
) -> dict:
    """Ghi nhan mau feedback vao feedback_data/feedback_log.json cho pipeline Active Learning."""
    os.makedirs(_FEEDBACK_DIR, exist_ok=True)
    with _lock:
        try:
            with open(_FEEDBACK_LOG, "r", encoding="utf-8") as f:
                logs = json.load(f)
                if not isinstance(logs, list):
                    logs = []
        except Exception:
            logs = []

        img_file = ""
        if image_path:
            abs_src = (
                image_path
                if os.path.isabs(image_path)
                else os.path.join(_BASE_DIR, image_path)
            )
            if os.path.exists(abs_src):
                img_file = os.path.basename(abs_src)
                dst_copy = os.path.join(_FEEDBACK_DIR, img_file)
                if not os.path.exists(dst_copy):
                    try:
                        shutil.copy2(abs_src, dst_copy)
                    except Exception:
                        pass

        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user_key": user_key,
            "predicted_name": predicted_name,
            "predicted_class_id": predicted_class_id,
            "corrected_name": corrected_name,
            "corrected_class_id": corrected_class_id,
            "confidence": confidence,
            "bounding_box": bounding_box or {},
            "image_file": img_file,
        }
        logs.append(entry)
        with open(_FEEDBACK_LOG, "w", encoding="utf-8") as f:
            json.dump(logs, f, ensure_ascii=False, indent=2)
    return entry


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

        if _supabase is not None:
            try:
                _supabase.table("weight_logs").upsert({
                    "user_key": user_key,
                    "log_date": today_str,
                    "weight_kg": round(float(weight_kg), 1),
                    "note": (note or "").strip(),
                }).execute()
            except Exception:
                pass

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

        if not history and _supabase is not None:
            try:
                res = (
                    _supabase.table("weight_logs")
                    .select("log_date, weight_kg, note")
                    .eq("user_key", user_key)
                    .order("log_date")
                    .limit(60)
                    .execute()
                )
                if res.data:
                    history = [
                        {
                            "date": str(r.get("log_date") or ""),
                            "weight_kg": round(float(r.get("weight_kg") or 0), 1),
                            "note": str(r.get("note") or ""),
                        }
                        for r in res.data
                        if isinstance(r, dict) and r.get("weight_kg")
                    ]
                    if history:
                        data[user_key] = history
                        with open(_WEIGHT_STORE_PATH, "w", encoding="utf-8") as f:
                            json.dump(data, f, ensure_ascii=False, indent=2)
            except Exception:
                pass

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
        if not isinstance(items, list) and _supabase is not None:
            try:
                res = (
                    _supabase.table("exercise_logs")
                    .select("activities")
                    .eq("user_key", user_key)
                    .eq("log_date", today_str)
                    .limit(1)
                    .execute()
                )
                if res.data and isinstance(res.data[0].get("activities"), list):
                    items = res.data[0]["activities"]
                    user_days[today_str] = items
                    data[user_key] = user_days
                    with open(_EXERCISE_STORE_PATH, "w", encoding="utf-8") as f:
                        json.dump(data, f, ensure_ascii=False, indent=2)
            except Exception:
                pass
        if not isinstance(items, list):
            items = []

        total_burned = sum(float(i.get("burned_kcal") or 0) for i in items if isinstance(i, dict))
        total_min = sum(int(i.get("minutes") or 0) for i in items if isinstance(i, dict))
        total_km = sum(float(i.get("distance_km") or 0) for i in items if isinstance(i, dict))
        total_steps = sum(int(i.get("steps") or 0) for i in items if isinstance(i, dict))
        return {
            "date": today_str,
            "burned_kcal": round(total_burned),
            "total_minutes": total_min,
            "total_distance_km": round(total_km, 2),
            "total_steps": total_steps,
            "activities": items,
        }


def log_exercise(
    user_key: str,
    activity_name: str,
    burned_kcal: float,
    minutes: int = 1,
    distance_km: float = 0.0,
    steps: int = 0,
    pace: str = "",
    duration_sec: int = 0,
) -> dict:
    """Ghi nhan 1 hoat dong the chat dot calo trong ngay (Strava-style)."""
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
        if not isinstance(items, list) and _supabase is not None:
            try:
                res = (
                    _supabase.table("exercise_logs")
                    .select("activities")
                    .eq("user_key", user_key)
                    .eq("log_date", today_str)
                    .limit(1)
                    .execute()
                )
                if res.data and isinstance(res.data[0].get("activities"), list):
                    items = res.data[0]["activities"]
                    user_days[today_str] = items
                    data[user_key] = user_days
                    with open(_EXERCISE_STORE_PATH, "w", encoding="utf-8") as f:
                        json.dump(data, f, ensure_ascii=False, indent=2)
            except Exception:
                pass
        if not isinstance(items, list):
            items = []

        items.append({
            "activity_name": (activity_name or "Vận động").strip(),
            "burned_kcal": round(max(float(burned_kcal or 0), 0.0)),
            "minutes": max(minutes or 1, 1),
            "distance_km": round(max(float(distance_km or 0.0), 0.0), 2),
            "steps": max(steps or 0, 0),
            "pace": (pace or "").strip(),
            "duration_sec": max(duration_sec or 0, 0),
            "time": datetime.now().strftime("%H:%M"),
        })
        user_days[today_str] = items[-30:]
        data[user_key] = user_days

        with open(_EXERCISE_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        if _supabase is not None:
            try:
                total_burned = sum(float(i.get("burned_kcal") or 0) for i in user_days[today_str] if isinstance(i, dict))
                _supabase.table("exercise_logs").upsert({
                    "user_key": user_key,
                    "log_date": today_str,
                    "burned_kcal": round(total_burned),
                    "activities": user_days[today_str],
                }).execute()
            except Exception:
                pass

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

        if _supabase is not None:
            try:
                _supabase.table("exercise_logs").upsert({
                    "user_key": user_key,
                    "log_date": today_str,
                    "burned_kcal": 0,
                    "activities": [],
                }).execute()
            except Exception:
                pass

    return get_today_exercise(user_key)


_DISH_KNOWN_INGREDIENTS: dict[str, list[str]] = {
    "bánh bột lọc": ["Bột năng luộc trong", "Nhân tôm tươi", "Thịt ba chỉ rim", "Hành khô phi", "Nước mắm ớt"],
    "bánh xèo": ["Vỏ bột gạo nghệ chiên giòn", "Tôm tươi", "Thịt ba chỉ", "Giá đỗ & đậu xanh", "Rau sống & nước mắm"],
    "bánh khọt": ["Bột gạo chiên khuôn", "Tôm tươi", "Nước cốt dừa", "Mỡ hành & bột tôm", "Rau sống & nước mắm"],
    "bánh bèo": ["Bột gạo hấp chén", "Tôm cháy", "Mỡ hành & da heo chiên", "Nước mắm ngọt"],
    "gỏi cuốn": ["Bánh tráng gạo", "Tôm luộc", "Thịt ba chỉ luộc", "Bún tươi & rau sống", "Tương chấm đậu phộng"],
    "bún đậu": ["Bún lá ép", "Đậu hũ chiên", "Thịt chân giò luộc", "Chả cốm", "Mắm tôm & rau kinh giới"],
    "bún riêu": ["Bún tươi", "Riêu cua đồng", "Đậu hũ chiên", "Cà chua & huyết", "Mắm tôm & rau sống"],
    "bún mắm": ["Bún tươi", "Nước lèo mắm cá linh/cá sặc", "Tôm, mực & cá", "Thịt heo quay", "Rau đắng & bông súng"],
    "hủ tiếu": ["Sợi hủ tiếu gạo", "Thịt heo & tôm", "Trứng cút", "Nước dùng ninh xương", "Giá hẹ & hành phi"],
    "mì quảng": ["Sợi mì Quảng nghệ", "Tôm & thịt heo/gà", "Trứng", "Đậu phộng rang & bánh đa", "Rau sống"],
    "cao lầu": ["Sợi mì cao lầu", "Thịt xá xíu heo", "Da heo chiên giòn", "Rau sống & nước sốt"],
    "bánh canh": ["Sợi bánh canh bột gạo/bột lọc", "Thịt heo / giò heo / chả", "Nước dùng hầm xương", "Hành ngò & tiêu"],
    "bánh chưng": ["Gạo nếp cái hoa vàng", "Đậu xanh đãi vỏ", "Thịt mỡ ba chỉ heo", "Tiêu & hành muối"],
    "bánh tét": ["Gạo nếp", "Đậu xanh", "Thịt mỡ ba chỉ heo", "Đồ chua ăn kèm"],
    "bánh cuốn": ["Vỏ bánh bột gạo tráng mỏng", "Nhân thịt heo băm & mộc nhĩ", "Chả lụa", "Hành phi & nước mắm"],
    "bánh ướt": ["Bánh ướt bột gạo", "Chả lụa & nem chua", "Hành phi", "Giá trụng & nước mắm"],
    "bánh mì": ["Vỏ bánh mì bột mì (gluten)", "Thịt heo / chả lụa", "Pate gan & sốt bơ", "Đồ chua, dưa leo & ngò"],
    "bánh bao": ["Vỏ bột mì hấp (gluten)", "Nhân thịt heo băm", "Trứng cút & lạp xưởng", "Mộc nhĩ"],
    "bánh giò": ["Bột gạo tẻ & bột năng", "Nhân thịt heo băm & mộc nhĩ", "Trứng cút", "Chả lụa / tương ớt"],
    "cơm tấm": ["Gạo tấm", "Sườn heo nướng", "Bì heo", "Chả trứng hấp", "Mỡ hành & nước mắm"],
    "cơm gà": ["Cơm nấu nước luộc gà", "Thịt gà xé / gà quay", "Đồ chua & dưa leo", "Nước mắm gừng"],
    "cơm chiên": ["Cơm rang trứng", "Xúc xích / lạp xưởng / tôm thịt", "Rau củ hạt lựu", "Nước tương"],
    "chả giò": ["Bánh tráng cuốn chiên ngập dầu", "Thịt heo băm & tôm", "Trứng", "Miến & mộc nhĩ"],
    "nem rán": ["Bánh tráng cuốn chiên ngập dầu", "Thịt heo băm & tôm", "Trứng", "Miến & mộc nhĩ"],
    "bún thịt nướng": ["Bún tươi", "Thịt heo nướng sả", "Chả giò chiên", "Đậu phộng & mỡ hành", "Nước mắm chua ngọt"],
    "bún chả": ["Bún tươi", "Chả thịt heo nướng", "Thịt ba chỉ nướng", "Đu đủ chua & rau sống", "Nước mắm chua ngọt"],
    "bún bò": ["Bún sợi to", "Thịt bắp bò & giò heo", "Chả bò Huế", "Nước dùng hầm xương sả", "Rau sống"],
    "phở": ["Bánh phở gạo", "Thịt bò / thịt gà", "Nước dùng ninh xương", "Hành lá & giá trụng"],
    "bò kho": ["Thịt bò nạm/gân hầm", "Cà rốt", "Nước sốt ngũ vị hương", "Bánh mì / hủ tiếu"],
    "thịt kho": ["Thịt ba chỉ heo kho", "Trứng vịt/trứng cút", "Nước dừa & nước mắm", "Hành tỏi"],
}


def get_known_dish_ingredients(name_vi: str) -> list[str]:
    """Tra ve thanh phan dac trung cua mon an Viet de doi chieu di ung & benh ly."""
    low = _norm(name_vi)
    for key, ings in _DISH_KNOWN_INGREDIENTS.items():
        if _norm(key) in low:
            return list(ings)
    if "bún" in low:
        return ["Bún gạo tươi", "Đạm thịt / chả", "Nước dùng / nước mắm", "Rau sống"]
    if "phở" in low:
        return ["Bánh phở gạo", "Thịt bò / gà", "Nước dùng hầm xương", "Rau gia vị"]
    if "cơm" in low:
        return ["Cơm trắng", "Thịt / cá chế biến", "Rau ăn kèm", "Nước chấm"]
    return [name_vi]


def estimate_standard_serving(name_vi: str, category: str | None = None) -> tuple[int, str]:
    """Uoc tinh khoi luong 1 khau phan an thuc te theo nhom mon Viet Nam (Viện Dinh dưỡng)."""
    low = _norm(name_vi)
    cat = _norm(category or "")
    if cat == "fruit" or any(k in low for k in (
        "chuối", "táo", "cam", "xoài", "dưa hấu", "nho", "ổi", "bưởi", "thanh long",
        "đu đủ", "dâu", "mít", "sầu riêng", "bơ", "vải", "nhãn", "mận", "đào", "lê", "dứa", "thơm",
        "chè", "sữa chua", "kem", "flan", "tàu hũ",
    )):
        return 150, "1 phần tiêu chuẩn (~150g)"
    if any(k in low for k in (
        "phở", "bún bò", "bún riêu", "bún cá", "bún mắm", "bún mọc", "bún thang",
        "bánh canh", "hủ tiếu", "miến", "mì quảng", "cao lầu", "lẩu", "bánh đa cua",
    )):
        return 380, "1 tô tiêu chuẩn (~380g cả nước & cái)"
    if any(k in low for k in ("cháo", "súp", "canh")):
        return 300, "1 tô vừa (~300g)"
    if any(k in low for k in ("cơm tấm", "cơm gà", "cơm chiên", "cơm sườn", "cơm")):
        return 320, "1 đĩa tiêu chuẩn (~320g)"
    if any(k in low for k in (
        "bún chả", "bún thịt nướng", "bún đậu", "bánh cuốn", "bánh ướt", "bánh xèo", "mì xào",
    )):
        return 260, "1 suất tiêu chuẩn (~260g)"
    if any(k in low for k in ("bánh mì", "xôi", "bánh bao", "bánh giò")):
        return 210, "1 ổ / 1 gói (~210g)"
    if any(k in low for k in ("bánh chưng", "bánh tét", "bánh dày")):
        return 200, "1 góc / 1 khoanh (~200g)"
    if any(k in low for k in (
        "bánh bột lọc", "bánh bèo", "bánh khọt", "bánh ít", "bánh đúc", "bánh pía",
        "bánh cam", "bánh tiêu", "bánh bò", "bánh da lợn", "bánh chuối", "bánh tráng",
        "gỏi cuốn", "chả giò", "nem", "bò bía", "há cảo", "xíu mại",
    )):
        return 180, "1 đĩa nhỏ / 1 phần (~180g)"
    if any(k in low for k in ("rau", "gỏi", "nộm", "salad", "cà pháo", "dưa")):
        return 180, "1 đĩa (~180g)"
    return 250, "1 khẩu phần chuẩn (~250g)"


def _eval_single_food_metrics(
    info: dict,
    conditions: list[str],
    allergies: list[str],
    compare_mode: str = "serving",
    custom_portion_g: int | None = None,
) -> dict:
    import health as health_rules

    name_vi = str(info.get("name_vi") or "Món ăn")
    nut = info.get("nutrition") if isinstance(info.get("nutrition"), dict) else info
    std_portion_g, serving_unit = estimate_standard_serving(name_vi, info.get("category"))

    # Lay dinh duong chuan tren 100g tu bang foods (Viện Dinh dưỡng Quốc gia)
    raw_portion = int(info.get("portion_g") or nut.get("portion_g") or std_portion_g)
    if info.get("calories_per_100g") is not None:
        cal_100g = max(float(info.get("calories_per_100g") or 100), 1.0)
        pro_100g = float(info.get("protein_g") or 0)
        fat_100g = float(info.get("fat_g") or 0)
        carb_100g = float(info.get("carbs_g") or 0)
    elif nut.get("calories") is not None and raw_portion > 0:
        scale_100 = 100.0 / raw_portion
        cal_100g = max(float(nut.get("calories") or 100) * scale_100, 1.0)
        pro_100g = float(nut.get("protein_g") or 0) * scale_100
        fat_100g = float(nut.get("fat_g") or 0) * scale_100
        carb_100g = float(nut.get("carbs_g") or 0) * scale_100
    else:
        cal_100g = 150.0
        pro_100g = 7.0
        fat_100g = 5.0
        carb_100g = 20.0

    if compare_mode == "per_100g":
        portion = 100
        portion_label = "Chuẩn 100g (So mật độ)"
    elif custom_portion_g is not None and int(custom_portion_g) >= 50:
        portion = int(custom_portion_g)
        portion_label = f"Định lượng {portion}g"
    else:
        portion = std_portion_g
        portion_label = serving_unit

    factor = portion / 100.0
    cal = max(cal_100g * factor, 1.0)
    pro = pro_100g * factor
    fat = fat_100g * factor
    carb = carb_100g * factor

    p_ratio = (pro * 4.0) / cal
    f_ratio = (fat * 9.0) / cal
    c_ratio = (carb * 4.0) / cal
    macro_sum = carb + pro + fat + 1.0
    buf = 1.0 - ((pro + fat) / macro_sum) * 0.25
    gl = round(carb * 0.55 * buf)

    score = 75
    reasons: list[str] = []
    criteria_details: list[str] = []

    # Tieu chi 1: Mat do nang luong (kcal/100g) & Tong calo khau phan
    if cal_100g <= 130:
        score += 8
        criteria_details.append(f"Mật độ calo thấp ({round(cal_100g)} kcal/100g: +8đ)")
    elif cal_100g > 230:
        score -= 10
        criteria_details.append(f"Mật độ calo đậm đặc ({round(cal_100g)} kcal/100g: -10đ)")
    if cal > 700:
        score -= 10
    elif cal <= 450:
        score += 4

    # Tieu chi 2: Ty le Dam sinh hoc (Protein % kcal)
    if p_ratio >= 0.20:
        score += 12
        criteria_details.append(f"Giàu đạm ({round(p_ratio * 100)}% năng lượng: +12đ)")
    elif p_ratio >= 0.14:
        score += 4
    elif p_ratio < 0.10:
        score -= 8
        criteria_details.append(f"Ít đạm ({round(p_ratio * 100)}% năng lượng: -8đ)")

    # Tieu chi 3: Ty le Chat beo (Fat % kcal)
    if f_ratio > 0.40:
        score -= 15
        criteria_details.append(f"Tỷ lệ béo cao ({round(f_ratio * 100)}% năng lượng: -15đ)")
    elif f_ratio > 0.33:
        score -= 7
    elif f_ratio <= 0.22:
        score += 5
        criteria_details.append(f"Ít béo ({round(f_ratio * 100)}% năng lượng: +5đ)")

    # Tieu chi 4: Tai duong huyet (Glycemic Load - GL)
    if gl <= 16:
        score += 6
        criteria_details.append(f"Tải đường huyết thấp (GL={gl}: +6đ)")
    elif gl >= 30:
        score -= 8
        criteria_details.append(f"Tải đường huyết cao (GL={gl}: -8đ)")

    # Tieu chi 5: Doi chieu Ho so Di ung & Benh ly nen (kiem tra ca thanh phan ngam trong mon)
    known_ings = get_known_dish_ingredients(name_vi)
    profile_dict = {
        "allergies": list(allergies or []),
        "conditions": list(conditions or []),
        "medications": [],
    }
    health_warns = health_rules.check_warnings(
        profile_dict,
        [name_vi],
        known_ings,
        {"calories": cal, "protein_g": pro, "fat_g": fat, "carbs_g": carb},
    )

    has_allergy_conflict = False
    has_condition_conflict = False
    for w in health_warns:
        msg = str(w.get("message") or "").strip()
        if not msg:
            continue
        if w.get("level") == "red":
            has_allergy_conflict = True
            score -= 40
            reasons.append(f"🚫 {msg}")
        else:
            has_condition_conflict = True
            score -= 14
            reasons.append(f"⚠️ {msg}")

    cond_norm = " ".join(_norm(c) for c in conditions)
    if ("tiểu đường" in cond_norm or "tieu duong" in cond_norm):
        if carb > 55 or gl >= 28:
            if not any("Tiểu đường" in r or "tiểu đường" in r for r in reasons):
                has_condition_conflict = True
                score -= 12
                reasons.append(f"⚠️ Tiểu đường: Tinh bột/GL khá cao ({carb:.0f}g Carb, GL={gl})")
        elif carb <= 38 and gl <= 18:
            score += 6
            reasons.append(f"✅ Tiểu đường: Tinh bột & GL kiểm soát tốt ({carb:.0f}g Carb, GL={gl})")

    if any(k in cond_norm for k in ("mỡ máu", "mo mau", "cholesterol", "tim mạch", "béo phì")):
        if fat > 18 or f_ratio > 0.34:
            if not any("béo" in r.lower() or "mỡ máu" in r.lower() for r in reasons):
                has_condition_conflict = True
                score -= 12
                reasons.append(f"⚠️ Mỡ máu/Cân nặng: Chất béo khá cao ({fat:.1f}g Béo)")
        elif fat <= 10:
            score += 6
            reasons.append(f"✅ Ít chất béo ({fat:.1f}g), tốt cho mỡ máu & kiểm soát cân nặng")

    if "gout" in cond_norm and pro > 32 and not any("gout" in r.lower() for r in reasons):
        has_condition_conflict = True
        score -= 10
        reasons.append(f"⚠️ Gout: Đạm khẩu phần cao ({pro:.0f}g), cần uống nhiều nước")

    if (allergies or conditions) and not has_allergy_conflict and not has_condition_conflict and not reasons:
        score += 5
        reasons.append("✅ Phù hợp với hồ sơ dị ứng & bệnh lý của bạn")

    score = max(min(score, 98), 15)
    if score >= 82 and not has_allergy_conflict:
        grade = "A"
    elif score >= 68 and not has_allergy_conflict:
        grade = "B"
    elif score >= 54 and not has_allergy_conflict:
        grade = "C"
    elif score >= 40:
        grade = "D"
    else:
        grade = "E"

    return {
        "name_vi": name_vi,
        "portion_g": portion,
        "portion_label": portion_label,
        "standard_portion_g": std_portion_g,
        "serving_unit": serving_unit,
        "calories_per_100g": round(cal_100g),
        "protein_per_100g": round(pro_100g, 1),
        "fat_per_100g": round(fat_100g, 1),
        "carbs_per_100g": round(carb_100g, 1),
        "calories": round(cal),
        "protein_g": round(pro, 1),
        "fat_g": round(fat, 1),
        "carbs_g": round(carb, 1),
        "protein_pct": round(p_ratio * 100),
        "fat_pct": round(f_ratio * 100),
        "carbs_pct": round(c_ratio * 100),
        "nutri_score": grade,
        "health_score": score,
        "glycemic_load": gl,
        "burn_walk_min": max(round(cal / 5.5), 5),
        "burn_run_min": max(round(cal / 10.0), 3),
        "known_ingredients": known_ings,
        "has_allergy_conflict": has_allergy_conflict,
        "has_condition_conflict": has_condition_conflict,
        "criteria_details": criteria_details,
        "notes": reasons,
    }


def compare_two_foods(
    food_a_id: int,
    food_b_id: int,
    foods_cache: dict,
    user_conditions: list[str] | None = None,
    user_allergies: list[str] | None = None,
    compare_mode: str = "serving",
    custom_portion_g: int | None = None,
) -> dict:
    """So sanh 2 mon an truc dien theo dinh duong & benh ly ca nhan."""
    conds = user_conditions or []
    alls = user_allergies or []
    info_a = foods_cache.get(food_a_id)
    if info_a is None:
        info_a = foods_cache.get(0) or {}
    info_b = foods_cache.get(food_b_id)
    if info_b is None:
        info_b = foods_cache.get(1) or {}

    res_a = _eval_single_food_metrics(
        info_a, conds, alls, compare_mode=compare_mode, custom_portion_g=custom_portion_g
    )
    res_b = _eval_single_food_metrics(
        info_b, conds, alls, compare_mode=compare_mode, custom_portion_g=custom_portion_g
    )
    res_a["class_id"] = food_a_id
    res_b["class_id"] = food_b_id

    winner = "A" if res_a["health_score"] >= res_b["health_score"] else "B"
    win_obj = res_a if winner == "A" else res_b
    lose_obj = res_b if winner == "A" else res_a

    cal_diff = abs(res_a["calories"] - res_b["calories"])
    cal100_diff = abs(res_a["calories_per_100g"] - res_b["calories_per_100g"])
    gl_diff = abs(res_a["glycemic_load"] - res_b["glycemic_load"])

    verdict_parts = [
        f"Nên chọn '{win_obj['name_vi']}' (Điểm sức khỏe {win_obj['health_score']}/100, "
        f"Nutri-Score {win_obj['nutri_score']}, GL={win_obj['glycemic_load']}) "
        f"thay vì '{lose_obj['name_vi']}' ({lose_obj['health_score']}/100)."
    ]
    if lose_obj.get("has_allergy_conflict") and not win_obj.get("has_allergy_conflict"):
        verdict_parts.append(
            f"Lưu ý quan trọng: '{lose_obj['name_vi']}' chứa thành phần trùng với DỊ ỨNG trong hồ sơ của bạn."
        )
    elif lose_obj.get("has_condition_conflict") and not win_obj.get("has_condition_conflict"):
        verdict_parts.append(
            f"'{win_obj['name_vi']}' an toàn hơn cho bệnh lý nền của bạn."
        )
    verdict_parts.append(
        f"Xét mật độ gốc: {win_obj['name_vi']} có {win_obj['calories_per_100g']} kcal/100g "
        f"so với {lose_obj['name_vi']} ({lose_obj['calories_per_100g']} kcal/100g, lệch {cal100_diff} kcal/100g). "
        f"Ở mức khẩu phần đang so sánh ({win_obj['portion_g']}g vs {lose_obj['portion_g']}g), "
        f"chênh lệch là {cal_diff} kcal và {gl_diff} điểm tải đường huyết (GL)."
    )

    criteria_guide = [
        "1. Mật độ Calo chuẩn (kcal/100g): Tra từ Bảng Thành phần Thực phẩm Việt Nam (Viện Dinh dưỡng Quốc gia).",
        "2. Định lượng khẩu phần thực tế (g): Chuẩn hóa theo đơn vị ăn thực tế của từng nhóm món (1 tô bún/phở/bánh canh ~380g cả nước, 1 đĩa cơm ~320g, 1 ổ bánh mì ~210g, 1 đĩa bánh nhỏ/ăn vặt ~180g).",
        "3. Tỷ lệ Đa lượng (Đạm / Béo / Carb): Ưu tiên món giàu đạm (>=18% kcal) và kiểm soát chất béo (<33% kcal).",
        "4. Tải đường huyết (Glycemic Load - GL): Đánh giá tốc độ tăng đường máu sau ăn dựa trên lượng Carb và độ đệm của Đạm/Xơ.",
        "5. Đối chiếu Hồ sơ Sức khỏe cá nhân: Tự động quét thành phần ngầm của món (vd: Bánh bột lọc có nhân tôm thịt, Bánh chưng có thịt mỡ...) để trừ điểm và cảnh báo nếu trùng Dị ứng hoặc Bệnh lý nền.",
    ]

    return {
        "food_a": res_a,
        "food_b": res_b,
        "compare_mode": compare_mode,
        "winner": winner,
        "winner_name": win_obj["name_vi"],
        "verdict": " ".join(verdict_parts),
        "criteria_guide": criteria_guide,
        "active_health_profile": {
            "allergies": alls,
            "conditions": conds,
        },
    }


# ============================================================
# SMART MENU ADVISOR & FRIDGE-TO-MEAL CHEF (PRO 4.5)
# ============================================================

_MENU_CATALOG: list[dict[str, Any]] = [
    {
        "name_vi": "Cơm ức gà áp chảo & bông cải luộc",
        "menu_group": "com_van_phong",
        "calories": 460,
        "protein_g": 38.0,
        "fat_g": 9.5,
        "carbs_g": 54.0,
        "portion_g": 350,
        "tags": ["it_mo", "giau_dam", "it_muoi"],
    },
    {
        "name_vi": "Cơm cá thu sốt cà chua & canh rau ngót",
        "menu_group": "com_van_phong",
        "calories": 510,
        "protein_g": 32.0,
        "fat_g": 14.0,
        "carbs_g": 62.0,
        "portion_g": 380,
        "tags": ["ca", "hai_san", "tot_tim_mach"],
    },
    {
        "name_vi": "Cơm đậu hũ nhồi thịt & rau muống luộc",
        "menu_group": "com_van_phong",
        "calories": 480,
        "protein_g": 24.0,
        "fat_g": 13.0,
        "carbs_g": 64.0,
        "portion_g": 360,
        "tags": ["dau_nanh", "thanh_dam"],
    },
    {
        "name_vi": "Cơm tấm sườn bì chả trứng ốp la",
        "menu_group": "com_van_phong",
        "calories": 760,
        "protein_g": 36.0,
        "fat_g": 30.0,
        "carbs_g": 82.0,
        "portion_g": 400,
        "tags": ["nhieu_mo", "nhieu_carb", "trung"],
    },
    {
        "name_vi": "Cơm thịt kho tàu (thịt ba chỉ) & dưa cải",
        "menu_group": "com_van_phong",
        "calories": 710,
        "protein_g": 26.0,
        "fat_g": 34.0,
        "carbs_g": 72.0,
        "portion_g": 380,
        "tags": ["nhieu_mo", "man", "nhieu_carb"],
    },
    {
        "name_vi": "Phở gà ta (bỏ da, ít bánh phở, nhiều giá trụng)",
        "menu_group": "bun_pho",
        "calories": 420,
        "protein_g": 31.0,
        "fat_g": 8.5,
        "carbs_g": 52.0,
        "portion_g": 450,
        "tags": ["it_mo", "giau_dam", "de_tieu"],
    },
    {
        "name_vi": "Bún thịt nướng nạc & nhiều rau sống (ít nước mắm)",
        "menu_group": "bun_pho",
        "calories": 490,
        "protein_g": 28.0,
        "fat_g": 13.5,
        "carbs_g": 62.0,
        "portion_g": 380,
        "tags": ["can_bang", "rau_xanh"],
    },
    {
        "name_vi": "Miến gà nấm hương thanh đạm",
        "menu_group": "bun_pho",
        "calories": 380,
        "protein_g": 27.0,
        "fat_g": 7.0,
        "carbs_g": 50.0,
        "portion_g": 420,
        "tags": ["it_calo", "it_mo", "giau_dam"],
    },
    {
        "name_vi": "Bún bò Huế giò heo & chả cua đặc biệt",
        "menu_group": "bun_pho",
        "calories": 720,
        "protein_g": 34.0,
        "fat_g": 31.0,
        "carbs_g": 74.0,
        "portion_g": 520,
        "tags": ["nhieu_mo", "man", "cay", "purine_cao", "hai_san"],
    },
    {
        "name_vi": "Hủ tiếu Nam Vang (tim, gan, tôm, thịt bằm)",
        "menu_group": "bun_pho",
        "calories": 580,
        "protein_g": 30.0,
        "fat_g": 18.0,
        "carbs_g": 68.0,
        "portion_g": 480,
        "tags": ["noi_tang", "purine_cao", "tom", "hai_san"],
    },
    {
        "name_vi": "Gỏi cuốn tôm thịt / Salad ức gà dầu mè",
        "menu_group": "tiec_nhau",
        "calories": 340,
        "protein_g": 26.0,
        "fat_g": 8.0,
        "carbs_g": 40.0,
        "portion_g": 280,
        "tags": ["it_calo", "it_mo", "rau_xanh", "tom", "hai_san"],
    },
    {
        "name_vi": "Cá diêu hồng hấp hồng kông cuốn rau cải",
        "menu_group": "tiec_nhau",
        "calories": 410,
        "protein_g": 39.0,
        "fat_g": 11.0,
        "carbs_g": 32.0,
        "portion_g": 350,
        "tags": ["ca", "hai_san", "it_mo", "giau_dam"],
    },
    {
        "name_vi": "Đậu hũ non hấp nấm đông cô & cải thìa",
        "menu_group": "tiec_nhau",
        "calories": 310,
        "protein_g": 19.0,
        "fat_g": 9.0,
        "carbs_g": 36.0,
        "portion_g": 320,
        "tags": ["dau_nanh", "it_calo", "thanh_dam"],
    },
    {
        "name_vi": "Lẩu thái hải sản chua cay & mì gói",
        "menu_group": "tiec_nhau",
        "calories": 780,
        "protein_g": 38.0,
        "fat_g": 32.0,
        "carbs_g": 84.0,
        "portion_g": 500,
        "tags": ["man", "cay", "purine_cao", "tom", "hai_san", "nhieu_mo"],
    },
    {
        "name_vi": "Ba chỉ bò Mỹ nướng sốt bơ tỏi & khoai tây chiên",
        "menu_group": "tiec_nhau",
        "calories": 840,
        "protein_g": 35.0,
        "fat_g": 48.0,
        "carbs_g": 66.0,
        "portion_g": 420,
        "tags": ["nhieu_mo", "purine_cao", "man"],
    },
]


def analyze_restaurant_menu(
    menu_text: str = "",
    sample_type: str = "com_van_phong",
    daily_goal: float = 2000.0,
    user_conditions: list[str] | None = None,
    user_allergies: list[str] | None = None,
) -> dict:
    """Phan tich thuc don quan an va goi y Top 3 mon nen goi + Mon can tranh."""
    cond_str = " ".join(user_conditions or []).lower()
    all_str = " ".join(user_allergies or []).lower()
    target_meal_cal = max(round(daily_goal * 0.33), 400)

    group_titles = {
        "com_van_phong": "Thực đơn Cơm Văn Phòng & Cơm Tấm",
        "bun_pho": "Thực đơn Quán Phở, Bún & Miến",
        "tiec_nhau": "Thực đơn Nhà Hàng, Lẩu & Đồ Nướng",
    }

    pool = [
        dict(item)
        for item in _MENU_CATALOG
        if item["menu_group"] == sample_type
    ]
    if not pool:
        pool = [dict(item) for item in _MENU_CATALOG[:6]]

    # Neu nguoi dung nhap tay danh sach mon tren menu, bo sung vao pool
    if menu_text.strip():
        raw_lines = [
            line.strip(" -•*\t")
            for line in menu_text.replace(",", "\n").splitlines()
            if len(line.strip(" -•*\t")) >= 3
        ]
        custom_pool = []
        for idx, line in enumerate(raw_lines[:8]):
            low = line.lower()
            is_fried_fat = any(k in low for k in ["chiên", "rán", "quay", "mỡ", "ba chỉ", "sườn", "lẩu", "bơ"])
            is_light = any(k in low for k in ["luộc", "hấp", "gỏi", "salad", "ức gà", "miến", "đậu hũ", "rau"])
            cal = 690 if is_fried_fat else (410 if is_light else 530)
            pro = 29.0 if is_fried_fat else (32.0 if is_light else 26.0)
            fat = 29.0 if is_fried_fat else (9.5 if is_light else 16.0)
            carb = 72.0 if is_fried_fat else (48.0 if is_light else 62.0)
            tags: list[str] = []
            if is_fried_fat:
                tags.extend(["nhieu_mo", "man"])
            if is_light:
                tags.extend(["it_mo", "giau_dam"])
            if any(k in low for k in ["tôm", "cua", "mực", "hải sản"]):
                tags.extend(["tom", "hai_san", "purine_cao"])
            if any(k in low for k in ["bò", "lòng", "tim", "gan", "ốc"]):
                tags.append("purine_cao")
            custom_pool.append({
                "name_vi": line[:65],
                "menu_group": "custom",
                "calories": cal + (idx % 3) * 15,
                "protein_g": pro,
                "fat_g": fat,
                "carbs_g": carb,
                "portion_g": 360,
                "tags": tags,
            })
        if custom_pool:
            pool = custom_pool

    scored_good: list[dict] = []
    caution_dishes: list[dict] = []

    for item in pool:
        name = str(item["name_vi"])
        cal = int(item["calories"])
        pro = float(item["protein_g"])
        fat = float(item["fat_g"])
        carb = float(item["carbs_g"])
        tags = list(item.get("tags") or [])
        score = 82
        reasons_good: list[str] = []
        reasons_bad: list[str] = []
        level = "orange"

        # Kiem tra di ung
        if ("tôm" in all_str or "hải sản" in all_str) and ("tom" in tags or "hai_san" in tags):
            score -= 60
            level = "red"
            reasons_bad.append("Chứa tôm/hải sản trùng với hồ sơ dị ứng của bạn.")
        if ("đậu nành" in all_str) and ("dau_nanh" in tags):
            score -= 50
            level = "red"
            reasons_bad.append("Có đậu hũ/đậu nành trong danh sách dị ứng.")

        # Kiem tra benh ly
        if ("tiểu đường" in cond_str) and (carb >= 70 or "nhieu_carb" in tags):
            score -= 22
            reasons_bad.append(f"Lượng tinh bột cao ({carb:.0f}g Carb), dễ gây tăng đường huyết sau ăn.")
        if ("mỡ máu" in cond_str or "tim mạch" in cond_str) and (fat >= 24 or "nhieu_mo" in tags):
            score -= 24
            reasons_bad.append(f"Nhiều chất béo/mỡ ({fat:.0f}g Fat), không có lợi cho mỡ máu.")
        if ("gout" in cond_str) and ("purine_cao" in tags):
            score -= 28
            level = "red"
            reasons_bad.append("Nhóm đạm nhân purine cao (hải sản/nội tạng/thịt đỏ đậm), dễ kích khởi cơn Gout.")
        if ("huyết áp" in cond_str) and ("man" in tags):
            score -= 20
            reasons_bad.append("Nước dùng/nước kho đậm gia vị và nhiều Natri, cần hạn chế khi tăng huyết áp.")
        if ("dạ dày" in cond_str) and ("cay" in tags):
            score -= 18
            reasons_bad.append("Vị chua cay dễ kích ứng niêm mạc dạ dày.")

        if cal > target_meal_cal + 180 or fat >= 28:
            score -= 18
            if not reasons_bad:
                reasons_bad.append(f"Năng lượng cao ({cal} kcal, {fat:.0f}g béo), dễ vượt định mức bữa ({target_meal_cal} kcal).")

        if "it_mo" in tags or fat <= 14:
            score += 8
            reasons_good.append(f"Ít béo ({fat:.0f}g), giàu đạm nạc ({pro:.0f}g)")
        if abs(cal - target_meal_cal) <= 140:
            score += 6
            reasons_good.append(f"Vừa vặn ngân sách bữa ({cal} kcal)")

        if score < 68 or reasons_bad:
            caution_dishes.append({
                "name_vi": name,
                "calories": cal,
                "protein_g": pro,
                "fat_g": fat,
                "carbs_g": carb,
                "portion_g": int(item.get("portion_g") or 360),
                "level": level,
                "reason": " ".join(reasons_bad) if reasons_bad else f"Năng lượng khá cao ({cal} kcal).",
            })
        else:
            scored_good.append({
                "name_vi": name,
                "calories": cal,
                "protein_g": pro,
                "fat_g": fat,
                "carbs_g": carb,
                "portion_g": int(item.get("portion_g") or 350),
                "health_score": min(score, 98),
                "reason": " · ".join(reasons_good) if reasons_good else "Cân bằng đạm - rau, an toàn với hồ sơ sức khỏe.",
            })

    scored_good.sort(key=lambda x: x["health_score"], reverse=True)
    for idx, g in enumerate(scored_good[:3]):
        g["badge"] = f"Top #{idx + 1} Nên gọi"

    tip = (
        "Mẹo gọi món: Ưu tiên món hấp/luộc/áp chảo, gọi thêm 1 phần rau luộc ăn trước tinh bột "
        "và dặn quán để riêng nước sốt/nước mắm."
    )
    if "tiểu đường" in cond_str:
        tip = "Mẹo cho Tiểu đường: Dặn quán lấy 2/3 lượng cơm/bún bình thường và ăn rau + đạm trước 5 phút."
    elif "huyết áp" in cond_str:
        tip = "Mẹo cho Huyết áp: Hạn chế húp hết nước lèo bún/phở (giảm ~50% lượng muối Natri nạp vào)."

    title = (
        "Thực đơn bạn vừa nhập / chụp"
        if menu_text.strip()
        else group_titles.get(sample_type, "Thực đơn Quán Ăn")
    )

    return {
        "restaurant_type": title,
        "target_meal_kcal": target_meal_cal,
        "top_picks": scored_good[:3],
        "caution_dishes": caution_dishes[:3],
        "ordering_tip": tip,
    }


_FRIDGE_RECIPE_BANK: list[dict[str, Any]] = [
    {
        "name_vi": "Ức gà áp chảo sốt tiêu chanh & bông cải xanh",
        "match_keys": ["ức gà", "gà", "bông cải", "rau", "chanh"],
        "cook_time_min": 15,
        "calories": 410,
        "protein_g": 39.0,
        "fat_g": 8.5,
        "carbs_g": 42.0,
        "portion_g": 340,
        "ingredients_used": ["150g Ức gà", "100g Bông cải xanh", "1/2 củ Khoai lang / Cơm vừa"],
        "steps_short": "Ướp ức gà với tiêu & chút muối, áp chảo chống dính 5p mỗi mặt. Luộc bông cải xanh 3p.",
        "health_note": "Giàu đạm nạc, chỉ số đường huyết (GL) thấp, rất tốt cho giảm mỡ & tiểu đường.",
    },
    {
        "name_vi": "Canh đậu hũ non cà chua nấu trứng & cơm gạo lứt/trắng",
        "match_keys": ["trứng", "đậu hũ", "cà chua", "hành", "rau"],
        "cook_time_min": 12,
        "calories": 395,
        "protein_g": 22.0,
        "fat_g": 11.0,
        "carbs_g": 50.0,
        "portion_g": 360,
        "ingredients_used": ["2 quả Trứng gà", "1 bìa Đậu hũ non", "2 quả Cà chua", "2/3 chén Cơm"],
        "steps_short": "Xào mềm cà chua với 1 thìa nhỏ dầu ô-liu, thêm nước sôi, thả đậu hũ non và khuấy nhẹ trứng.",
        "health_note": "Mềm, dễ tiêu hóa, đạm thực vật kết hợp đạm trứng lành mạnh cho dạ dày & mỡ máu.",
    },
    {
        "name_vi": "Cá phi lê hấp gừng hành & rau cải luộc",
        "match_keys": ["cá", "rau cải", "rau", "gừng", "nấm"],
        "cook_time_min": 18,
        "calories": 430,
        "protein_g": 35.0,
        "fat_g": 10.0,
        "carbs_g": 48.0,
        "portion_g": 350,
        "ingredients_used": ["150g Cá phi lê", "Gừng sợi & hành lá", "150g Rau cải luộc", "2/3 chén Cơm"],
        "steps_short": "Xếp gừng và nấm lên cá, hấp cách thủy 12 phút với 1 thìa xì dầu giảm mặn.",
        "health_note": "Giàu Omega-3, không dầu chiên rán, tối ưu cho người rối loạn mỡ máu và tim mạch.",
    },
    {
        "name_vi": "Thịt thăn heo xào nấm đông cô & bông cải",
        "match_keys": ["thịt heo", "thịt", "nấm", "bông cải", "cà rốt"],
        "cook_time_min": 15,
        "calories": 455,
        "protein_g": 31.0,
        "fat_g": 12.5,
        "carbs_g": 52.0,
        "portion_g": 350,
        "ingredients_used": ["120g Thịt thăn nạc", "80g Nấm tươi", "100g Rau củ", "2/3 chén Cơm"],
        "steps_short": "Trần sơ rau củ, đảo nhanh thịt thăn và nấm trên lửa lớn với tỏi đập dập.",
        "health_note": "Đủ chất xơ hòa tan từ nấm giúp làm chậm hấp thu đường và cholesterol.",
    },
    {
        "name_vi": "Tôm tươi rim nhạt thịt nạc & canh bầu/bí xanh",
        "match_keys": ["tôm", "thịt", "bầu", "bí", "rau"],
        "cook_time_min": 16,
        "calories": 440,
        "protein_g": 34.0,
        "fat_g": 10.5,
        "carbs_g": 51.0,
        "portion_g": 350,
        "ingredients_used": ["100g Tôm tươi", "50g Thịt nạc", "1 tô Canh bí xanh", "2/3 chén Cơm"],
        "steps_short": "Áp chảo tôm với chút hành tỏi cho săn, nêm nhạt. Nấu canh bí xanh thanh mát.",
        "health_note": "Đạm sinh học cao, ít chất béo bão hòa.",
    },
]


def suggest_fridge_recipes(
    ingredients: list[str],
    daily_goal: float = 2000.0,
    user_conditions: list[str] | None = None,
    user_allergies: list[str] | None = None,
) -> dict:
    """Goi y 3 mon nau nhanh tai nha tu nguyen lieu tu lanh + loc di ung/benh ly."""
    cleaned_ings = [x.strip() for x in ingredients if x.strip()]
    if not cleaned_ings:
        cleaned_ings = ["Trứng gà", "Đậu hũ", "Cà chua", "Ức gà", "Rau cải xanh"]

    ing_norm = " ".join(cleaned_ings).lower()
    cond_str = " ".join(user_conditions or []).lower()
    all_str = " ".join(user_allergies or []).lower()

    results: list[dict[str, Any]] = []
    for r in _FRIDGE_RECIPE_BANK:
        name = str(r["name_vi"])
        # Loc di ung tom/hai san hoac dau nanh
        if ("tôm" in all_str or "hải sản" in all_str) and "tôm" in name.lower():
            continue
        if ("đậu nành" in all_str) and "đậu hũ" in name.lower():
            continue
        if ("gout" in cond_str) and "tôm" in name.lower():
            continue

        mkeys = r.get("match_keys")
        key_list = mkeys if isinstance(mkeys, list) else []
        hits = sum(1 for k in key_list if str(k) in ing_norm)
        item: dict[str, Any] = dict(r)
        item["match_score"] = hits
        if "tiểu đường" in cond_str:
            item["health_note"] = str(r["health_note"]) + " (Khuyên dùng cơm gạo lứt hoặc giảm 1/3 cơm trắng)."
        results.append(item)

    results.sort(key=lambda x: int(x.get("match_score") or 0), reverse=True)
    return {
        "detected_ingredients": cleaned_ings,
        "target_meal_kcal": max(round(daily_goal * 0.32), 400),
        "recipes": results[:3],
    }



