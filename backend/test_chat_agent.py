"""Test Chat AI hieu ngu canh + ghi mon bang chat - khong can mang / Gemini / Supabase.

Chay trong thu muc backend/:
    python -m pytest test_chat_agent.py -q
"""
import json
from datetime import datetime, timezone

from flask import Flask

import chat_agent as ca
import chat_agent_api

VN = ca.VN_TZ
NOW = datetime(2026, 11, 17, 14, 20, tzinfo=VN)       # Thu Ba 14:20 gio VN


# ---------------- Supabase gia (co order / gte / delete) ----------------

class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters, self.gte_filters = [], []
        self.to_insert, self._limit, self.deleting = None, None, False
        self._order = None

    def select(self, *_):
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
        return self

    def gte(self, column, value):
        self.gte_filters.append((column, value))
        return self

    def order(self, column, desc=False):
        self._order = (column, desc)
        return self

    def limit(self, n):
        self._limit = n
        return self

    def insert(self, rows):
        self.to_insert = rows if isinstance(rows, list) else [rows]
        return self

    def delete(self):
        self.deleting = True
        return self

    def execute(self):
        rows = self.db.setdefault(self.table, [])

        if self.to_insert is not None:
            made = []
            for row in self.to_insert:
                row = {"created_at": datetime.now(timezone.utc).isoformat(),
                       **row, "id": len(rows) + 1000}
                rows.append(row)
                made.append(row)
            return _Result(made)

        found = [r for r in rows if all(r.get(c) == v for c, v in self.filters)]
        found = [r for r in found if all(
            datetime.fromisoformat(r[c]) >= datetime.fromisoformat(v)
            for c, v in self.gte_filters)]

        if self.deleting:
            for r in found:
                rows.remove(r)
            return _Result(found)

        if self._order:
            found.sort(key=lambda r: r.get(self._order[0]) or "", reverse=self._order[1])

        return _Result(found[: self._limit] if self._limit else found)


class FakeSupabase:
    def __init__(self):
        self.db = {}

    def table(self, name):
        return _Query(self.db, name)

    def add_meal(self, user, name, kcal, when_vn, slot="Bữa trưa", mid=None):
        self.db.setdefault("meal_logs", []).append({
            "id": mid or len(self.db.get("meal_logs", [])) + 1,
            "user_key": user, "food_name": name, "meal_type": slot,
            "calories": kcal, "protein_g": 10, "fat_g": 5, "carbs_g": 40,
            "created_at": when_vn.astimezone(timezone.utc).isoformat(),
        })


def reply_with(**data):
    """Gemini gia: luon tra ve 1 JSON co dinh."""
    def ask(contents, system):
        ask.last = {"contents": contents, "system": system}
        return json.dumps(data, ensure_ascii=False)
    return ask


PHO = {"name_vi": "Phở bò", "portion_g": 500, "calories": 480,
       "protein_g": 24, "fat_g": 12, "carbs_g": 65}


# ---------------- Ngu canh ----------------

def test_ngu_canh_co_so_that_hom_nay_va_bo_qua_hom_qua():
    sb = FakeSupabase()
    sb.add_meal("u1", "Bánh mì", 360, NOW.replace(hour=7), "Bữa sáng")
    sb.add_meal("u1", "Cơm tấm", 620, NOW.replace(hour=12), "Bữa trưa")
    sb.add_meal("u1", "Pizza", 900, NOW.replace(day=16, hour=20), "Bữa tối")  # hom qua
    sb.add_meal("u2", "Của người khác", 5000, NOW.replace(hour=9))

    text = ca.build_context(sb, "u1", now=NOW, daily_goal=2000)
    assert "14:20" in text and "thứ Ba" in text
    assert "Tổng hôm nay".lower() in text.lower() or "tong hom nay" in text.lower()
    assert "980 kcal / muc tieu 2000" in text         # 360 + 620, khong tinh Pizza
    assert "con lai 1020" in text
    assert "Bánh mì" in text and "Cơm tấm" in text
    assert "Pizza" not in text and "Của người khác" not in text
    assert "trung binh 900 kcal/ngay" in text           # chi co ngay 16/11


def test_ngu_canh_dung_gio_viet_nam_khong_bi_lech_ngay():
    sb = FakeSupabase()
    # 01:00 sang 17/11 gio VN = 18:00 UTC ngay 16/11 -> van la HOM NAY
    sb.add_meal("u1", "Mì khuya", 400, NOW.replace(hour=1), "Ăn phụ")
    assert "Mì khuya" in ca.build_context(sb, "u1", now=NOW)


def test_chua_ghi_gi_hom_nay():
    text = ca.build_context(FakeSupabase(), "u1", now=NOW)
    assert "CHUA ghi bua nao" in text


def test_loi_doc_nhat_ky_khong_lam_hong_chat():
    class Broken:
        def table(self, _):
            raise RuntimeError("mat ket noi")
    assert ca.build_context(Broken(), "u1", now=NOW) == ""


