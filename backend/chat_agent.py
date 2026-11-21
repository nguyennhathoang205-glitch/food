"""Chat AI hieu ngu canh + ghi mon bang cau lenh trong chat.

Chi chua logic (khong phu thuoc Flask / Gemini that) de de test. API nam o
chat_agent_api.py.

Y tuong:
1. Moi cau hoi, server gan them NGU CANH THAT: hom nay nguoi dung da an gi, bao
   nhieu kcal, con lai bao nhieu so voi muc tieu, trung binh 7 ngay qua, gio
   hien tai. Nho vay "hom nay toi an bao nhieu roi?" duoc tra loi bang so that.
2. Gemini tra ve JSON gom y dinh: chat | log_meal | delete_last.
3. AN TOAN: chat KHONG BAO GIO tu ghi vao nhat ky. Khi nguoi dung noi "trua nay
   toi an 1 to pho bo", server chi tra ve de xuat (pending) -> app hien the
   "Ghi vao nhat ky / Bo qua" -> chi khi bam xac nhan moi ghi. Neu AI hieu sai
   thi khong lam hong du lieu.
4. Xoa mon cung can xac nhan; server tu tim mon vua ghi (khong tin id do AI dua).
"""

import json
import re
from datetime import datetime, timedelta, timezone

MEAL_SLOTS = ("Bữa sáng", "Bữa trưa", "Bữa tối", "Ăn phụ")
VN_TZ = timezone(timedelta(hours=7))
WEEKDAYS = ["thứ Hai", "thứ Ba", "thứ Tư", "thứ Năm", "thứ Sáu", "thứ Bảy", "Chủ nhật"]

MAX_MEALS = 8
MAX_HISTORY = 10

AGENT_PROMPT = """Ban la tro ly dinh duong than thien trong app "FoodScan AI".
Tra loi NGAN GON (toi da 4 cau), bang tieng Viet, giong nhu nhan tin voi ban be.
Khong chan doan y te; neu nguoi dung co benh ly/di ung thi nhac than trong.
{context}
QUY TAC DUNG SO LIEU: khi nguoi dung hoi ve hom nay da an bao nhieu, con bao nhieu
kcal, tuan nay an the nao... CHI dung so trong muc NGU CANH o tren. Neu NGU CANH
khong co thi noi ro la chua co du lieu, TUYET DOI khong bia so. Nho rang nguoi
dung co the chua ghi het cac bua.

Tra ve DUNG 1 JSON (khong them chu nao khac):
{{"intent": "chat" | "log_meal" | "delete_last",
  "reply": "cau tra loi ngan",
  "meal_type": "Bữa sáng" | "Bữa trưa" | "Bữa tối" | "Ăn phụ",
  "meals": [{{"name_vi": "...", "portion_g": so, "calories": so,
             "protein_g": so, "fat_g": so, "carbs_g": so}}]}}

Cach chon intent:
- "log_meal": CHI khi nguoi dung noi minh DA an/uong mon cu the (vd "trua nay toi an
  1 to pho bo", "vua uong ly ca phe sua da", "ghi giup toi 2 qua trung") hoac nho ghi.
  Dien meals (moi mon 1 phan tu, uoc tinh khoi luong va dinh duong cho dung so luong
  nguoi dung noi) va meal_type theo ngu canh (gio hien tai neu ho khong noi bua nao).
- "delete_last": nguoi dung muon xoa / huy mon vua ghi ("ghi nham roi", "xoa mon vua ghi").
- "chat": moi truong hop con lai, GOM CA cau hoi hoac gia dinh ("an pho co beo khong",
  "neu toi an com tam thi sao"). Khi do de meals = [] va bo qua meal_type.
Luon dien "reply". Voi log_meal/delete_last, reply chi la 1 cau dan nhap, server se
hien thi chi tiet de nguoi dung xac nhan."""


# ------------------------------------------------------------------
# Thoi gian (gio Viet Nam)
# ------------------------------------------------------------------

def local_datetime(created_at):
    text = str(created_at or "").strip()

    if not text:
        return None

    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    return dt.astimezone(VN_TZ)


def slot_for_hour(hour):
    if 5 <= hour < 10:
        return "Bữa sáng"
    if 10 <= hour < 14:
        return "Bữa trưa"
    if 17 <= hour < 21:
        return "Bữa tối"
    return "Ăn phụ"


def normalize_slot(raw, now):
    """Dua ten bua ve 4 ten chuan; khong hieu thi theo gio hien tai."""
    text = " ".join(str(raw or "").lower().split())
    aliases = {
        "bữa sáng": "Bữa sáng", "breakfast": "Bữa sáng",
        "bữa trưa": "Bữa trưa", "lunch": "Bữa trưa",
        "bữa tối": "Bữa tối", "dinner": "Bữa tối",
        "ăn phụ": "Ăn phụ", "bữa phụ": "Ăn phụ", "snack": "Ăn phụ",
    }
    return aliases.get(text) or slot_for_hour(now.hour)


# ------------------------------------------------------------------
# Ngu canh that tu nhat ky
# ------------------------------------------------------------------

