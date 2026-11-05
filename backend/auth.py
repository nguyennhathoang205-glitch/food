"""Xac thuc nguoi dung: dang ky / dang nhap / token ky HMAC.

Ho tro luu tru dong bo Supabase (bang app_users) kem fallback file JSON
(users.json) de chay offline / test ma khong mat du lieu khi deploy Cloud.
Token = base64(payload).chu_ky_HMAC, het han sau 30 ngay.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import threading
import time
import uuid

_DIR = os.path.dirname(os.path.abspath(__file__))
_USERS_PATH = os.path.join(_DIR, "users.json")
_SECRET_PATH = os.path.join(_DIR, ".auth_secret")
_lock = threading.Lock()
_supabase = None

TOKEN_TTL = 30 * 24 * 3600
GUEST_ID = "demo-user"
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def set_supabase_client(sb):
    """Gan Supabase client de dong bo tai khoan len Cloud (neu bang app_users da tao)."""
    global _supabase
    _supabase = sb


def _secret():
    env = os.environ.get("AUTH_SECRET")

    if env:
        return env.encode()

    if not os.path.exists(_SECRET_PATH):
        with open(_SECRET_PATH, "w", encoding="utf-8") as f:
            f.write(secrets.token_hex(32))

    with open(_SECRET_PATH, "r", encoding="utf-8") as f:
        return f.read().strip().encode()


def _read():
    try:
        with open(_USERS_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write(data):
    with open(_USERS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _hash(password, salt):
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode(), bytes.fromhex(salt), 120_000
    ).hex()


def make_token(uid):
    payload = base64.urlsafe_b64encode(
        json.dumps({"uid": uid, "exp": int(time.time()) + TOKEN_TTL}).encode()
    ).decode()

    sig = hmac.new(_secret(), payload.encode(), hashlib.sha256).hexdigest()

    return f"{payload}.{sig}"


def verify_token(token):
    """Tra ve uid neu token hop le va chua het han, nguoc lai None."""
    try:
        payload, sig = token.rsplit(".", 1)

        expected = hmac.new(
            _secret(), payload.encode(), hashlib.sha256
        ).hexdigest()

        if not hmac.compare_digest(sig, expected):
            return None

        data = json.loads(base64.urlsafe_b64decode(payload.encode()))

        if data["exp"] < time.time():
            return None

        return data["uid"]
    except Exception:
        return None


def _sb_find_user(email):
    if _supabase is None:
        return None
    try:
        res = (
            _supabase.table("app_users")
            .select("*")
            .eq("email", email)
            .limit(1)
            .execute()
        )
        if res.data:
            row = res.data[0]
            return {
                "id": row["id"],
                "name": row["name"],
                "salt": row["salt"],
                "hash": row["password_hash"],
                "created": row.get("created_at", int(time.time())),
            }
    except Exception:
        pass
    return None


def _sb_save_user(email, record):
    if _supabase is None:
        return False
    try:
        _supabase.table("app_users").upsert({
            "id": record["id"],
            "email": email,
            "name": record["name"],
            "salt": record["salt"],
            "password_hash": record["hash"],
            "created_at": record["created"],
        }).execute()
        return True
    except Exception:
        return False


def register(email, password, name):
    email = (email or "").strip().lower()
    name = (name or "").strip() or email.split("@")[0]

    if not _EMAIL_RE.match(email):
        return None, "Email không hợp lệ."

    if len(password or "") < 6:
        return None, "Mật khẩu tối thiểu 6 ký tự."

    with _lock:
        users = _read()

        if email in users or _sb_find_user(email) is not None:
            return None, "Email này đã được đăng ký."

        salt = secrets.token_hex(16)
        uid = "u" + uuid.uuid4().hex[:12]

        record = {
            "id": uid,
            "name": name,
            "salt": salt,
            "hash": _hash(password, salt),
            "created": int(time.time()),
        }
        users[email] = record
        _write(users)
        _sb_save_user(email, record)

    return {"id": uid, "email": email, "name": name}, None


def login(email, password):
    email = (email or "").strip().lower()
    user = _read().get(email)
    if not user:
        user = _sb_find_user(email)
        if user:
            with _lock:
                users = _read()
                users[email] = user
                _write(users)

    if not user or not hmac.compare_digest(
        user["hash"], _hash(password or "", user["salt"])
    ):
        return None, "Sai email hoặc mật khẩu."

    return {"id": user["id"], "email": email, "name": user["name"]}, None
