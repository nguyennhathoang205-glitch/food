"""API cho tinh nang "Mam com gia dinh" (xem family_meal.py).

Tach thanh Blueprint rieng. Trong app.py them (gan chỗ community_api.init):

    import family_api
    family_api.init(app, supabase, _bearer_uid, _ask_gemini_with_image,
                    _family_warnings)

Cac API (deu can dang nhap), tien to /api/family:
    POST /analyze   multipart: image            -> {dishes: [...]}
    POST /split     json: dishes, members       -> chia phan (tinh thu)
    POST /log       json: meal_type, dishes, members, me_index
                                                -> ghi phan cua nguoi do vao nhat ky
"""

from flask import Blueprint, jsonify, request

import family_meal

bp = Blueprint("family", __name__, url_prefix="/api/family")

_supabase = None
_get_uid = None
_ask_gemini = None
_warnings = None


def init(app, supabase, get_uid, ask_gemini, warnings_fn=None):
    """ask_gemini(jpeg_bytes, prompt) -> text|None.
    warnings_fn(user_key, ten_cac_mon, tong_dinh_duong_cua_toi) -> list (tuy chon)."""
    global _supabase, _get_uid, _ask_gemini, _warnings

    _supabase = supabase
    _get_uid = get_uid
    _ask_gemini = ask_gemini
    _warnings = warnings_fn
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


@bp.route("/analyze", methods=["POST"])
def analyze():
    if "image" not in request.files:
        return _error("Thiếu ảnh.", 400)

    try:
        dishes, error = family_meal.analyze(
            request.files["image"].read(), _ask_gemini
        )
    except Exception as e:
        print(f"[family] analyze loi: {e}")
        return _error("Không phân tích được ảnh, thử lại sau.", 500)

    if error:
        return _error(error, 422)

    return jsonify({"status": "ok", "dishes": dishes})


@bp.route("/split", methods=["POST"])
def split():
    data = request.get_json(silent=True) or {}
    result, error = family_meal.compute(data.get("dishes"), data.get("members"))

    if error:
        return _error(error, 400)

    # Canh bao suc khoe CHI cho nguoi dung dang dang nhap (ho so benh ly la cua
    # ho, khong ap cho nguoi khac trong nha).
    warnings = []

    if _warnings is not None:
        try:
            me_index = int(data.get("me_index", 0))
            me = result["members"][me_index]
            names = [d["name_vi"] for d in me["dishes"]]
            warnings = _warnings(_get_uid(), names, {
                "calories": me["calories"], "protein_g": me["protein_g"],
                "fat_g": me["fat_g"], "carbs_g": me["carbs_g"],
            }) or []
        except Exception as e:
            print(f"[family] bo qua canh bao: {e}")
            warnings = []

    return jsonify({"status": "ok", "warnings": warnings, **result})


@bp.route("/log", methods=["POST"])
def log():
    data = request.get_json(silent=True) or {}

    try:
        result, error, status = family_meal.log_member(
            _supabase, _get_uid(), data.get("meal_type"),
            data.get("dishes"), data.get("members"), data.get("me_index", 0),
        )
    except Exception as e:
        print(f"[family] log loi: {e}")
        return _error("Không ghi được vào nhật ký, thử lại sau.", 500)

    if error:
        return _error(error, status)

    return jsonify({"status": "ok", **result})