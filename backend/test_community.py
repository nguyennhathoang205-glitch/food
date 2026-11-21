"""Test tinh nang cong dong day mon moi - khong can mang, Supabase hay CLIP.

Chay trong thu muc backend/:
    python -m pytest test_community.py -q

Dung Supabase gia (luu trong bo nho) va bo vector hoa gia (vector = mau trung
binh cua anh) de kiem tra LOGIC: gop anh theo mon, nguong, chong trung ten.
"""
import math

from PIL import Image

import community_foods as cf


# ---------------- Supabase gia ----------------

class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters, self.rows_to_insert, self._limit = [], None, None

    def select(self, *_):
        return self

    def order(self, *_, **__):
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
        return self

    def limit(self, n):
        self._limit = n
        return self

    def insert(self, rows):
        self.rows_to_insert = rows if isinstance(rows, list) else [rows]
        return self

    def execute(self):
        rows = self.db.setdefault(self.table, [])

        if self.rows_to_insert is not None:
            created = []
            for row in self.rows_to_insert:
                row = {**row, "id": len(rows) + 1}
                rows.append(row)
                created.append(row)
            return _Result(created)

        found = [r for r in rows if all(r.get(c) == v for c, v in self.filters)]
        return _Result(found[: self._limit] if self._limit else found)


class FakeSupabase:
    def __init__(self):
        self.db = {}

    def table(self, name):
        return _Query(self.db, name)

    def rpc(self, name, params):
        assert name == "match_community_foods"
        foods = {f["id"]: f for f in self.db.get("community_foods", [])}
        query = params["query_embedding"]
        matches = [
            {
                "food_id": img["food_id"],
                "name_vi": foods[img["food_id"]]["name_vi"],
                "similarity": sum(a * b for a, b in zip(query, img["embedding"])),
                "calories_per_100g": foods[img["food_id"]].get("calories_per_100g"),
            }
            for img in self.db.get("community_food_images", [])
        ]
        matches.sort(key=lambda m: m["similarity"], reverse=True)

        class _Rpc:
            def execute(_self):
                return _Result(matches[: params["match_count"]])

        return _Rpc()


# ---------------- Bo vector hoa gia ----------------

def color_embedder(images):
    """Vector = mau trung binh (R, G, B) da chuan hoa do dai 1."""
    vectors = []
    for image in images:
        r, g, b = image.resize((1, 1)).getpixel((0, 0))
        norm = math.sqrt(r * r + g * g + b * b) or 1.0
        vectors.append([r / norm, g / norm, b / norm])
    return vectors


def img(color):
    return Image.new("RGB", (32, 32), color)


RED, RED2, GREEN, BLUE = (220, 30, 30), (200, 45, 35), (30, 200, 40), (20, 30, 220)


# ---------------- Test ----------------

def test_day_mon_moi_roi_nhan_ra():
    sb = FakeSupabase()

    result, error = cf.teach(sb, "u1", "Bánh căn", [img(RED), img(RED2)],
                             nutrition={"calories_per_100g": "180"},
                             embedder=color_embedder)
    assert error is None
    assert result["is_new"] and result["images_added"] == 2

    cf.teach(sb, "u2", "Rau muống xào", [img(GREEN)], embedder=color_embedder)

    found = cf.recognize(sb, img((210, 35, 32)), embedder=color_embedder)
    assert found["best"]["name_vi"] == "Bánh căn"
    assert found["best"]["calories_per_100g"] == 180.0
    assert found["best"]["similarity"] > 0.99


def test_mon_chua_ai_day_thi_khong_doan_bua():
    sb = FakeSupabase()
    cf.teach(sb, "u1", "Bánh căn", [img(RED)], embedder=color_embedder)

    found = cf.recognize(sb, img(BLUE), embedder=color_embedder)
    assert found["best"] is None            # khong du giong -> tu choi
    assert found["candidates"]              # nhung van tra ve ung vien de tham khao


def test_trung_ten_thi_gop_vao_mot_mon():
    sb = FakeSupabase()
    cf.teach(sb, "u1", "Bánh căn", [img(RED)], embedder=color_embedder)
    again, _ = cf.teach(sb, "u2", "  bánh   CĂN ", [img(RED2)], embedder=color_embedder)

    assert again["is_new"] is False
    assert len(sb.db["community_foods"]) == 1
    assert len(sb.db["community_food_images"]) == 2

    stats = cf.list_foods(sb, "u2")
    assert stats["total_foods"] == 1 and stats["total_images"] == 2
    assert stats["my_images"] == 1 and stats["my_foods"] == 0


def test_dau_vao_khong_hop_le():
    sb = FakeSupabase()
    assert cf.teach(sb, "u1", "a", [img(RED)], embedder=color_embedder)[1]
    assert cf.teach(sb, "u1", "Bánh căn", [None], embedder=color_embedder)[1]
    assert cf.open_image(b"khong phai anh") is None

    # Qua 5 anh thi chi nhan 5
    result, _ = cf.teach(sb, "u1", "Bánh căn", [img(RED)] * 8, embedder=color_embedder)
    assert result["images_added"] == cf.MAX_IMAGES_PER_TEACH


def test_hai_mon_gan_giong_nhau_thi_khong_chac_chan():
    matches = [
        {"food_id": 1, "name_vi": "Bún bò", "similarity": 0.90},
        {"food_id": 2, "name_vi": "Bún riêu", "similarity": 0.895},
    ]
    ranked = cf.rank_foods(matches, threshold=0.82)
    assert ranked["best"] is None                     # chenh lech < MIN_MARGIN
    assert ranked["candidates"][0]["name_vi"] == "Bún bò"


def test_diem_mon_la_trung_binh_2_anh_giong_nhat():
    matches = [
        {"food_id": 1, "name_vi": "A", "similarity": 0.95},
        {"food_id": 1, "name_vi": "A", "similarity": 0.85},
        {"food_id": 1, "name_vi": "A", "similarity": 0.10},
    ]
    assert cf.rank_foods(matches, threshold=0.5)["best"]["similarity"] == 0.9