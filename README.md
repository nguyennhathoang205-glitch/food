# FoodScan AI — Hệ Thống Nhận Diện Món Ăn, Phân Tích Dinh Dưỡng & Cảnh Báo Y Khoa Cá Nhân Hóa

**FoodScan AI** là ứng dụng di động & web (**Flutter + Python Flask + Dual-YOLO26 + TFLite On-Device + CLIP 512-dim Few-Shot + Gemini Vision + Supabase pgvector**) hỗ trợ nhận diện món ăn Việt Nam, trái cây, nhãn dinh dưỡng bao bì, mã vạch sản phẩm và phiếu xét nghiệm máu để tính toán năng lượng (Calo, Đạm, Béo, Tinh bột), chấm điểm Nutri-Score / Glycemic Load (GL), theo dõi vận động GPS kiểu Strava và cảnh báo bệnh lý nền theo thời gian thực.

---

## Tổng quan 24+ Tính năng Chính

### Giai đoạn 1 — Core AI Food Scanner (Server + Offline TFLite) & Phân tích 6 Bệnh lý Lâm sàng
1. **Nhận diện đa mô hình (Dual YOLO26 + On-Device TFLite + Gemini Vision + CLIP Few-Shot)**:
   - **YOLO26s Food Detector (`food_detector_yolo26.pt`)**: Nhận diện 68 món ăn Việt Nam phổ biến (Phở, Bún bò Huế, Cơm tấm, Bánh mì, Gỏi cuốn...) với `mAP@50 = 79.6%`.
   - **YOLO26s Fruit Detector (`fruit_detector.pt`)**: Nhận diện 20 loại trái cây nhiệt đới (Táo, Bơ, Chuối, Thanh long, Sầu riêng, Xoài, Bưởi, Dưa hấu...) với `mAP@50 = 79.5%`.
   - **On-Device Offline TFLite (`OnDeviceDetector`)**: Chạy song song cả 2 model `food_detector.tflite` (ID `0..67`) và `fruit_detector.tflite` (ID `1000..1019`) ngay trên thiết bị khi mất mạng.
   - **Gemini Vision Holistic Dish Analysis**: Phân tích toàn cảnh mâm cơm/món ăn ngoài tập train, bóc tách nguyên liệu, ước lượng khối lượng khẩu phần (`estimated_weight_g`) và tổng dinh dưỡng.
2. **Phân tích 6 nhóm bệnh lý lâm sàng (`disease_breakdown`)**:
   - Đánh giá trực quan mức độ **Phù hợp / Cần hạn chế / Nguy cơ cao** trên cả 3 chế độ quét (**Món ăn**, **Nhãn bao bì Nutrition Facts**, **Mã vạch OpenFoodFacts**) đối với 6 nhóm bệnh:
     - Tăng huyết áp & Tim mạch (Natri)
     - Bệnh Gout & Axit Uric (Nhân Purine)
     - Mỡ máu & Xơ vữa động mạch (Chất béo bão hòa)
     - Tiểu đường type 2 (Đường & Tinh bột / Tải lượng đường huyết GL)
     - Bệnh Thận mạn (Áp lực lọc Natri & Đạm)
     - Dạ dày & Tiêu hóa (Gia vị chua/cay, đồ chiên, chất kích thích)
3. **Chấm điểm Nutri-Score (A–E), Tải lượng đường huyết (GL) & Tùy chỉnh Khẩu phần kiểu Việt Nam**:
   - Quy đổi số gram sang đơn vị trực quan (`VietnamesePortionHelper`: chén cơm, lòng bàn tay đạm, nắm rau).
   - Tuỳ chỉnh cỡ tô/đĩa (`Nhỏ 70%`, `Vừa 100%`, `Lớn 130%`), chip `Ít cơm/bún (-25% Carb)`, `Bỏ nước béo/mỡ (-30% Béo)`, `Thêm đạm (+25% Đạm)` và nút **1-Chạm Tối ưu Sức khỏe (Healthy Swap)**.
   - Tùy chỉnh khẩu phần từng món riêng lẻ trên ảnh mâm cơm (`0.5x` .. `5.0x`).

