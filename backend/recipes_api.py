"""API cho tinh nang "Cong thuc cong dong" (xem recipes.py).

Tach thanh Blueprint rieng de KHONG phai sua cac API san co. Trong app.py chi
can 2 dong (ngay canh community_api.init):

    import recipes_api
    recipes_api.init(app, supabase, _bearer_uid)

Cac API (deu can dang nhap), tien to /api/community/recipes:
    POST   /preview          json: title?, servings, ingredients[]  -> tinh thu
    POST   /                 multipart: data (json) + images (0-3 anh)
    GET    /?sort=new|top&mine=1
    GET    /<id>
    POST   /<id>/like        bat/tat tha tim
    POST   /<id>/eat         json: meal_type, portions -> ghi vao nhat ky
    DELETE /<id>             chi chu cong thuc
"""

import json
import os

from flask import Blueprint, jsonify, request

import community_foods
import recipes

bp = Blueprint("recipes", __name__, url_prefix="/api/community/recipes")

_supabase = None
_get_uid = None

ENABLED = os.environ.get("COMMUNITY_AI", "1") != "0"


def init(app, supabase, get_uid):
    global _supabase, _get_uid

    _supabase = supabase
    _get_uid = get_uid
    app.register_blueprint(bp)


def _error(message, status):
    return jsonify({"status": "error", "message": message}), status


@bp.before_request
def _require_login():
    if request.method == "OPTIONS":
        return None

    if not ENABLED:
        return _error("Tính năng cộng đồng đang tắt.", 503)

    if not _get_uid():
        return _error("Chua dang nhap", 401)

    return None


def _display_name(uid):
    """Ten hien thi tu bang profiles; loi / khong co thi dung ten mac dinh."""
    try:
        rows = (
            _supabase.table("profiles").select("display_name")
            .eq("user_key", uid).limit(1).execute()
        ).data
        return (rows[0].get("display_name") or "").strip() if rows else ""
    except Exception:
        return ""


@bp.route("/preview", methods=["POST"])
def preview():
    result, error = recipes.preview(request.get_json(silent=True) or {})

    if error:
        return _error(error, 400)

    return jsonify({"status": "ok", **result})


@bp.route("", methods=["POST"])
@bp.route("/", methods=["POST"])
def create():
    try:
        payload = json.loads(request.form.get("data") or "{}")
    except ValueError:
        return _error("Dữ liệu công thức không hợp lệ.", 400)

    if not isinstance(payload, dict):
        return _error("Dữ liệu công thức không hợp lệ.", 400)

    files = request.files.getlist("images")

    if len(files) > recipes.MAX_IMAGES:
        return _error(f"Tối đa {recipes.MAX_IMAGES} ảnh.", 400)

    images = [community_foods.open_image(f.read()) for f in files]
    uid = _get_uid()

    try:
        result, error, status = recipes.create_recipe(
            _supabase, uid, _display_name(uid), payload, images,
            teach_ai=request.form.get("teach_ai", "1") != "0",
        )
    except Exception as e:
        print(f"[recipes] create loi: {e}")
        return _error("Không đăng được công thức, thử lại sau.", 500)

    if error:
        return _error(error, status)

    return jsonify({"status": "ok", **result})


@bp.route("", methods=["GET"])
@bp.route("/", methods=["GET"])
def list_all():
    sort = "top" if request.args.get("sort") == "top" else "new"

    try:
        items = recipes.list_recipes(
            _supabase, _get_uid(), sort=sort,
            mine_only=request.args.get("mine") == "1",
        )
    except Exception as e:
        print(f"[recipes] list loi: {e}")
        return _error("Không tải được công thức.", 500)

    return jsonify({"status": "ok", "recipes": items})


@bp.route("/<int:recipe_id>", methods=["GET"])
def detail(recipe_id):
    try:
        item = recipes.get_recipe(_supabase, _get_uid(), recipe_id)
    except Exception as e:
        print(f"[recipes] detail loi: {e}")
        return _error("Không tải được công thức.", 500)

    if item is None:
        return _error("Không tìm thấy công thức.", 404)

    return jsonify({"status": "ok", "recipe": item})


@bp.route("/<int:recipe_id>/like", methods=["POST"])
def like(recipe_id):
    try:
        result = recipes.toggle_like(_supabase, _get_uid(), recipe_id)
    except Exception as e:
        print(f"[recipes] like loi: {e}")
        return _error("Không thả tim được, thử lại sau.", 500)

    if result is None:
        return _error("Không tìm thấy công thức.", 404)

    liked, count = result
    return jsonify({"status": "ok", "liked": liked, "like_count": count})


@bp.route("/<int:recipe_id>/eat", methods=["POST"])
def eat(recipe_id):
    data = request.get_json(silent=True) or {}

    try:
        result, error, status = recipes.eat_recipe(
            _supabase, _get_uid(), recipe_id,
            data.get("meal_type"), data.get("portions", 1),
        )
    except Exception as e:
        print(f"[recipes] eat loi: {e}")
        return _error("Không ghi được vào nhật ký, thử lại sau.", 500)

    if error:
        return _error(error, status)

    return jsonify({"status": "ok", **result})


@bp.route("/<int:recipe_id>", methods=["DELETE"])
def delete(recipe_id):
    try:
        removed = recipes.delete_recipe(_supabase, _get_uid(), recipe_id)
    except Exception as e:
        print(f"[recipes] delete loi: {e}")
        return _error("Không xóa được, thử lại sau.", 500)

    if not removed:
        return _error("Không tìm thấy công thức của bạn.", 404)

    return jsonify({"status": "ok"})