def _num(value):
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def build_context(supabase, user_key, now=None, daily_goal=2000):
    """Doan van ngu canh: hom nay + 7 ngay qua. Loi doc DB thi tra ve chuoi rong
    (chat van chay, chi thieu ngu canh)."""
    now = now or datetime.now(VN_TZ)
    cutoff = (now - timedelta(days=8)).astimezone(timezone.utc).isoformat()

    try:
        meals = (
            supabase.table("meal_logs").select("*")
            .eq("user_key", user_key).gte("created_at", cutoff)
            .order("created_at", desc=True).limit(500).execute()
        ).data or []
    except Exception as e:
        print(f"[chat_agent] khong doc duoc nhat ky: {e}")
        return ""

    today = now.strftime("%Y-%m-%d")
    by_day = {}

    for meal in meals:
        dt = local_datetime(meal.get("created_at"))

        if dt is None:
            continue

        by_day.setdefault(dt.strftime("%Y-%m-%d"), []).append(meal)

    lines = [
        f"Bay gio la {now.strftime('%H:%M')} (gio Viet Nam), "
        f"{WEEKDAYS[now.weekday()]} {now.strftime('%d/%m')}."
    ]

    today_meals = by_day.get(today, [])

    if today_meals:
        total = {k: sum(_num(m.get(k)) for m in today_meals)
                 for k in ("calories", "protein_g", "fat_g", "carbs_g")}
        by_slot = {}

        for m in reversed(today_meals):   # cu -> moi
            by_slot.setdefault(m.get("meal_type") or "Khac", []).append(
                f"{m.get('food_name')} ({round(_num(m.get('calories')))} kcal)"
            )

        slots = "; ".join(f"{slot}: {', '.join(items)}" for slot, items in by_slot.items())
        remaining = round(daily_goal - total["calories"])

        lines.append(f"Hom nay da ghi: {slots}.")
        lines.append(
            f"Tong hom nay: {round(total['calories'])} kcal / muc tieu {round(daily_goal)} kcal "
            f"({'con lai ' + str(remaining) if remaining >= 0 else 'vuot ' + str(-remaining)} kcal), "
            f"dam {round(total['protein_g'])}g, beo {round(total['fat_g'])}g, "
            f"tinh bot {round(total['carbs_g'])}g."
        )
    else:
        lines.append("Hom nay nguoi dung CHUA ghi bua nao.")

    past = [
        sum(_num(m.get("calories")) for m in day_meals)
        for day, day_meals in by_day.items() if day != today
    ]

    if past:
        lines.append(
            f"Cac ngay truoc (chi tinh ngay co ghi, {len(past)} ngay trong 7 ngay qua): "
            f"trung binh {round(sum(past) / len(past))} kcal/ngay."
        )

    return "\n".join(lines)


# ------------------------------------------------------------------
# Doc tra loi cua Gemini
# ------------------------------------------------------------------

def parse_agent_json(text):
    text = str(text or "").strip()
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.MULTILINE).strip()

    try:
        data = json.loads(text)
    except ValueError:
        return None

    return data if isinstance(data, dict) else None


def _number(value, low, high):
    if value in (None, ""):
        return None

    try:
        number = float(value)
    except (TypeError, ValueError):
        return None

    return number if low <= number <= high else None


def clean_meals(raw):
    """Mon thieu ten / khoi luong / kcal bi bo (khong doan). Toi da MAX_MEALS."""
    if not isinstance(raw, list):
        return []

    meals = []

    for item in raw[:MAX_MEALS]:
        if not isinstance(item, dict):
            continue

        name = " ".join(str(item.get("name_vi") or item.get("food_name") or "").split())[:60]
        grams = _number(item.get("portion_g"), 1, 5000)
        calories = _number(item.get("calories"), 0, 5000)

        if len(name) < 2 or grams is None or calories is None:
            continue

        meals.append({
            "name_vi": name,
            "portion_g": round(grams),
            "calories": round(calories, 1),
            "protein_g": round(_number(item.get("protein_g"), 0, 500) or 0.0, 1),
            "fat_g": round(_number(item.get("fat_g"), 0, 500) or 0.0, 1),
            "carbs_g": round(_number(item.get("carbs_g"), 0, 500) or 0.0, 1),
        })

    return meals


def _totals(meals):
    return {k: round(sum(m[k] for m in meals), 1)
            for k in ("calories", "protein_g", "fat_g", "carbs_g")}


def _history_contents(history, message):
    """Lich su hoi thoai dang Gemini contents. Bo cau cuoi cua nguoi dung neu
    trung voi tin nhan hien tai (app gui history da gom ca tin nhan moi)."""
    turns = [t for t in (history or []) if isinstance(t, dict) and t.get("text")]

    if turns and turns[-1].get("role") == "user" and str(turns[-1]["text"]).strip() == message:
        turns = turns[:-1]

    contents = [
        {"role": "user" if t.get("role") == "user" else "model",
         "parts": [{"text": str(t["text"])}]}
        for t in turns[-MAX_HISTORY:]
    ]
    contents.append({"role": "user", "parts": [{"text": message}]})
    return contents


