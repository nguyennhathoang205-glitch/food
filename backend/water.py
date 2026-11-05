"""Luu luong nuoc uong theo ngay (dong bo Supabase water_logs + fallback JSON)."""

import json
import os
import threading
from datetime import date, timedelta

_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "water_log.json"
)
_lock = threading.Lock()
_supabase = None

DEFAULT_GOAL_ML = 2000


def set_supabase_client(sb):
    """Gan Supabase client de dong bo nhat ky nuoc uong len bang water_logs."""
    global _supabase
    _supabase = sb


def _read():
    try:
        with open(_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write(data):
    with open(_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _sb_fetch_recent(user_key, start_iso):
    if _supabase is None:
        return None
    try:
        res = (
            _supabase.table("water_logs")
            .select("log_date, ml")
            .eq("user_key", user_key)
            .gte("log_date", start_iso)
            .execute()
        )
        if res.data is not None:
            return {str(r["log_date"]): int(r.get("ml") or 0) for r in res.data}
    except Exception:
        pass
    return None


def _sb_upsert(user_key, day_iso, ml_val):
    if _supabase is None:
        return False
    try:
        _supabase.table("water_logs").upsert({
            "user_key": user_key,
            "log_date": day_iso,
            "ml": int(ml_val),
        }).execute()
        return True
    except Exception:
        return False


def get_water(user_key):
    today = date.today()
    start_day = today - timedelta(days=6)

    with _lock:
        data = _read()
        user = dict(data.get(user_key) or {})
        sb_rows = _sb_fetch_recent(user_key, start_day.isoformat())
        if sb_rows:
            user.update(sb_rows)
            data[user_key] = user
            _write(data)

    history = []

    for i in range(6, -1, -1):
        d = today - timedelta(days=i)
        history.append({
            "date": d.isoformat(),
            "ml": int(user.get(d.isoformat(), 0))
        })

    return {
        "today_ml": int(user.get(today.isoformat(), 0)),
        "goal_ml": DEFAULT_GOAL_ML,
        "history": history,
    }


def add_water(user_key, ml):
    key = date.today().isoformat()

    with _lock:
        data = _read()
        user = data.setdefault(user_key, {})
        new_val = max(0, min(int(user.get(key, 0)) + int(ml), 10000))
        user[key] = new_val
        _write(data)
        _sb_upsert(user_key, key, new_val)

    return get_water(user_key)
