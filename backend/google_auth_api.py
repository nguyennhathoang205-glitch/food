"""Dang nhap bang Google (OAuth "authorization code" qua backend).

Vi sao lam qua backend thay vi plugin google_sign_in: plugin buoc client ID gan voi
bundle ID cua app, ma Sideloadly doi bundle ID khi ky -> se loi. Cach nay chay moi
nen tang vi Google chi biet dia chi backend (redirect URI).

Luong:
  app mo trinh duyet he thong -> GET /api/auth/google/start
      -> Google (chon tai khoan) -> GET /api/auth/google/callback?code&state
      -> backend doi code lay email, tao/tim tai khoan, cap token cua app
      -> 302 ve  foodscan://auth?token=...&uid=...&name=...&email=...
  app (flutter_web_auth_2) bat link do va luu phien dang nhap.

Bien moi truong (them vao Hugging Face -> Settings -> Secrets):
    GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
    PUBLIC_BASE_URL  (tuy chon, vd https://quangdadada-foodscan-api.hf.space)

Trong app.py them:
    import google_auth_api
    google_auth_api.init(app, auth_store)
"""

import base64
import hashlib
import hmac
import json
import os
import re
import time
import urllib.parse
import urllib.request

from flask import Blueprint, Response, redirect, request

bp = Blueprint("google_auth", __name__, url_prefix="/api/auth/google")

STATE_TTL = 600
DEFAULT_SCHEME = "foodscan"
_SCHEME_RE = re.compile(r"^[a-z][a-z0-9+.\-]{1,30}$")
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"

_auth = None
_exchange = None


def init(app, auth_store, exchange=None):
    """exchange(code, redirect_uri) -> dict userinfo (de test); mac dinh goi Google that."""
    global _auth, _exchange
    _auth = auth_store
    _exchange = exchange or google_exchange
    app.register_blueprint(bp)


# ------------------------------------------------------------------
# state ky HMAC (khong can luu session)
# ------------------------------------------------------------------

def _sign(payload):
    body = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()
    sig = hmac.new(_auth._secret(), body.encode(), hashlib.sha256).hexdigest()
    return f"{body}.{sig}"


def _unsign(state):
    try:
        body, sig = str(state).rsplit(".", 1)
        expected = hmac.new(_auth._secret(), body.encode(), hashlib.sha256).hexdigest()

        if not hmac.compare_digest(sig, expected):
            return None

        data = json.loads(base64.urlsafe_b64decode(body.encode()))

        return data if data.get("exp", 0) >= time.time() else None
    except Exception:
        return None


def _safe_scheme(raw):
    raw = str(raw or DEFAULT_SCHEME).lower()
    return raw if _SCHEME_RE.match(raw) and raw not in ("http", "https", "javascript") \
        else DEFAULT_SCHEME


def _public_base():
    base = os.environ.get("PUBLIC_BASE_URL") or request.url_root
    base = base.rstrip("/")

    if base.startswith("http://") and "localhost" not in base and "127.0.0.1" not in base:
        base = "https://" + base[len("http://"):]    # sau proxy (Hugging Face) luon la https

    return base


def _redirect_uri():
    return _public_base() + "/api/auth/google/callback"


def _page(message, status=400):
    return Response(
        f"<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>"
        f"<body style='font-family:sans-serif;padding:24px'><p>{message}</p></body>",
        status=status, mimetype="text/html",
    )


def _back(scheme, **params):
    return redirect(f"{scheme}://auth?" + urllib.parse.urlencode(params), code=302)


# ------------------------------------------------------------------
# Goi Google that (stdlib, khong them thu vien)
# ------------------------------------------------------------------

def google_exchange(code, redirect_uri):
    form = urllib.parse.urlencode({
        "code": code,
        "client_id": os.environ.get("GOOGLE_CLIENT_ID", ""),
        "client_secret": os.environ.get("GOOGLE_CLIENT_SECRET", ""),
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode()

    req = urllib.request.Request(
        TOKEN_URL, data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=15) as res:
        token = json.load(res)

    info = urllib.request.Request(
        USERINFO_URL, headers={"Authorization": "Bearer " + token["access_token"]}
    )
    with urllib.request.urlopen(info, timeout=15) as res:
        return json.load(res)


# ------------------------------------------------------------------
# Route
# ------------------------------------------------------------------

@bp.route("/start", methods=["GET"])
def start():
    client_id = os.environ.get("GOOGLE_CLIENT_ID")

    if not client_id:
        return _page("Máy chủ chưa cấu hình đăng nhập Google (thiếu GOOGLE_CLIENT_ID).", 503)

    scheme = _safe_scheme(request.args.get("scheme"))
    state = _sign({"scheme": scheme, "exp": int(time.time()) + STATE_TTL})

    query = urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": _redirect_uri(),
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "prompt": "select_account",
    })
    return redirect(f"{AUTH_URL}?{query}", code=302)


@bp.route("/callback", methods=["GET"])
def callback():
    data = _unsign(request.args.get("state"))

    if data is None:
        return _page("Phiên đăng nhập đã hết hạn hoặc không hợp lệ. Hãy quay lại app và thử lại.")

    scheme = _safe_scheme(data.get("scheme"))

    if request.args.get("error") or not request.args.get("code"):
        return _back(scheme, error="Bạn đã hủy đăng nhập Google.")

    try:
        info = _exchange(request.args["code"], _redirect_uri())
    except Exception as e:
        print(f"[google_auth] doi code that bai: {e}")
        return _back(scheme, error="Không đăng nhập được bằng Google, thử lại sau nhé.")

    if not info.get("email") or info.get("email_verified") not in (True, "true"):
        return _back(scheme, error="Email Google chưa được xác minh.")

    user, error = _auth.google_login(info["email"], info.get("name"))

    if error or not user:
        return _back(scheme, error=error or "Không đăng nhập được.")

    return _back(
        scheme,
        token=_auth.make_token(user["id"]),
        uid=user["id"], name=user["name"], email=user["email"],
    )