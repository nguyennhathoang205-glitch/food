# FoodScan AI — Hệ Thống Nhận Diện Món Ăn, Phân Tích Dinh Dưỡng & Cảnh Báo Y Khoa Cá Nhân Hóa

**FoodScan AI** là ứng dụng di động & web (Flutter + Python Flask + YOLO26 + Gemini Vision + Supabase) hỗ trợ nhận diện món ăn Việt Nam, trái cây, nhãn dinh dưỡng bao bì, mã vạch sản phẩm và hồ sơ y tế/đơn thuốc để tính toán năng lượng (Calo, Đạm, Béo, Tinh bột) và cảnh báo bệnh lý – tương tác thuốc theo thời gian thực.

---

## Tính năng chính

### Giai đoạn 1 — Core AI Food Scanner & Phân tích 6 Bệnh lý Lâm sàng
1. **Nhận diện đa mô hình (Dual YOLO26 + Gemini Vision)**:
   - **YOLO26 Food Detector (`food_detector_yolo26.pt`)**: Nhận diện 68 món ăn Việt Nam phổ biến (Phở, Bún bò Huế, Cơm tấm, Bánh mì, Gỏi cuốn...).
   - **YOLO26 Fruit Detector (`fruit_detector.pt`)**: Nhận diện 20 loại trái cây nhiệt đới (Táo, Bơ, Chuối, Thanh long, Sầu riêng, Xoài, Bưởi, Dưa hấu...) với mAP50 = `79.5%`.
   - **Gemini Vision Holistic Dish Analysis**: Phân tích toàn cảnh mâm cơm/món ăn ngoài tập train, bóc tách nguyên liệu, ước lượng khối lượng khẩu phần (`estimated_weight_g`) và tổng dinh dưỡng.
2. **Phân tích 6 nhóm bệnh lý lâm sàng (`disease_breakdown`)**:
   - Đánh giá trực quan mức độ **Phù hợp / Cần hạn chế / Nguy cơ cao** trên cả 3 chế độ quét (**Món ăn**, **Nhãn bao bì Nutrition Facts**, **Mã vạch OpenFoodFacts**) đối với 6 nhóm bệnh:
     - Tăng huyết áp & Tim mạch (Natri)
     - Bệnh Gout & Axit Uric (Nhân Purine)
     - Mỡ máu & Xơ vữa động mạch (Chất béo bão hòa)
     - Tiểu đường type 2 (Đường & Tinh bột)
     - Bệnh Thận mạn (Áp lực lọc Natri & Đạm)
     - Dạ dày & Tiêu hóa (Gia vị chua/cay, đồ chiên, chất kích thích)
3. **Vòng lặp Dinh dưỡng Hàng ngày (Daily Nutrition Loop)**:
   - Tính chuẩn **BMR / TDEE** theo công thức **Mifflin-St Jeor**.
   - **Gợi ý món ăn thông minh (`/api/suggest` & `SuggestionsCard`)**: Đề xuất món ăn giàu đạm phù hợp lượng Calo còn lại trong ngày và tự động lọc bỏ món gây dị ứng/nguy cơ đỏ.
   - Theo dõi lượng nước uống (`WaterTrackerCard`), chuỗi ngày ăn đúng mục tiêu (`StreakInsightCard`), và biểu đồ thống kê tuần/tháng.

### Giai đoạn 2 — Hồ sơ Y tế AI OCR, Cảnh báo Tương tác Thuốc – Thực phẩm & Smart NLP Logger
1. **Quét Đơn thuốc & Phiếu xét nghiệm máu bằng AI (`POST /api/health/scan-medical`)**:
   - Đọc ảnh đơn thuốc hoặc phiếu xét nghiệm sinh hóa máu (Glucose, HbA1c, Cholesterol, Acid Uric, Creatinine, Huyết áp...).
   - Tự động trích xuất bệnh lý nền, danh sách thuốc đang điều trị, giải thích chỉ số cao/thấp và **đồng bộ 1 chạm** vào Hồ sơ sức khỏe cá nhân.
