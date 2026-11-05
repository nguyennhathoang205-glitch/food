"""Kiem tra canh bao di ung / benh ly / tuong tac thuoc / OCR y te.

Chay trong thu muc backend/:
    python -m unittest test_health.py -v
    hoac: python test_health.py
"""
import unittest
import health
import active_learning

PROFILE = {
    "allergies": ["sữa", "gluten", "mè", "hải sản"],
    "conditions": ["gout", "huyết áp cao", "mỡ máu", "đau dạ dày"],
}


def warn(dish, ingredients=()):
    return [w["message"] for w in health.check_warnings(PROFILE, [dish], list(ingredients), {})]


def test_khong_bao_nham_do_bo_dau():
    # "bò" khong phai "bơ", "phở" la banh pho gao, "long" trong "thanh long",
    # "kho" trong "khoai", "me" (trai me) khong phai "mè", "cà" khong phai "cá".
    assert warn("Phở bò") == []
    assert warn("Bún bò Huế") == []
    assert warn("Thanh long") == []
    assert warn("Măng cụt") == []
    assert not any("mè" in m for m in warn("Cua rang me"))
    assert not any("hải sản" in m for m in warn("Gỏi cuốn", ["cà rốt", "bún"]))
    assert not any("huyết áp" in m for m in warn("Khoai tây chiên"))


def test_van_bat_dung():
    assert any("sữa" in m for m in warn("Sữa chua"))
    assert any("gluten" in m for m in warn("Bánh mì thịt"))
    assert any("mè" in m for m in warn("Bánh mì", ["mè"]))
    assert any("hải sản" in m for m in warn("Cua rang me"))
    assert any("huyết áp cao" in m for m in warn("Thịt kho trứng", ["nước mắm"]))
    assert any("gout" in m for m in warn("Lòng lợn"))


def test_di_ung_tu_nhap():
    profile = {"allergies": ["sầu riêng"], "conditions": []}
    msgs = [w["message"] for w in health.check_warnings(profile, ["Kem sầu riêng"], [], {})]
    assert any("sầu riêng" in m for m in msgs)


def test_drug_food_interactions():
    # Tinh nang canh bao tuong tac thuoc da TAT (khong du can cu y khoa chac chan).
    profile = {
        "allergies": [],
        "conditions": ["mỡ máu", "tiểu đường"],
        "medications": ["Atorvastatin 10mg", "Metformin 500mg", "Warfarin"],
    }
    assert health.check_drug_food_interactions(profile["medications"], "bưởi cải bó xôi bia") == []
    w = health.check_warnings(profile, ["Nước ép bưởi"], ["bưởi"], {})
    assert not any("Tương tác thuốc" in x["message"] for x in w)


def test_analyze_food_pathology_6_groups():
    profile = {
        "allergies": ["tôm"],
        "conditions": ["huyết áp cao", "gout"],
        "medications": ["Allopurinol"],
    }
    res = health.analyze_food_pathology(profile, {
        "product_name": "Lẩu hải sản chua cay",
        "ingredients": ["tôm", "mực", "ớt", "nước mắm"],
        "calories": 650,
        "protein_g": 42,
        "fat_g": 22,
        "carbs_g": 55,
    })
    assert len(res["disease_breakdown"]) == 6
    assert any("DỊ ỨNG" in w["message"] for w in res["warnings"])
    assert not any("Tương tác thuốc" in w["message"] for w in res["warnings"])


def test_scan_medical_document_samples():
    blood = health.scan_medical_document(sample_type="blood_test")
    assert blood["document_type"] == "lab_result"
    assert "tiểu đường" in blood["detected_conditions"]
    assert len(blood["lab_indicators"]) >= 4

    rx = health.scan_medical_document(sample_type="prescription")
    assert rx["document_type"] == "prescription"
    assert any("Losartan" in m for m in rx["detected_medications"])


def test_generate_weekly_meal_plan():
    profile = {
        "allergies": ["hải sản", "trứng"],
        "conditions": ["tiểu đường", "huyết áp cao"],
        "medications": ["Metformin 500mg", "Losartan 50mg"],
    }
    plan = health.generate_weekly_meal_plan(daily_goal=1800, profile=profile)
    assert len(plan["days"]) == 7
    for day in plan["days"]:
        assert 1650 <= day["total_calories"] <= 1950
        for m in day["meals"]:
            assert "trứng" not in m["name_vi"].lower()
            assert "cá" not in m["name_vi"].lower()


class HealthTestCase(unittest.TestCase):
    def test_false_positives(self):
        test_khong_bao_nham_do_bo_dau()

    def test_true_positives(self):
        test_van_bat_dung()

    def test_custom_allergy(self):
        test_di_ung_tu_nhap()

    def test_drug_interactions(self):
        test_drug_food_interactions()

    def test_pathology_6_groups(self):
        test_analyze_food_pathology_6_groups()

    def test_medical_ocr_samples(self):
        test_scan_medical_document_samples()

    def test_weekly_meal_plan(self):
        test_generate_weekly_meal_plan()

    def test_stage4_active_learning_and_weight_forecast(self):
        metrics = active_learning.get_ai_metrics({0: {"name_vi": "Cơm tấm", "name_en": "Com tam"}})
        assert len(metrics["benchmarks"]) >= 2
        assert "active_learning" in metrics
        fc = active_learning.forecast_weight_30d(
            current_weight_kg=65.0,
            daily_goal_kcal=2000.0,
            avg_consumed_kcal=1500.0,
            logged_days=5,
        )
        assert fc["trend"] == "lose"
        assert fc["projected_weight_30d_kg"] is not None and fc["projected_weight_30d_kg"] < 65.0


if __name__ == "__main__":
    unittest.main()
