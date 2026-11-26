"""API cho tinh nang "Cong dong day AI mon moi" (xem community_foods.py).

Tach thanh Blueprint rieng de KHONG phai sua cac API san co trong app.py.
Trong app.py chi can 2 dong:

    import community_api
    community_api.init(app, supabase, _bearer_uid)

Cac API (deu can dang nhap):
    POST /api/community/teach      form: name_vi, images (1-5 file), tuy chon
                                   calories_per_100g, protein_g, fat_g, carbs_g
    POST /api/community/recognize  form: image
    GET  /api/community/foods      danh sach mon + thong ke dong gop

Tat tinh nang: dat bien moi truong COMMUNITY_AI=0.
"""

import os

from flask import Blueprint, jsonify, request

import community_foods

bp = Blueprint("community", __name__, url_prefix="/api/community")

_supabase = None
_get_uid = None

ENABLED = os.environ.get("COMMUNITY_AI", "1") != "0"


def init(app, supabase, get_uid):
    """Goi 1 lan trong app.py sau khi tao supabase client."""
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


@bp.route("/teach", methods=["POST"])
def teach():
    files = request.files.getlist("images") or request.files.getlist("image")

    if not files:
        return _error("Cần ít nhất 1 ảnh.", 400)

    if len(files) > community_foods.MAX_IMAGES_PER_TEACH:
        return _error(
            f"Tối đa {community_foods.MAX_IMAGES_PER_TEACH} ảnh mỗi lần.", 400
        )

    images = [community_foods.open_image(f.read()) for f in files]

    try:
        result, error = community_foods.teach(
            _supabase,
            _get_uid(),
            request.form.get("name_vi"),
            images,
            nutrition=request.form,
        )
    except Exception as e:
        print(f"[community] teach loi: {e}")
        return _error("Không lưu được món mới, thử lại sau.", 500)

    if error:
        return _error(error, 400)

    return jsonify({"status": "ok", **result})


@bp.route("/recognize", methods=["POST"])
def recognize():
    if "image" not in request.files:
        return _error("Thiếu ảnh.", 400)

    image = community_foods.open_image(request.files["image"].read())

    if image is None:
        return _error("Ảnh không hợp lệ.", 400)

    try:
        result = community_foods.recognize(_supabase, image)
    except Exception as e:
        print(f"[community] recognize loi: {e}")
        return _error("Không nhận diện được, thử lại sau.", 500)

    return jsonify({
        "status": "ok",
        "threshold": community_foods.MATCH_THRESHOLD,
        **result,
    })


@bp.route("/foods", methods=["GET"])
def foods():
    try:
        data = community_foods.list_foods(_supabase, _get_uid())
    except Exception as e:
        print(f"[community] foods loi: {e}")
        return _error("Không tải được danh sách.", 500)

    return jsonify({"status": "ok", **data})


def match_for_detect(image):
    """Dung trong /detect: tra ve mon cong dong neu nhan ra CHAC CHAN, nguoc
<<<<<<< HEAD
    lai None. Khong bao gio lam hong hay lam cham /detect: neu CLIP chua nap
    xong trong RAM thi kich hoat warmup ngam va tra None ngay."""
    if not ENABLED or _supabase is None:
        return None

    if not community_foods.is_model_loaded():
        community_foods.warmup_async()
        return None

=======
    lai None. Khong bao gio lam hong /detect (loi gi cung tra None)."""
    if not ENABLED or _supabase is None:
        return None

>>>>>>> a9402009 (chat nhanh + dang nhap Google)
    try:
        return community_foods.recognize(_supabase, image)["best"]
    except Exception as e:
        print(f"[community] bo qua trong /detect: {e}")
        return None