# ---------------- Chat thuong ----------------

def test_chat_thuong_khong_ghi_gi():
    sb = FakeSupabase()
    ask = reply_with(intent="chat", reply="Hôm nay bạn còn 1020 kcal.", meals=[])
    result, error = ca.handle_message(sb, "u1", "hôm nay tôi ăn bao nhiêu rồi?", [], ask, now=NOW)
    assert error is None
    assert result["intent"] == "chat" and result["pending"] is None
    assert "1020" in result["reply"]
    assert not sb.db.get("meal_logs")
    assert "NGU CANH" in ask.last["system"]             # ngu canh duoc gui cho AI


def test_cau_hoi_gia_dinh_khong_bi_ghi_du_AI_tra_nham_log_meal_rong():
    ask = reply_with(intent="log_meal", reply="ok", meals=[])
    result, _ = ca.handle_message(FakeSupabase(), "u1", "ăn phở có béo không", [], ask, now=NOW)
    assert result["pending"] is None and result["intent"] == "chat"


def test_gemini_khong_tra_json_thi_dung_lam_cau_tra_loi():
    result, error = ca.handle_message(
        FakeSupabase(), "u1", "xin chào", [], lambda c, s: "Chào bạn nhé!", now=NOW)
    assert error is None and result["reply"] == "Chào bạn nhé!" and result["pending"] is None


def test_gemini_loi_thi_bao_loi():
    _, error = ca.handle_message(FakeSupabase(), "u1", "xin chào", [], lambda c, s: None, now=NOW)
    assert error
    assert ca.handle_message(FakeSupabase(), "u1", "  ", [], lambda c, s: "{}", now=NOW)[1]


def test_bo_cau_user_trung_lap_trong_history():
    ask = reply_with(intent="chat", reply="ok")
    history = [{"role": "assistant", "text": "Chào"}, {"role": "user", "text": "câu hỏi"}]
    ca.handle_message(FakeSupabase(), "u1", "câu hỏi", history, ask, now=NOW)
    user_turns = [c for c in ask.last["contents"] if c["role"] == "user"]
    assert len(user_turns) == 1


# ---------------- Ghi mon ----------------

def test_ghi_mon_chi_de_xuat_khong_ghi_cho_den_khi_xac_nhan():
    sb = FakeSupabase()
    ask = reply_with(intent="log_meal", reply="ok", meal_type="Bữa trưa", meals=[PHO])
    result, _ = ca.handle_message(sb, "u1", "trưa nay tôi ăn 1 tô phở bò", [], ask, now=NOW)

    assert result["intent"] == "log_meal"
    pending = result["pending"]
    assert pending["type"] == "log_meal" and pending["meal_type"] == "Bữa trưa"
    assert pending["total"]["calories"] == 480
    assert "Phở bò" in result["reply"] and "xác nhận" in result["reply"]
    assert not sb.db.get("meal_logs")                     # CHUA ghi

    saved, error, status = ca.confirm_log(sb, "u1", pending["meal_type"], pending["items"], now=NOW)
    assert error is None and status == 200
    row = sb.db["meal_logs"][0]
    assert row["user_key"] == "u1" and row["food_name"] == "Phở bò"
    assert row["meal_type"] == "Bữa trưa" and row["calories"] == 480


def test_ten_bua_la_hoac_thieu_thi_theo_gio_hien_tai():
    ask = reply_with(intent="log_meal", reply="ok", meal_type="bữa gì đó", meals=[PHO])
    result, _ = ca.handle_message(FakeSupabase(), "u1", "ăn phở", [], ask, now=NOW)
    assert result["pending"]["meal_type"] == "Ăn phụ"        # 14:20 -> an phu
    morning = NOW.replace(hour=8)
    result, _ = ca.handle_message(FakeSupabase(), "u1", "ăn phở", [], ask, now=morning)
    assert result["pending"]["meal_type"] == "Bữa sáng"


def test_mon_thieu_so_lieu_bi_bo_khong_doan():
    meals = ca.clean_meals([
        PHO, {"name_vi": "Thiếu kcal", "portion_g": 100},
        {"name_vi": "Thiếu gram", "calories": 100}, {"name_vi": "x", "portion_g": 1, "calories": 1},
        "rac",
    ])
    assert [m["name_vi"] for m in meals] == ["Phở bò"]
    assert ca.confirm_log(FakeSupabase(), "u1", "Bữa trưa", [{"name_vi": "x"}])[2] == 400


def test_xac_nhan_nhieu_mon_va_gioi_han_so_mon():
    sb = FakeSupabase()
    items = [{**PHO, "name_vi": f"Món {i}"} for i in range(20)]
    saved, _, _ = ca.confirm_log(sb, "u1", "Bữa tối", items, now=NOW)
    assert len(sb.db["meal_logs"]) == ca.MAX_MEALS == saved["saved"]


# ---------------- Xoa mon ----------------

