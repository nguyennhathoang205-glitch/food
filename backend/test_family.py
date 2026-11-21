"""Test tinh nang Mam com gia dinh - khong can mang, Gemini hay Supabase that.

Chay trong thu muc backend/:
    python -m pytest test_family.py -q
"""
import io
import json

from PIL import Image

import family_meal as fm
from test_recipes import FakeSupabase


def jpeg_bytes():
    buffer = io.BytesIO()
    Image.new("RGB", (200, 100), (180, 120, 60)).save(buffer, format="JPEG")
    return buffer.getvalue()


DISHES = [
    {"name_vi": "Cơm trắng", "grams": 600, "calories": 780,
     "protein_g": 16, "fat_g": 2, "carbs_g": 170},
    {"name_vi": "Cá kho", "grams": 300, "calories": 450,
     "protein_g": 50, "fat_g": 25, "carbs_g": 6},
    {"name_vi": "Canh rau", "grams": 400, "calories": 80,
     "protein_g": 4, "fat_g": 2, "carbs_g": 12},
]


def members(*specs):
    return [{"name": n, "weight": w, "skip": s} for n, w, s in specs]


# ---------------- Chia phan ----------------

def test_chia_deu_khi_he_so_bang_nhau():
    result, error = fm.compute(DISHES, members(("Ba", 1, []), ("Mẹ", 1, [])))
    assert error is None
    for m in result["members"]:
        assert m["calories"] == (780 + 450 + 80) / 2


def test_he_so_phan_chia_theo_ti_le():
    # Be an 0.5, nguoi lon 1 -> be 1/3, nguoi lon 2/3
    result, _ = fm.compute(DISHES, members(("Be", 0.5, []), ("Ba", 1, [])))
    be, ba = result["members"]
    assert round(be["calories"] / (be["calories"] + ba["calories"]), 3) == 0.333
    assert round(ba["grams"], 1) == round(1300 * 2 / 3, 1)


def test_nguoi_khong_an_mon_thi_mon_do_chia_cho_nguoi_con_lai():
    # Me khong an ca (mon index 1): ca kho chia het cho Ba
    result, _ = fm.compute(DISHES, members(("Ba", 1, []), ("Mẹ", 1, [1])))
    ba, me = result["members"]
    assert [d["name_vi"] for d in me["dishes"]] == ["Cơm trắng", "Canh rau"]
    assert ba["calories"] == 450 + (780 + 80) / 2
    assert me["calories"] == (780 + 80) / 2


def test_bao_toan_tong_khong_mat_khong_them():
    group = members(("A", 1, []), ("B", 0.5, [0]), ("C", 1.5, [1, 2]), ("D", 1, []))
    result, _ = fm.compute(DISHES, group)
    eaten = sum(m["calories"] for m in result["members"])
    assert abs(eaten - result["total"]["calories"]) < 0.5
    assert result["total"]["calories"] == 780 + 450 + 80


def test_mon_ca_nha_deu_khong_an_khong_tinh_vao_ai():
    result, _ = fm.compute(DISHES, members(("Ba", 1, [2]), ("Mẹ", 1, [2])))
    assert result["dishes"][2]["uneaten"] is True
    assert result["total"]["calories"] == 780 + 450
    assert sum(m["calories"] for m in result["members"]) == 780 + 450


def test_phan_tram_muc_tieu_ngay():
    group = [{"name": "Ba", "weight": 1, "skip": [], "goal_kcal": 2000}]
    result, _ = fm.compute(DISHES, group)
    assert result["members"][0]["goal_percent"] == round(1310 / 2000 * 100)
    group[0]["goal_kcal"] = None
    assert fm.compute(DISHES, group)[0]["members"][0]["goal_percent"] is None


def test_mon_them_bang_tay_thieu_dam_beo_bot_thi_danh_dau():
    manual = DISHES + [{"name_vi": "Trái cây", "grams": 200, "calories": 90}]
    result, _ = fm.compute(manual, members(("Ba", 1, [])))
    assert result["macros_complete"] is False
    assert fm.compute(DISHES, members(("Ba", 1, [])))[0]["macros_complete"] is True


# ---------------- Kiem tra dau vao ----------------