### Giai đoạn 2 — Quét Nhãn Bao bì, Mã vạch Camera/Gallery, Hồ sơ Y tế AI OCR & Active Learning
4. **Quét Nhãn Dinh Dưỡng Bao Bì & Quét Ảnh Mã Vạch (`label_scanner.dart`)**:
   - Đọc bảng Nutrition Facts trên bao bì bằng Gemini Vision OCR.
   - Tra cứu mã vạch qua **Open Food Facts** hoặc **chụp/tải ảnh mã vạch trực tiếp từ Camera & Thư viện** để AI tự đọc số EAN-13/UPC và lấy dữ liệu dinh dưỡng.
5. **Quét Phiếu Xét Nghiệm Máu bằng AI OCR (`POST /api/health/scan-medical`)**:
   - Đọc ảnh phiếu xét nghiệm sinh hóa máu (Glucose, HbA1c, Cholesterol, Triglyceride, Acid Uric, Creatinine, Huyết áp...).
   - Tự động trích xuất chỉ số cao/thấp, phát hiện bệnh lý nền và **đồng bộ 1 chạm** vào Hồ sơ sức khỏe cá nhân.
6. **Ghi bữa ăn bằng ngôn ngữ tự nhiên (`SmartMealDialog` + `/api/meals/parse-text`)**:
   - Nhập câu mô tả tự nhiên (VD: *"1 tô phở bò nhiều thịt + 1 ly trà đá"*), AI tự tách từng món và tính dinh dưỡng.
7. **Học chủ động & Bảng Chỉ số Thực nghiệm AI (`FeedbackDialog` + `AiMetricsDialog` + `/api/ai/metrics`)**:
   - Người dùng góp ý sửa nhãn kèm ảnh & bounding box (`POST /api/feedback`), tự động xuất tập dữ liệu chuẩn YOLO (`feedback_data/yolo_dataset`).
   - Xem trực tiếp bảng đối chiếu `YOLOv8s Baseline` vs `YOLO26s Food` vs `YOLO26s Fruit` (`mAP@50`, `mAP@50-95`, `Precision`, `Recall`, tốc độ `ms/ảnh`) trên màn hình Thống kê.

### Giai đoạn 3 — Cố vấn Menu Quán ăn, Tủ lạnh Thông minh, Strava GPS Tracker & Nhịn ăn Gián đoạn
8. **Cố vấn Thực đơn Quán ăn (`SmartMenuAdvisorSheet` + `POST /api/menu/analyze`)**:
   - Chụp ảnh tờ Menu nhà hàng/quán ăn hoặc chọn loại quán (*Cơm văn phòng, Bún/Phở, Lẩu & Nướng*) để AI lọc ra **Top món nên gọi** và **Món nên hạn chế** khớp TDEE & bệnh lý.
9. **Gợi ý Món nấu từ Tủ lạnh (`FridgeToMealSheet` + `POST /api/fridge/suggest`)**:
   - Chụp ảnh tủ lạnh để Gemini Vision tự nhận diện nguyên liệu (hoặc chọn/nhập nguyên liệu sẵn có) → gợi ý các món Việt nấu nhanh 15 phút chuẩn dinh dưỡng.
10. **Strava Live Exercise Tracker (`ExerciseTrackerCard` + `LiveMotionTracker`)**:
    - Đo **Chạy bộ / Đi bộ / Đạp xe** bằng GPS & cảm biến bước chân thực tế (hỗ trợ Auto-Pause khi đứng yên và chế độ Giả lập Demo PC), vẽ bản đồ đường chạy, chia sẻ thẻ thành tích Strava và tự động cộng bù Calo đốt vào mục tiêu ngày.
11. **Theo dõi Nước uống & Bù nước món mặn (`WaterTrackerCard` + `SaltyMealHydrationHelper`)**:
    - Tự động đếm số món đậm vị/nước lèo đã ăn trong ngày và nhắc uống bù `+250 ml/món`.
12. **Nhịp Sinh Học & Nhịn Ăn Gián Đoạn (`CircadianTimingCard`)**:
    - Đồng hồ theo dõi chu kỳ `16:8`, `14:10`, `12:12` và cảnh báo khi phát hiện bữa ăn khuya sau `20:30`.

