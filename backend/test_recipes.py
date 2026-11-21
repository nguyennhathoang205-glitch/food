"""Test tinh nang cong thuc cong dong - khong can mang hay Supabase that.

Chay trong thu muc backend/:
    python -m pytest test_recipes.py -q
"""
from PIL import Image

import recipes as rc


# ---------------- Supabase gia (du cho recipes + meal_logs) ----------------

class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters, self.to_insert, self._limit = [], None, None
        self.deleting = False

    def select(self, *_):
        return self

    def order(self, *_, **__):
        return self

    def limit(self, n):
        self._limit = n
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
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
                row = {**row, "id": row.get("id") or len(rows) + 1}
                rows.append(row)
                made.append(row)
            return _Result(made)

        found = [r for r in rows if all(r.get(c) == v for c, v in self.filters)]

        if self.deleting:
            for r in found:
                rows.remove(r)
            return _Result(found)

        return _Result(found[: self._limit] if self._limit else found)


class FakeSupabase:
    def __init__(self):
        self.db = {}

    def table(self, name):
        return _Query(self.db, name)


def fake_embedder(images):
    return [[1.0] + [0.0] * 511 for _ in images]


def img():
    return Image.new("RGB", (640, 480), (200, 100, 50))


COM_GA = {
    "title": "Cơm gà luộc",
    "servings": 2,
    "ingredients": [
        {"name": "Cơm trắng", "grams": 300},
        {"name": "ức gà luộc", "grams": 200},
        {"name": "Dưa leo", "grams": 100},
    ],
    "steps": ["Luộc gà", "", "Bày ra đĩa"],
}


# ---------------- Test ----------------

def test_tinh_dinh_duong_dung_so():
    result, error = rc.preview(COM_GA)
    assert error is None and result["ok"]

    # com 300g*1.30 + uc ga 200g*1.20 + dua leo 100g*0.15
    assert result["total"]["kcal"] == round(390 + 240 + 15)
    assert result["per_serving"]["kcal"] == round((390 + 240 + 15) / 2)
    assert result["total_grams"] == 600
    assert result["grams_per_serving"] == 300


def test_nhan_tinh_tu_so_lieu_va_kem_con_so():
    result, _ = rc.preview(COM_GA)
    # 1 phan: ~323 kcal, dam ~25.8g, beo ~2.7g, bot ~44g
    labels = result["labels"]
    assert any(l.startswith("Giàu đạm") and "g/phần" in l for l in labels)
    assert any(l.startswith("Ít béo") for l in labels)
    assert any(l.startswith("Ít calo") for l in labels)
    assert not any("tinh bột" in l for l in labels)     # 44g: khong it, khong nhieu


def test_khong_bao_gio_gan_nhan_an_toan():
    for payload in (COM_GA, {
        "servings": 1,
        "ingredients": [{"name": "Thịt ba chỉ", "grams": 400}],
    }):
        result, _ = rc.preview(payload)
        text = " ".join(result["labels"]).lower()
        assert "an toàn" not in text and "tốt cho" not in text


def test_mon_nhieu_beo_bi_gan_nhan_nhieu_beo():
    result, _ = rc.preview({
        "servings": 1,
        "ingredients": [{"name": "Thịt ba chỉ", "grams": 300}],
    })
    assert any(l.startswith("Nhiều béo") for l in result["labels"])
    assert any(l.startswith("Năng lượng cao") for l in result["labels"])


def test_nguyen_lieu_la_thi_khong_doan():
    payload = {"servings": 1, "ingredients": [
        {"name": "Cơm trắng", "grams": 200}, {"name": "Rau má", "grams": 50},
    ]}
    result, _ = rc.preview(payload)
    assert result["ok"] is False and result["unknown"] == ["Rau má"]
    assert result["labels"] == []

    # Co nhap so cua nguoi dung thi tinh duoc
    payload["ingredients"][1].update(kcal_per_100g=20, protein_per_100g=2,
                                     fat_per_100g=0.3, carbs_per_100g=3)
    result, _ = rc.preview(payload)
    assert result["ok"] and result["macros_complete"]


def test_nhap_thieu_dam_beo_bot_thi_khong_gan_nhan_dua_tren_chung():
    result, _ = rc.preview({"servings": 1, "ingredients": [
        {"name": "Món tự chế", "grams": 100, "kcal_per_100g": 100},
    ]})
    assert result["ok"] and result["macros_complete"] is False
    assert all("đạm" not in l and "béo" not in l and "tinh bột" not in l
               for l in result["labels"])


def test_che_bien_doi_han_nang_luong_thi_phai_tu_nhap():
    assert rc.lookup_reference("tôm khô") is None
    assert rc.lookup_reference("cá chiên giòn") is None
    assert rc.lookup_reference("tôm")[0] == 85


