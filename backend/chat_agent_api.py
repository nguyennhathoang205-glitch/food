"""API cho Chat AI hieu ngu canh + ghi mon bang chat (xem chat_agent.py).

Khong sua /chat cu. Trong app.py them:

    import chat_agent_api
    chat_agent_api.init(app, supabase, _bearer_uid, _ask_gemini_chat,
                        _chat_context_parts, _daily_goal_of)

API (can dang nhap):
    POST /api/chat/agent          json: message, history, scan_context
        -> {reply, intent: chat|log_meal|delete_last, pending: null | {...}}
        KHONG ghi gi vao nhat ky.
    POST /api/chat/agent/confirm  json: {type: "log_meal", meal_type, items}
                                       | {type: "delete_meal", meal_id}
        -> thuc su ghi / xoa sau khi nguoi dung bam xac nhan.
"""

<<<<<<< HEAD
=======
from concurrent.futures import ThreadPoolExecutor

>>>>>>> a9402009 (chat nhanh + dang nhap Google)
from flask import Blueprint, jsonify, request

import chat_agent

bp = Blueprint("chat_agent", __name__, url_prefix="/api/chat")

_supabase = None
_get_uid = None
_ask = None
_context_parts = None
_goal_of = None


def init(app, supabase, get_uid, ask, context_parts=None, goal_of=None):
    """ask(contents, system_text) -> text|None.
    context_parts(user_key, scan_context) -> list[str]  (ho so, benh ly, ket qua quet).
    goal_of(user_key) -> muc tieu kcal/ngay."""
    global _supabase, _get_uid, _ask, _context_parts, _goal_of

    _supabase, _get_uid, _ask = supabase, get_uid, ask
    _context_parts, _goal_of = context_parts, goal_of
    app.register_blueprint(bp)


def _error(message, status):
    return jsonify({"status": "error", "message": message}), status


@bp.before_request
def _require_login():
    if request.method == "OPTIONS":
        return None

    if not _get_uid():
        return _error("Chua dang nhap", 401)

    return None


<<<<<<< HEAD
=======
def _load_context(uid, scan_context):
    """3 truy van DB doc lap (ho so + y te, muc tieu, nhat ky) chay SONG SONG thay vi
    noi duoi nhau -> bot ~2/3 thoi gian cho truoc khi hoi Gemini. Loi tung phan
    chi lam thieu ngu canh, khong lam hong chat."""

    def get_extra():
        if _context_parts is None:
            return ""
        return "\n".join(_context_parts(uid, scan_context) or [])

    def get_goal():
        return (_goal_of(uid) if _goal_of is not None else 0) or 2000

    def get_meals():
        return chat_agent.fetch_meals(_supabase, uid)

    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(fn) for fn in (get_extra, get_goal, get_meals)]
        defaults = ("", 2000, None)
        values = []

        for future, default in zip(futures, defaults):
            try:
                values.append(future.result(timeout=15))
            except Exception as e:
                print(f"[chat_agent] bo qua ngu canh phu: {e}")
                values.append(default)

    return tuple(values)


>>>>>>> a9402009 (chat nhanh + dang nhap Google)
@bp.route("/agent", methods=["POST"])
def agent():
    data = request.get_json(silent=True) or {}
    uid = _get_uid()

<<<<<<< HEAD
    extra = ""
    goal = 2000

    try:
        if _context_parts is not None:
            extra = "\n".join(_context_parts(uid, data.get("scan_context")) or [])
        if _goal_of is not None:
            goal = _goal_of(uid) or 2000
    except Exception as e:
        print(f"[chat_agent] bo qua ngu canh phu: {e}")
=======
    extra, goal, meals = _load_context(uid, data.get("scan_context"))
>>>>>>> a9402009 (chat nhanh + dang nhap Google)

    try:
        result, error = chat_agent.handle_message(
            _supabase, uid, data.get("message"), data.get("history"), _ask,
<<<<<<< HEAD
            extra_context=extra, daily_goal=goal,
=======
            extra_context=extra, daily_goal=goal, meals=meals,
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
        )
    except Exception as e:
        print(f"[chat_agent] agent loi: {e}")
        return _error("Trợ lý đang gặp sự cố, thử lại sau nhé.", 500)

    if error:
        return _error(error, 400 if "Thiếu" in error else 503)

    return jsonify({"status": "ok", **result})


@bp.route("/agent/confirm", methods=["POST"])
def confirm():
    data = request.get_json(silent=True) or {}
    uid = _get_uid()
    kind = data.get("type")

    try:
        if kind == "log_meal":
            result, error, status = chat_agent.confirm_log(
                _supabase, uid, data.get("meal_type"), data.get("items")
            )
        elif kind == "delete_meal":
            result, error, status = chat_agent.confirm_delete(
                _supabase, uid, data.get("meal_id")
            )
        else:
            return _error("Hành động không hợp lệ.", 400)
    except Exception as e:
        print(f"[chat_agent] confirm loi: {e}")
        return _error("Không thực hiện được, thử lại sau.", 500)

    if error:
        return _error(error, status)

    return jsonify({"status": "ok", **result})