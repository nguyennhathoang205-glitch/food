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


@bp.route("/agent", methods=["POST"])
def agent():
    data = request.get_json(silent=True) or {}
    uid = _get_uid()

    extra = ""
    goal = 2000

    try:
        if _context_parts is not None:
            extra = "\n".join(_context_parts(uid, data.get("scan_context")) or [])
        if _goal_of is not None:
            goal = _goal_of(uid) or 2000
    except Exception as e:
        print(f"[chat_agent] bo qua ngu canh phu: {e}")

    try:
        result, error = chat_agent.handle_message(
            _supabase, uid, data.get("message"), data.get("history"), _ask,
            extra_context=extra, daily_goal=goal,
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