def test_khop_cum_tu_dai_nhat():
    assert rc.lookup_reference("thịt heo nạc")[0] == 143    # khong phai "thịt heo"
    assert rc.lookup_reference("Cá thu")[0] == 205           # khong phai "cá"
    assert rc.lookup_reference("dầu hào") is None            # khong nham dau an


def test_dau_vao_khong_hop_le():
    assert rc.preview({"servings": 1, "ingredients": []})[1]
    assert rc.preview({"servings": 0, "ingredients": COM_GA["ingredients"]})[1]
    assert rc.preview({"servings": 1, "ingredients": [
        {"name": "Cơm", "grams": 0}]})[1]
    assert rc.preview({"servings": 1, "ingredients": [
        {"name": "x", "grams": 10}]})[1]


def test_dang_cong_thuc_roi_xem_va_tha_tim():
    sb = FakeSupabase()
    result, error, status = rc.create_recipe(
        sb, "u1", "Quang", COM_GA, [img()], embedder=fake_embedder)
    assert error is None and status == 200
    assert result["ai_learned"] is True       # co anh -> AI hoc mon nay
    rid = result["recipe_id"]

    # cac buoc rong bi bo
    assert sb.db["recipes"][0]["steps"] == ["Luộc gà", "Bày ra đĩa"]
    assert sb.db["recipes"][0]["thumb"]       # co anh thu nho
    assert sb.db["community_foods"][0]["name_vi"] == "Cơm gà luộc"

    assert rc.toggle_like(sb, "u2", rid) == (True, 1)
    assert rc.toggle_like(sb, "u3", rid) == (True, 2)
    assert rc.toggle_like(sb, "u2", rid) == (False, 1)     # bam lan 2 = bo tim
    assert rc.toggle_like(sb, "u2", 999) is None

    detail = rc.get_recipe(sb, "u3", rid)
    assert detail["like_count"] == 1 and detail["liked_by_me"] is True
    assert detail["is_mine"] is False and len(detail["ingredients"]) == 3

    assert rc.list_recipes(sb, "u1")[0]["is_mine"] is True


def test_khong_anh_van_dang_duoc_va_khong_day_ai():
    sb = FakeSupabase()
    result, error, _ = rc.create_recipe(sb, "u1", "", COM_GA, [],
                                        embedder=fake_embedder)
    assert error is None and result["ai_learned"] is False
    assert sb.db.get("community_foods") is None


def test_loi_khi_day_ai_khong_lam_hong_viec_dang():
    sb = FakeSupabase()

    def broken(images):
        raise RuntimeError("khong tai duoc CLIP")

    result, error, _ = rc.create_recipe(sb, "u1", "", COM_GA, [img()],
                                        embedder=broken)
    assert error is None and result["ai_learned"] is False
    assert len(sb.db["recipes"]) == 1


def test_thieu_nguyen_lieu_thi_khong_luu():
    sb = FakeSupabase()
    bad = {**COM_GA, "ingredients": [{"name": "Rau má", "grams": 50}]}
    _, error, status = rc.create_recipe(sb, "u1", "", bad, [])
    assert status == 400 and "Rau má" in error
    assert not sb.db.get("recipes")


def test_an_theo_cong_thuc_ghi_vao_nhat_ky():
    sb = FakeSupabase()
    result, _, _ = rc.create_recipe(sb, "u1", "", COM_GA, [],
                                    embedder=fake_embedder)
    rid = result["recipe_id"]

    eaten, error, status = rc.eat_recipe(sb, "u2", rid, "Bữa trưa", 1.5)
    assert error is None and status == 200
    meal = sb.db["meal_logs"][0]
    assert meal["user_key"] == "u2" and meal["meal_type"] == "Bữa trưa"
    assert meal["food_name"] == "Cơm gà luộc"
    assert meal["calories"] == round(323 * 1.5, 1) or abs(meal["calories"] - 484.5) < 2
    assert meal["portion_g"] == 450                      # 300 g/phan * 1.5

    assert rc.eat_recipe(sb, "u2", rid, "", 1)[2] == 400
    assert rc.eat_recipe(sb, "u2", rid, "Bữa trưa", 0)[2] == 400
    assert rc.eat_recipe(sb, "u2", 999, "Bữa trưa", 1)[2] == 404


def test_chi_chu_cong_thuc_moi_xoa_duoc():
    sb = FakeSupabase()
    result, _, _ = rc.create_recipe(sb, "u1", "", COM_GA, [],
                                    embedder=fake_embedder)
    rid = result["recipe_id"]

    assert rc.delete_recipe(sb, "u2", rid) is False
    assert len(sb.db["recipes"]) == 1
    assert rc.delete_recipe(sb, "u1", rid) is True
    assert not sb.db["recipes"]