def test_dau_vao_khong_hop_le():
    assert fm.compute([], members(("Ba", 1, [])))[1]
    assert fm.compute(DISHES, [])[1]
    assert fm.compute(DISHES, members(("Ba", 0, [])))[1]            # he so 0
    assert fm.compute(DISHES, members(("Ba", 9, [])))[1]            # he so qua lon
    assert fm.compute(DISHES, members(*[(f"N{i}", 1, []) for i in range(9)]))[1]


def test_mon_thieu_khoi_luong_hoac_kcal_bi_bo_khong_doan():
    dishes, _ = fm.clean_dishes([
        {"name_vi": "Cá", "estimated_weight_g": 200, "calories": 300},
        {"name_vi": "Thiếu kcal", "estimated_weight_g": 100},
        {"name_vi": "Thiếu gram", "calories": 100},
        {"name_vi": "x", "estimated_weight_g": 100, "calories": 100},    # ten qua ngan
        "khong phai dict",
    ])
    assert [d["name_vi"] for d in dishes] == ["Cá"]


def test_chi_so_mon_khong_an_ngoai_pham_vi_bi_bo():
    group, _ = fm.clean_members([{"weight": 1, "skip": [0, 99, "x", -1]}], 3)
    assert group[0]["skip"] == {0}


# ---------------- Gemini ----------------

def test_phan_tich_anh_thanh_cong():
    reply = json.dumps({"dishes": [
        {"name_vi": "Cơm", "estimated_weight_g": 400, "calories": 520,
         "protein_g": 10, "fat_g": 1, "carbs_g": 115},
    ]})
    dishes, error = fm.analyze(jpeg_bytes(), lambda img, prompt: reply)
    assert error is None and dishes[0]["name_vi"] == "Cơm"


def test_gemini_boc_json_trong_code_fence_van_doc_duoc():
    reply = '```json\n{"dishes": [{"name_vi": "Cơm", "estimated_weight_g": 100, "calories": 130}]}\n```'
    dishes, error = fm.analyze(jpeg_bytes(), lambda img, prompt: reply)
    assert error is None and len(dishes) == 1


def test_gemini_loi_thi_bao_loi_ro_rang():
    assert "chưa phân tích" in fm.analyze(jpeg_bytes(), lambda i, p: None)[1]
    assert fm.analyze(jpeg_bytes(), lambda i, p: "khong phai json")[1]
    assert "Không nhận ra" in fm.analyze(jpeg_bytes(), lambda i, p: '{"dishes": []}')[1]
    assert fm.analyze(b"khong phai anh", lambda i, p: "{}")[1] == "Ảnh không hợp lệ."


def test_anh_gui_cho_gemini_la_jpeg():
    seen = {}

    def ask(img, prompt):
        seen["img"] = img
        return '{"dishes": []}'

    buffer = io.BytesIO()
    Image.new("RGB", (50, 50)).save(buffer, format="PNG")
    fm.analyze(buffer.getvalue(), ask)
    assert seen["img"][:2] == b"\xff\xd8"          # dau file JPEG


# ---------------- Ghi nhat ky ----------------

def test_ghi_phan_cua_toi_moi_mon_mot_dong():
    sb = FakeSupabase()
    group = members(("Tôi", 1, []), ("Mẹ", 1, [1]))
    result, error, status = fm.log_member(sb, "u1", "Bữa tối", DISHES, group, 0)
    assert error is None and status == 200

    rows = sb.db["meal_logs"]
    assert [r["food_name"] for r in rows] == ["Cơm trắng", "Cá kho", "Canh rau"]
    assert all(r["user_key"] == "u1" and r["meal_type"] == "Bữa tối" for r in rows)
    assert rows[0]["calories"] == 390.0            # 1/2 com
    assert rows[1]["calories"] == 450.0            # Me khong an ca -> toi an het
    assert rows[1]["portion_g"] == 300
    assert result["calories"] == 390 + 450 + 40


def test_ghi_nhat_ky_dau_vao_sai():
    sb = FakeSupabase()
    group = members(("Tôi", 1, [0, 1, 2]))
    assert fm.log_member(sb, "u1", "", DISHES, group, 0)[2] == 400
    assert fm.log_member(sb, "u1", "Bữa tối", DISHES, group, 0)[2] == 400   # khong an gi
    assert fm.log_member(sb, "u1", "Bữa tối", DISHES, members(("A", 1, [])), 5)[2] == 400
    assert not sb.db.get("meal_logs")