def test_xoa_mon_vua_ghi_phai_xac_nhan_va_chi_xoa_mon_cua_minh():
    sb = FakeSupabase()
    sb.add_meal("u1", "Cơm tấm", 620, NOW.replace(hour=12), mid=1)
    sb.add_meal("u1", "Phở nhầm", 480, NOW.replace(hour=13), mid=2)       # moi nhat
    sb.add_meal("u2", "Của người khác", 700, NOW.replace(hour=14), mid=3)

    ask = reply_with(intent="delete_last", reply="ok")
    result, _ = ca.handle_message(sb, "u1", "ghi nhầm rồi, xóa đi", [], ask, now=NOW)
    pending = result["pending"]
    assert pending["type"] == "delete_meal" and pending["meal"]["id"] == 2
    assert "Phở nhầm" in result["reply"]
    assert len(sb.db["meal_logs"]) == 3                                     # chua xoa

    assert ca.confirm_delete(sb, "u2", 2)[2] == 404                         # khong xoa duoc cua nguoi khac
    assert len(sb.db["meal_logs"]) == 3
    assert ca.confirm_delete(sb, "u1", 2)[2] == 200
    assert [m["food_name"] for m in sb.db["meal_logs"]] == ["Cơm tấm", "Của người khác"]
    assert ca.confirm_delete(sb, "u1", "abc")[2] == 400


def test_xoa_khi_nhat_ky_trong():
    ask = reply_with(intent="delete_last", reply="ok")
    result, _ = ca.handle_message(FakeSupabase(), "u1", "xóa món vừa ghi", [], ask, now=NOW)
    assert result["pending"] is None and "chưa thấy" in result["reply"]


# ---------------- API ----------------

def make_client(uid="u1", ask=None):
    app = Flask(__name__)
    sb = FakeSupabase()
    chat_agent_api.init(app, sb, lambda: uid,
                        ask or reply_with(intent="log_meal", reply="ok",
                                          meal_type="Bữa trưa", meals=[PHO]),
                        lambda user, scan: ["Ho so: test"], lambda user: 1800)
    return app.test_client(), sb


def test_api_agent_roi_confirm():
    client, sb = make_client()
    res = client.post("/api/chat/agent", json={"message": "trưa nay ăn phở bò", "history": []})
    assert res.status_code == 200 and res.json["pending"]["type"] == "log_meal"
    assert not sb.db.get("meal_logs")

    res = client.post("/api/chat/agent/confirm", json={
        "type": "log_meal", "meal_type": "Bữa trưa", "items": res.json["pending"]["items"]})
    assert res.status_code == 200 and len(sb.db["meal_logs"]) == 1


def test_api_dau_vao_sai_va_chua_dang_nhap():
    client, _ = make_client()
    assert client.post("/api/chat/agent", json={"message": ""}).status_code == 400
    assert client.post("/api/chat/agent/confirm", json={"type": "xoa_tat_ca"}).status_code == 400
    assert client.post("/api/chat/agent/confirm", json={"type": "log_meal", "items": []}).status_code == 400

    anonymous, _ = make_client(uid=None)
<<<<<<< HEAD
    assert anonymous.post("/api/chat/agent", json={"message": "hi"}).status_code == 401
=======
    assert anonymous.post("/api/chat/agent", json={"message": "hi"}).status_code == 401


# ---------------- Toi uu: doc song song / khong truy van thua ----------------

def test_nhat_ky_doc_san_thi_khong_truy_van_lai():
    class Counting(FakeSupabase):
        queries = 0

        def table(self, name):
            Counting.queries += 1
            return super().table(name)

    sb = Counting()
    sb.add_meal("u1", "Cơm tấm", 620, NOW.replace(hour=12))

    meals = ca.fetch_meals(sb, "u1", now=NOW)
    assert [m["food_name"] for m in meals] == ["Cơm tấm"] and Counting.queries == 1

    text = ca.build_context(sb, "u1", now=NOW, daily_goal=2000, meals=meals)
    assert "620 kcal / muc tieu 2000" in text and Counting.queries == 1   # khong doc lai


def test_fetch_meals_loi_tra_none():
    class Broken:
        def table(self, _):
            raise RuntimeError("mat ket noi")
    assert ca.fetch_meals(Broken(), "u1", now=NOW) is None


def test_api_mot_phan_ngu_canh_loi_van_tra_loi_duoc():
    def boom(*_):
        raise RuntimeError("loi ho so")

    app = Flask(__name__)
    sb = FakeSupabase()
    ask = reply_with(intent="chat", reply="Chào bạn!", meals=[])
    chat_agent_api.init(app, sb, lambda: "u1", ask, boom, boom)
    res = app.test_client().post("/api/chat/agent", json={"message": "hi", "history": []})
    assert res.status_code == 200 and res.json["reply"] == "Chào bạn!"
    assert "CHUA ghi bua nao" in ask.last["system"]       # nhat ky van doc duoc
>>>>>>> a9402009 (chat nhanh + dang nhap Google)
