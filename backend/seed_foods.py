"""
Insert 68 mon an (tuong ung 68 class YOLO) vao bang 'foods' tren Supabase,
kem dinh duong UOC TINH (tham khao nhanh, chua phai so lieu chinh xac tuyet doi -
neu can do chinh xac cao cho bao cao/luan van, nen doi chieu lai voi bang thanh phan
dinh duong Viet Nam chinh thuc, vd: Vien Dinh duong Quoc gia).

Chay trong thu muc backend/ (da active venv, da co .env voi SUPABASE_URL/KEY):
    python seed_foods.py
"""
import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")
supabase = create_client(SUPABASE_URL or "", SUPABASE_KEY or "")

# id = class_id (0-67) tu YOLO, khop voi thu tu trong data.yaml
# calories/protein/fat/carbs/fiber: uoc tinh tren 100g phan an duoc
FOODS = [
    dict(id=0,  name_en="banh_canh",              name_vi="Bánh canh",              category="món chính", calories_per_100g=110, protein_g=6,  fat_g=3,  carbs_g=15, fiber_g=1),
    dict(id=1,  name_en="banh_chung",              name_vi="Bánh chưng",             category="món chính", calories_per_100g=200, protein_g=6,  fat_g=8,  carbs_g=27, fiber_g=1),
    dict(id=2,  name_en="banh_cuon",               name_vi="Bánh cuốn",              category="món chính", calories_per_100g=140, protein_g=6,  fat_g=4,  carbs_g=20, fiber_g=1),
    dict(id=3,  name_en="cha_trung",               name_vi="Chả trứng",              category="món chính", calories_per_100g=220, protein_g=14, fat_g=16, carbs_g=3,  fiber_g=0),
    dict(id=4,  name_en="banh_mi_heo_quay",        name_vi="Bánh mì heo quay",       category="ăn vặt",    calories_per_100g=300, protein_g=12, fat_g=14, carbs_g=32, fiber_g=2),
    dict(id=5,  name_en="banh_da",                 name_vi="Bánh đa",                category="món chính", calories_per_100g=130, protein_g=3,  fat_g=1,  carbs_g=27, fiber_g=1),
    dict(id=6,  name_en="banh_trang_tron",         name_vi="Bánh tráng trộn",        category="ăn vặt",    calories_per_100g=180, protein_g=5,  fat_g=8,  carbs_g=22, fiber_g=2),
    dict(id=7,  name_en="banh_xeo_mien_trung",     name_vi="Bánh xèo miền Trung",    category="món chính", calories_per_100g=215, protein_g=7,  fat_g=13, carbs_g=18, fiber_g=1),
    dict(id=8,  name_en="bo_kho_chay",             name_vi="Bò kho chay",            category="món chính", calories_per_100g=90,  protein_g=5,  fat_g=4,  carbs_g=8,  fiber_g=2),
    dict(id=9,  name_en="bo_la_lot",               name_vi="Bò lá lốt",              category="món chính", calories_per_100g=220, protein_g=18, fat_g=15, carbs_g=3,  fiber_g=1),
    dict(id=10, name_en="bong_cai_xanh",           name_vi="Bông cải xanh",          category="rau củ",    calories_per_100g=55,  protein_g=3,  fat_g=2,  carbs_g=7,  fiber_g=3),
    dict(id=11, name_en="banh_hoi",                name_vi="Bánh hỏi",               category="món chính", calories_per_100g=110, protein_g=2,  fat_g=0.3,carbs_g=25, fiber_g=1),
    dict(id=12, name_en="bun_bo_hue",              name_vi="Bún bò Huế",             category="món chính", calories_per_100g=140, protein_g=9,  fat_g=5,  carbs_g=16, fiber_g=1),
    dict(id=13, name_en="bun_cha_ha_noi",          name_vi="Bún chả Hà Nội",         category="món chính", calories_per_100g=200, protein_g=12, fat_g=10, carbs_g=18, fiber_g=1),
    dict(id=14, name_en="bun_dau_mam_tom",         name_vi="Bún đậu mắm tôm",        category="món chính", calories_per_100g=180, protein_g=8,  fat_g=10, carbs_g=16, fiber_g=1),
    dict(id=15, name_en="bun_mam",                 name_vi="Bún mắm",                category="món chính", calories_per_100g=150, protein_g=10, fat_g=6,  carbs_g=16, fiber_g=1),
    dict(id=16, name_en="bun_rieu_chay",           name_vi="Bún riêu chay",          category="món chính", calories_per_100g=90,  protein_g=4,  fat_g=2,  carbs_g=15, fiber_g=1),
    dict(id=17, name_en="ca_sot_ca_chua",          name_vi="Cá sốt cà chua",         category="món chính", calories_per_100g=140, protein_g=15, fat_g=6,  carbs_g=5,  fiber_g=1),
    dict(id=18, name_en="banh_mi_thit",            name_vi="Bánh mì thịt",           category="ăn vặt",    calories_per_100g=260, protein_g=10, fat_g=8,  carbs_g=35, fiber_g=2),
    dict(id=19, name_en="banh_bot_loc",            name_vi="Bánh bột lọc",           category="ăn vặt",    calories_per_100g=150, protein_g=5,  fat_g=3,  carbs_g=27, fiber_g=1),
    dict(id=20, name_en="bo_kho",                  name_vi="Bò kho",                 category="món chính", calories_per_100g=150, protein_g=14, fat_g=8,  carbs_g=6,  fiber_g=1),
    dict(id=21, name_en="canh_khoai_mo",           name_vi="Canh khoai mỡ",          category="canh",      calories_per_100g=60,  protein_g=2,  fat_g=1,  carbs_g=11, fiber_g=2),
    dict(id=22, name_en="bun_rieu_cua",            name_vi="Bún riêu cua",           category="món chính", calories_per_100g=130, protein_g=8,  fat_g=5,  carbs_g=15, fiber_g=1),
    dict(id=23, name_en="cha_gio",                 name_vi="Chả giò",                category="món xào/chiên", calories_per_100g=250, protein_g=8,  fat_g=15, carbs_g=20, fiber_g=1),
    dict(id=24, name_en="tra_chanh",               name_vi="Trà chanh",              category="đồ uống",   calories_per_100g=40,  protein_g=0,  fat_g=0,  carbs_g=10, fiber_g=0),
    dict(id=25, name_en="com_trang",               name_vi="Cơm trắng",              category="món chính", calories_per_100g=130, protein_g=2.7,fat_g=0.3,carbs_g=28, fiber_g=0.4),
    dict(id=26, name_en="com_tam",                 name_vi="Cơm tấm",                category="món chính", calories_per_100g=250, protein_g=12, fat_g=10, carbs_g=30, fiber_g=1),
    dict(id=27, name_en="banh_mi",                 name_vi="Bánh mì",                category="ăn vặt",    calories_per_100g=250, protein_g=9,  fat_g=7,  carbs_g=34, fiber_g=2),
    dict(id=28, name_en="cu_kieu",                 name_vi="Củ kiệu",                category="đồ chua",   calories_per_100g=40,  protein_g=1,  fat_g=0.2,carbs_g=9,  fiber_g=1),
    dict(id=29, name_en="cua_rang_me",             name_vi="Cua rang me",            category="món chính", calories_per_100g=180, protein_g=18, fat_g=8,  carbs_g=10, fiber_g=1),
    dict(id=30, name_en="dau_phu",                 name_vi="Đậu phụ",                category="món chính", calories_per_100g=80,  protein_g=8,  fat_g=5,  carbs_g=2,  fiber_g=1),
    dict(id=31, name_en="dua_chua",                name_vi="Dưa chua",               category="đồ chua",   calories_per_100g=20,  protein_g=1,  fat_g=0.2,carbs_g=4,  fiber_g=1),
    dict(id=32, name_en="mam_chung",               name_vi="Mắm chưng",              category="món chính", calories_per_100g=180, protein_g=14, fat_g=12, carbs_g=3,  fiber_g=0),
    dict(id=33, name_en="goi_cuon",                name_vi="Gỏi cuốn",               category="ăn vặt",    calories_per_100g=90,  protein_g=6,  fat_g=1.5,carbs_g=14, fiber_g=1),
    dict(id=34, name_en="hamburger",               name_vi="Hamburger",              category="ăn vặt",    calories_per_100g=250, protein_g=13, fat_g=12, carbs_g=24, fiber_g=1),
    dict(id=35, name_en="thit_heo_quay",           name_vi="Thịt heo quay",          category="món chính", calories_per_100g=320, protein_g=20, fat_g=26, carbs_g=0,  fiber_g=0),
    dict(id=36, name_en="hu_tieu",                 name_vi="Hủ tiếu",                category="món chính", calories_per_100g=130, protein_g=7,  fat_g=3,  carbs_g=20, fiber_g=1),
    dict(id=37, name_en="canh_kho_qua_nhoi_thit",  name_vi="Canh khổ qua nhồi thịt", category="canh",      calories_per_100g=60,  protein_g=6,  fat_g=2,  carbs_g=5,  fiber_g=2),
    dict(id=38, name_en="khoai_tay_chien",         name_vi="Khoai tây chiên",        category="món xào/chiên", calories_per_100g=310, protein_g=4,  fat_g=15, carbs_g=41, fiber_g=3),
    dict(id=39, name_en="lau_thai",                name_vi="Lẩu Thái",               category="canh",      calories_per_100g=50,  protein_g=3,  fat_g=2,  carbs_g=4,  fiber_g=1),
    dict(id=40, name_en="long_lon",                name_vi="Lòng lợn",               category="món chính", calories_per_100g=220, protein_g=15, fat_g=17, carbs_g=0,  fiber_g=0),
    dict(id=41, name_en="mi_tron",                 name_vi="Mì trộn",                category="món chính", calories_per_100g=200, protein_g=7,  fat_g=6,  carbs_g=30, fiber_g=1),
    dict(id=42, name_en="muc_trung",               name_vi="Mực trứng",              category="món chính", calories_per_100g=150, protein_g=14, fat_g=8,  carbs_g=4,  fiber_g=0),
    dict(id=43, name_en="nam_rom_kho_tieu",        name_vi="Nấm rơm kho tiêu",       category="món chính", calories_per_100g=90,  protein_g=3,  fat_g=4,  carbs_g=10, fiber_g=2),
    dict(id=44, name_en="oc",                      name_vi="Ốc",                     category="món chính", calories_per_100g=100, protein_g=15, fat_g=2,  carbs_g=5,  fiber_g=0),
    dict(id=45, name_en="ot_chuong",               name_vi="Ớt chuông",              category="rau củ",    calories_per_100g=30,  protein_g=1,  fat_g=0.3,carbs_g=6,  fiber_g=2),
    dict(id=46, name_en="pho_bo",                  name_vi="Phở bò",                 category="món chính", calories_per_100g=120, protein_g=7,  fat_g=3,  carbs_g=18, fiber_g=1),
    dict(id=47, name_en="pho_mai",                 name_vi="Phô mai",                category="khác",      calories_per_100g=350, protein_g=23, fat_g=28, carbs_g=2,  fiber_g=0),
    dict(id=48, name_en="bun_cha_ha_noi",          name_vi="Bún chả Hà Nội",         category="món chính", calories_per_100g=200, protein_g=12, fat_g=10, carbs_g=18, fiber_g=1),
    dict(id=49, name_en="banh_xeo_chay",           name_vi="Bánh xèo chay",          category="món chính", calories_per_100g=180, protein_g=4,  fat_g=10, carbs_g=18, fiber_g=2),
    dict(id=50, name_en="bo_nhung_giam",           name_vi="Bò nhúng giấm",          category="món chính", calories_per_100g=150, protein_g=18, fat_g=8,  carbs_g=1,  fiber_g=0),
    dict(id=51, name_en="ga_nuong",                name_vi="Gà nướng",               category="món chính", calories_per_100g=220, protein_g=25, fat_g=13, carbs_g=0,  fiber_g=0),
    dict(id=52, name_en="bun_bo_gio_heo",          name_vi="Bún bò giò heo",         category="món chính", calories_per_100g=160, protein_g=10, fat_g=7,  carbs_g=16, fiber_g=1),
    dict(id=53, name_en="thit_kho_trung",          name_vi="Thịt kho trứng",         category="món chính", calories_per_100g=230, protein_g=14, fat_g=17, carbs_g=4,  fiber_g=0),
    dict(id=54, name_en="suon_nuong",              name_vi="Sườn nướng",             category="món chính", calories_per_100g=280, protein_g=20, fat_g=21, carbs_g=2,  fiber_g=0),
    dict(id=55, name_en="tom_cuon_khoai_tay",      name_vi="Tôm cuốn khoai tây",     category="ăn vặt",    calories_per_100g=180, protein_g=10, fat_g=8,  carbs_g=18, fiber_g=1),
    dict(id=56, name_en="bot_chien",               name_vi="Bột chiên",              category="ăn vặt",    calories_per_100g=230, protein_g=5,  fat_g=12, carbs_g=26, fiber_g=1),
    dict(id=57, name_en="xoi",                     name_vi="Xôi",                    category="món chính", calories_per_100g=180, protein_g=3.5,fat_g=3,  carbs_g=35, fiber_g=1),
    dict(id=58, name_en="banh_canh_cua",           name_vi="Bánh canh cua",          category="món chính", calories_per_100g=130, protein_g=8,  fat_g=4,  carbs_g=17, fiber_g=1),
    dict(id=59, name_en="cao_lau",                 name_vi="Cao lầu",                category="món chính", calories_per_100g=180, protein_g=9,  fat_g=6,  carbs_g=24, fiber_g=1),
    dict(id=60, name_en="mi_quang",                name_vi="Mì Quảng",               category="món chính", calories_per_100g=190, protein_g=10, fat_g=7,  carbs_g=24, fiber_g=1),
    dict(id=61, name_en="com_chien_duong_chau",    name_vi="Cơm chiên Dương Châu",   category="món chính", calories_per_100g=200, protein_g=7,  fat_g=7,  carbs_g=28, fiber_g=1),
    dict(id=62, name_en="bun_moc",                 name_vi="Bún mọc",                category="món chính", calories_per_100g=140, protein_g=9,  fat_g=5,  carbs_g=16, fiber_g=1),
    dict(id=63, name_en="com_ga_xoi_mo",           name_vi="Cơm gà xối mỡ",          category="món chính", calories_per_100g=280, protein_g=15, fat_g=14, carbs_g=27, fiber_g=1),
    dict(id=64, name_en="chao_long",               name_vi="Cháo lòng",              category="món chính", calories_per_100g=110, protein_g=7,  fat_g=3,  carbs_g=14, fiber_g=0.5),
    dict(id=65, name_en="goi_bap_chuoi",           name_vi="Gỏi bắp chuối",          category="rau củ",    calories_per_100g=70,  protein_g=3,  fat_g=3,  carbs_g=8,  fiber_g=3),
    dict(id=66, name_en="nui_xao_bo",              name_vi="Nui xào bò",             category="món chính", calories_per_100g=200, protein_g=12, fat_g=8,  carbs_g=22, fiber_g=1),
    dict(id=67, name_en="sup_cua",                 name_vi="Súp cua",                category="canh",      calories_per_100g=70,  protein_g=7,  fat_g=3,  carbs_g=5,  fiber_g=0.5),
]


def main():
    print(f"Chuan bi insert {len(FOODS)} mon an vao bang 'foods'...")
    inserted, failed = 0, 0
    for food in FOODS:
        try:
            supabase.table("foods").upsert(food).execute()
            inserted += 1
        except Exception as e:
            print(f"  Loi voi id={food['id']} ({food['name_vi']}): {e}")
            failed += 1

    print(f"\nHoan tat: {inserted} thanh cong, {failed} loi.")
    print("Dung 'upsert' nen chay lai script nay bao nhieu lan cung an toan (khong tao trung).")


if __name__ == "__main__":
    main()