### Giai đoạn 4 — Cộng đồng Dạy AI (CLIP Few-Shot), Mâm cơm Gia đình, Sổ tay Công thức & Chat Agent
13. **Cộng đồng Dạy AI Món Mới (`TeachFoodScreen` + `community_foods.py`)**:
    - Người dùng chụp 1–5 ảnh một món đặc sản mới → trích xuất vector **CLIP 512 chiều (`clip-ViT-B-32`)** lưu vào Supabase `pgvector`. Nhận diện ngay ở lần quét sau trên cả màn thử nghiệm lẫn màn Quét món chính (`/detect`) mà không cần train lại YOLO.
14. **Chia Khẩu phần Mâm Cơm Gia Đình (`FamilyMealScreen` + `family_meal.py`)**:
    - Chụp ảnh mâm cơm chung, AI tách từng món trên mâm và tự động chia Calo/Macro cho từng thành viên theo hệ số khẩu phần và món mỗi người có ăn/không ăn.
15. **Sổ tay Công thức Cộng đồng (`RecipesScreen` + `recipes.py`)**:
    - Đăng công thức nấu ăn, tự động tính tổng dinh dưỡng từ nguyên liệu, gắn nhãn cảnh báo số liệu, thả tim, ghi nhật ký 1 chạm và tự động dạy luôn cho CLIP AI nếu bài đăng kèm ảnh.
16. **Trợ lý AI Chat Agent (`FloatingHelpButton` / `ChatAssistantSheet` + `chat_agent.py`)**:
    - Trò chuyện dinh dưỡng theo ngữ cảnh món vừa quét & nhật ký thực tế trong ngày, hỗ trợ đề xuất ghi/xóa món trong nhật ký có bước xác nhận an toàn.

### Giai đoạn 5 — Nhật ký Thumbnail, Thực đơn 7 Ngày, So sánh Món, Dự báo Cân nặng 30 Ngày & Báo cáo CSV
17. **Nhật ký Ăn uống Kèm Ảnh Thumbnail & Tìm kiếm Lịch sử (`JournalScreen`)**:
    - Tự động nén và lưu ảnh chụp món ăn/nhãn/mã vạch thành thumbnail nhẹ (`MealEntry.thumb`), hỗ trợ xem theo lịch từng ngày, tìm kiếm lịch sử món đã ăn, và sao chép nhanh bữa ăn từ hôm qua.
18. **Lập Thực đơn 7 Ngày AI & Danh sách Đi chợ (`WeeklyMealPlanSheet` + `_SmartGroceryListDialog`)**:
    - Lên thực đơn Sáng – Trưa – Tối – Phụ từ Thứ 2 đến Chủ Nhật khớp TDEE & bệnh lý, kèm danh sách đi chợ 7 ngày phân nhóm nguyên liệu.
19. **So sánh 2 Món ăn Trực diện (`FoodComparisonDialog` + `/api/foods/compare`)**, **Dự báo Biến thiên Cân nặng 30 Ngày (`_WeightTrajectoryCard`)**, **4 Huy hiệu Sức khỏe Tuần (`_WeeklyBadgesCard`)**, và **Báo cáo Lâm sàng 7 Ngày & Xuất Excel `.CSV` (`WeeklyClinicalReportDialog` + `CsvExportDialog`)**.

---

## Hướng dẫn Cài đặt & Chạy Dự án

### 1. Khởi tạo Cơ sở dữ liệu Supabase
Chạy toàn bộ file [backend/supabase_stage3_migration.sql](file:///c:/Users/Administrator/Desktop/food-scan-app%20(2)/food-scan-app/backend/supabase_stage3_migration.sql) trong **Supabase SQL Editor** để tạo bảng và hàm vector RPC `match_community_foods`.

### 2. Backend (Flask + YOLO26 + CLIP + Gemini + Supabase)
```bash
cd backend
python app.py
```
Chạy toàn bộ kiểm thử Backend:
```bash
cd backend
python -m unittest discover -s . -p "test_*.py" -v
```

### 3. Mobile / Web (Flutter)
```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```