2. **Kiểm tra Tương tác Thuốc – Thực phẩm (`check_drug_food_interactions`)**:
   - Cảnh báo lâm sàng khi món ăn vừa quét xung đột với thuốc đang dùng:
     - **Statin (Atorvastatin, Rosuvastatin...)** ↔ Bưởi, mỡ động vật
     - **Warfarin / Thuốc chống đông** ↔ Thực phẩm giàu Vitamin K (cải bó xôi, bông cải xanh...), rượu bia
     - **Thuốc huyết áp (ACEi / ARB)** ↔ Món quá mặn hoặc thực phẩm giàu Kali lượng lớn
     - **Metformin / Thuốc tiểu đường** ↔ Đồ uống có cồn, món nhiều đường đơn
     - **Kháng sinh (Tetracycline / Quinolone)** ↔ Sữa, phô mai (Canxi cản trở hấp thu), rượu bia
     - **Thuốc Gout (Allopurinol / Colchicine)** ↔ Hải sản, nội tạng, bia rượu
     - **NSAID / Corticoid / Thuốc dạ dày** ↔ Đồ chua cay, cà phê, rượu bia
3. **Ghi bữa ăn bằng ngôn ngữ tự nhiên (`SmartMealDialog` + `/api/meals/parse-text`)**:
   - Nhập câu mô tả tự nhiên (VD: *"1 tô phở bò nhiều thịt + 1 ly trà đá"*), AI tự tách từng món, cho phép tăng/giảm khẩu phần từng món trước khi lưu vào nhật ký.
4. **Học chủ động (Active Learning Feedback)**:
   - Người dùng góp ý sửa nhãn khi AI nhận diện chưa chính xác (`POST /api/feedback`), lưu mẫu về kho dữ liệu để tái huấn luyện mô hình.

### Giai đoạn 3 — Đồng bộ Đám mây (Supabase Write-Through), Chỉnh sửa Khẩu phần Trực tiếp trên Mâm cơm & Thực đơn AI 7 Ngày
1. **Đồng bộ Đám mây Supabase + Write-Through Cache (`backend/supabase_stage3_migration.sql`)**:
   - Tự động đồng bộ tài khoản (`app_users`), hồ sơ y tế & thuốc (`health_profiles`), nhật ký nước uống (`water_logs`) và phản hồi học chủ động (`feedback_logs`) lên Supabase đồng thời duy trì cache JSON cục bộ để hoạt động mượt cả khi chập chờn mạng.
2. **Tùy chỉnh Khẩu phần Từng Món trên Ảnh Quét (`ScanScreen`)**:
   - Khi YOLO nhận diện nhiều món trên bàn ăn/mâm cơm (`detections`), người dùng có thể tăng/giảm khẩu phần từng món (`0.5x` .. `5.0x`), loại bỏ món (`0.0x`), tự động tính lại tổng Calo & Macro toàn bữa theo thời gian thực (`scaledTotal`), hoặc lưu lẻ từng món vào nhật ký.
3. **Lập Thực đơn 7 Ngày bằng AI & Báo cáo Lâm sàng Tuần (`StatisticsScreen`)**:
   - **Thực đơn 7 ngày cá nhân hóa (`POST /api/meal-plan/weekly`)**: Lên thực đơn Sáng – Trưa – Tối – Phụ chuẩn Việt Nam từ Thứ 2 đến Chủ Nhật khớp mục tiêu TDEE, tự động loại bỏ và thay thế mọi món vi phạm dị ứng, bệnh lý nền hoặc tương tác với thuốc đang dùng, hỗ trợ lưu 1 chạm vào nhật ký.
   - **Báo cáo Dinh dưỡng & Lâm sàng Tuần (`GET /api/report/weekly/<user_key>`)**: Tổng hợp 7 ngày ăn uống, lượng nước, tỷ lệ bám sát mục tiêu, cảnh báo lâm sàng và cho phép sao chép/xuất báo cáo gửi bác sĩ hoặc chuyên gia dinh dưỡng.

---

## Hướng dẫn cài đặt & Chạy dự án

### 1. Backend (Flask + YOLO + Gemini + Supabase)
```bash
cd backend
..\venv\Scripts\python.exe app.py
```
Kiểm tra unit test backend:
```bash
cd backend
..\venv\Scripts\python.exe -m unittest discover -s . -p "test_*.py" -v
```

### 2. Mobile / Web (Flutter)
```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