# ------------------------------------------------------------------
# Xu ly 1 tin nhan
# ------------------------------------------------------------------

def handle_message(supabase, user_key, message, history, ask, extra_context="",
                   daily_goal=2000, now=None):
    """ask(contents, system_text) -> text|None (Gemini, JSON mode).

    Tra ve (ket_qua, loi). ket_qua = {reply, intent, pending}.
    KHONG ghi gi vao nhat ky o day.
    """
    message = str(message or "").strip()

    if not message:
        return None, "Thiếu tin nhắn."

    now = now or datetime.now(VN_TZ)
    context = build_context(supabase, user_key, now=now, daily_goal=daily_goal)
    context_block = "\nNGU CANH:\n" + "\n".join(
        part for part in (extra_context, context) if part
    ) + "\n"

    system_text = AGENT_PROMPT.format(context=context_block)
    text = ask(_history_contents(history, message), system_text)

    if text is None:
        return None, "AI đang quá tải hoặc lỗi, thử lại sau nhé."

    data = parse_agent_json(text)

    # Gemini khong tra JSON -> coi la cau chat thuong (khong mat cau tra loi).
    if data is None:
        return {"reply": str(text).strip(), "intent": "chat", "pending": None}, None

    intent = str(data.get("intent") or "chat")
    reply = " ".join(str(data.get("reply") or "").split()) or "Mình đã hiểu."

    if intent == "log_meal":
        meals = clean_meals(data.get("meals"))

        if meals:
            meal_type = normalize_slot(data.get("meal_type"), now)
            total = _totals(meals)
            names = ", ".join(
                f"{m['name_vi']} (~{round(m['calories'])} kcal)" for m in meals
            )
            return {
                "reply": (
                    f"Mình ghi vào {meal_type}: {names}. "
                    f"Tổng khoảng {round(total['calories'])} kcal (ước tính). Bạn xác nhận nhé?"
                ),
                "intent": "log_meal",
                "pending": {
                    "type": "log_meal", "meal_type": meal_type,
                    "items": meals, "total": total,
                },
            }, None

        intent = "chat"   # khong tach duoc mon hop le -> khong ghi gi

    if intent == "delete_last":
        last = _latest_meal(supabase, user_key)

        if last is None:
            return {"reply": "Mình chưa thấy món nào trong nhật ký để xóa.",
                    "intent": "chat", "pending": None}, None

        return {
            "reply": (
                f"Bạn muốn xóa \"{last.get('food_name')}\" "
                f"({round(_num(last.get('calories')))} kcal, {last.get('meal_type')}) "
                "vừa ghi, đúng không?"
            ),
            "intent": "delete_last",
            "pending": {
                "type": "delete_meal",
                "meal": {
                    "id": last.get("id"), "food_name": last.get("food_name"),
                    "calories": _num(last.get("calories")),
                    "meal_type": last.get("meal_type"),
                },
            },
        }, None

    return {"reply": reply, "intent": "chat", "pending": None}, None


def _latest_meal(supabase, user_key):
    rows = (
        supabase.table("meal_logs").select("*").eq("user_key", user_key)
        .order("created_at", desc=True).limit(1).execute()
    ).data or []
    return rows[0] if rows else None


# ------------------------------------------------------------------
# Xac nhan (moi thuc su ghi / xoa)
# ------------------------------------------------------------------

def confirm_log(supabase, user_key, meal_type, items, now=None):
    """Ghi cac mon da duoc nguoi dung xac nhan. Tra ve (ket_qua, loi, http)."""
    now = now or datetime.now(VN_TZ)
    meals = clean_meals(items)

    if not meals:
        return None, "Không có món hợp lệ để ghi.", 400

    meal_type = normalize_slot(meal_type, now)
    rows = [
        {
            "user_key": user_key, "food_name": m["name_vi"],
            "meal_type": meal_type, "portion_g": max(m["portion_g"], 10),
            "calories": m["calories"], "protein_g": m["protein_g"],
            "fat_g": m["fat_g"], "carbs_g": m["carbs_g"],
        }
        for m in meals
    ]
    saved = supabase.table("meal_logs").insert(rows).execute()
    total = _totals(meals)

    return {
        "saved": len(saved.data or rows),
        "reply": f"Đã ghi {len(rows)} món vào {meal_type} (~{round(total['calories'])} kcal).",
    }, None, 200


def confirm_delete(supabase, user_key, meal_id):
    """Chi xoa mon CUA CHINH NGUOI DUNG. Tra ve (ket_qua, loi, http)."""
    try:
        meal_id = int(meal_id)
    except (TypeError, ValueError):
        return None, "Món cần xóa không hợp lệ.", 400

    found = (
        supabase.table("meal_logs").select("*")
        .eq("id", meal_id).eq("user_key", user_key).limit(1).execute()
    ).data

    if not found:
        return None, "Không tìm thấy món trong nhật ký của bạn.", 404

    supabase.table("meal_logs").delete().eq("id", meal_id).eq("user_key", user_key).execute()
    return {"reply": f"Đã xóa \"{found[0].get('food_name')}\" khỏi nhật ký."}, None, 200