import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth_http.dart' as http;

import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_session.dart';
import '../../models/models.dart';
import '../../services/offline_service.dart' show isNetworkError;
import '../../services/on_device_detector.dart';
import '../../label_scanner.dart'
    show NutritionLabelScannerView, BarcodeScannerView, buildDiseaseBreakdown;
import '../../widgets/meal_slot_picker.dart';
import '../../widgets/offline_food_picker.dart';
import '../feedback_dialog.dart';
import '../stats/statistics_screen.dart' show AiModelMetricsDialog;

// ============================================================
// SCAN
// ============================================================

class ScanScreen extends StatefulWidget {
  final Future<void> Function(MealEntry) onAddMeal;

  // Bao cho FoodScanShell biet ket qua /detect moi nhat, de FloatingHelpButton
  // co ngu canh (mon an + dinh duong vua quet) khi nguoi dung mo chat AI.
  final ValueChanged<Map<String, dynamic>>? onScanResult;

  const ScanScreen({super.key, required this.onAddMeal, this.onScanResult});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  int scanMode = 0; // 0: Mon an, 1: Nhan dinh duong, 2: Ma vach

  Future<void> _onAddFromScanner(
    String name,
    double calories,
    double protein,
    double fat,
    double carbs,
    int portionG,
  ) async {
    // Dong hop chon bua thi KHONG luu (truoc day tu luu vao 'Ăn phụ').
    final mealType = await pickMealSlot(context);
    if (mealType == null) {
      return;
    }

    await widget.onAddMeal(
      MealEntry(
        name: name,
        mealType: mealType,
        time: DateTime.now(),
        portionG: portionG,
        calories: calories,
        proteinG: protein,
        fatG: fat,
        carbsG: carbs,
      ),
    );
  }

  Widget _buildModeTab(int index, String title, IconData icon) {
    final selected = scanMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => scanMode = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? primary : const Color(0xFF7F8A85),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? primary : const Color(0xFF7F8A85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeChip(String label, double factor) {
    final selected = (portionSizeFactor - factor).abs() < 0.05;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => portionSizeFactor = factor),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? primaryLight : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? primary : const Color(0xFFE2E8F0),
              width: selected ? 1.4 : 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? primaryDark : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModifierChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? primaryDark : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Uint8List? selectedImageBytes;

  ui.Image? decodedImage;

  List<Detection> detections = [];

  TotalNutrition? totalNutrition;

  final ImagePicker picker = ImagePicker();

  bool loading = false;

  String? errorMessage;

  // Goi y mon (class id) do AI chay tren may khi mat mang.
  List<int> offlineSuggestions = [];

  // Ten mon an CHINH do Gemini Vision nhan dien tren toan bo tam anh (backend
  // tra ve trong field "main_dish"), khong gioi han trong 68 class YOLO da
  // train - vi du se ra dung "Bun thit nuong" thay vi phai chon class gan
  // giong nhat. Null neu backend chua ho tro hoac Gemini bi loi/het quota.
  String? geminiMainDish;

  // Danh sach nguyen lieu nhin thay trong anh, cung do Gemini Vision phan
  // tich - thay the cho viec dung ten box YOLO lam "thanh phan" (vi YOLO
  // hay tach 1 to/mam thanh nhieu "mon" rieng sai lech, xem comment backend).
  List<String> ingredients = [];

  // 'gemini' neu dinh duong tong lay tu uoc tinh cua Gemini (dang tin cay
  // hon vi hieu ca mon, khong bi gioi han 68 class), 'yolo' neu phai
  // fallback ve tong cong YOLO (Gemini loi/het quota).
  String nutritionSource = 'yolo';

  // So "phan an" nguoi dung chon khi them vao nhat ky - nhan voi dinh
  // duong goc (1 phan = dung nhu uoc tinh cho ca tam anh) de ra tong cuoi.
  int servings = 1;

  // Co to/dia: Nho (0.7x), Vua (1.0x), Lon/Dac biet (1.3x).
  double portionSizeFactor = 1.0;

  // Tuy chinh thuc te cua nguoi Viet: It com/bun, Bo nuoc beo/mo, Them thit/dam.
  bool modLessCarb = false;
  bool modLessFat = false;
  bool modExtraProtein = false;

  // Khoi luong tong uoc tinh (gram) cua phan an trong anh.
  int estimatedWeightG = 0;

  // Canh bao di ung / benh ly tra ve tu backend (level: red | orange).
  List<Map<String, String>> warnings = [];

  // Phan tich 6 nhom benh ly lam sang tra ve tu /detect.
  List<dynamic> diseaseBreakdown = [];

  // He so dieu chinh khau phan cho tung mon YOLO nhan dien tren mam com.
  List<double> detectionScales = [];

  bool get hasScanResult =>
      detections.isNotEmpty ||
      (geminiMainDish != null && geminiMainDish!.isNotEmpty) ||
      (totalNutrition != null && totalNutrition!.calories > 0);

  Widget _warningTile(Map<String, String> w) {
    final red = w['level'] == 'red';
    final color = red ? const Color(0xFFD32F2F) : const Color(0xFFB8860B);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            red ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              w['message'] ?? '',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // Gom canh bao: muc "Can tranh" (red) hien day du; muc "Luu y" (orange)
  // thu gon khi co tu 2 canh bao tro len de man hinh khong bi qua dai.
  Widget buildWarnings() {
    final reds = warnings.where((w) => w['level'] == 'red').toList();
    final oranges = warnings.where((w) => w['level'] != 'red').toList();

    return Column(
      children: [
        ...reds.map(_warningTile),
        if (oranges.length == 1) _warningTile(oranges.first),
        if (oranges.length > 1)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFB8860B).withValues(alpha: 0.08),
              border: Border.all(color: const Color(0xFFB8860B)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB8860B),
                ),
                title: Text(
                  'Cần lưu ý (${oranges.length})',
                  style: const TextStyle(
                    color: Color(0xFFB8860B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                children: oranges.map(_warningTile).toList(),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            'Chỉ mang tính tham khảo, không thay thế tư vấn của bác sĩ.',
            style: TextStyle(
              fontSize: 10.5,
              color: Color(0xFF94A3B8),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> pickImage(ImageSource source) async {
    final image = await picker.pickImage(source: source, imageQuality: 90);

    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();

    final codec = await ui.instantiateImageCodec(bytes);

    final frame = await codec.getNextFrame();

    setState(() {
      selectedImageBytes = bytes;

      decodedImage = frame.image;

      detections = [];

      totalNutrition = null;

      errorMessage = null;

      geminiMainDish = null;

      ingredients = [];

      nutritionSource = 'yolo';

      servings = 1;
      portionSizeFactor = 1.0;
      modLessCarb = false;
      modLessFat = false;
      modExtraProtein = false;

      warnings = [];

      diseaseBreakdown = [];
    });
  }

  Future<void> detect() async {
    if (selectedImageBytes == null) {
      return;
    }

    setState(() {
      loading = true;

      detections = [];

      errorMessage = null;

      geminiMainDish = null;

      ingredients = [];

      nutritionSource = 'yolo';

      servings = 1;
      portionSizeFactor = 1.0;
      modLessCarb = false;
      modLessFat = false;
      modExtraProtein = false;

      warnings = [];

      diseaseBreakdown = [];
    });

    try {
      final request = http.MultipartRequest(
        'POST',

        Uri.parse('${AppConfig.baseUrl}/detect'),
      );

      request.fields['user_key'] = AppSession.currentUserKey;

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',

          selectedImageBytes!,

          filename: 'photo.jpg',
        ),
      );

      final streamed = await request.send();

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception('Server ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      final List<dynamic> raw = data['detections'];

      final rawMainDish = data['main_dish'];

      final rawIngredients = data['ingredients'];

      setState(() {
        detections = raw.map((item) => Detection.fromJson(item)).toList();
        detectionScales = List<double>.filled(detections.length, 1.0);

        totalNutrition = TotalNutrition.fromJson(data['total_nutrition']);

        geminiMainDish =
            (rawMainDish is String && rawMainDish.trim().isNotEmpty)
            ? rawMainDish.trim()
            : null;

        ingredients = rawIngredients is List
            ? rawIngredients.map((e) => e.toString()).toList()
            : [];

        nutritionSource = (data['nutrition_source'] as String?) ?? 'yolo';

        final rawWarnings = data['warnings'];
        final rawBreakdown = data['disease_breakdown'];

        estimatedWeightG = (data['estimated_weight_g'] as num?)?.round() ?? 0;

        warnings = rawWarnings is List
            ? rawWarnings
                  .map<Map<String, String>>(
                    (e) => {
                      'level': e['level'].toString(),
                      'message': e['message'].toString(),
                    },
                  )
                  .toList()
            : [];

        diseaseBreakdown = rawBreakdown is List ? rawBreakdown : [];
      });

      // Gui ket qua scan nay cho FoodScanShell de lam ngu canh cho chat AI.
      widget.onScanResult?.call(data);
    } catch (e) {
      if (isNetworkError(e) &&
          selectedImageBytes != null &&
          OnDeviceDetector.isSupported) {
        try {
          final local = await OnDeviceDetector.detect(selectedImageBytes!);
          offlineSuggestions = local.map((d) => d.classId).take(3).toList();
        } catch (_) {
          offlineSuggestions = [];
        }
      }
      setState(() {
        errorMessage = isNetworkError(e)
            ? 'Không kết nối được máy chủ (mất mạng hoặc sóng yếu).'
            : 'Không nhận diện được.\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  // Dinh duong tong nhan voi so "phan an", co to/dia va cac tuy chon cach an
  // thuc te (it com, bo mo, them dam).
  TotalNutrition get scaledTotal {
    if (totalNutrition == null) {
      return TotalNutrition(calories: 0, proteinG: 0, fatG: 0, carbsG: 0);
    }

    final factor = servings.toDouble() * portionSizeFactor;
    final hasCustomScales =
        detections.isNotEmpty &&
        detectionScales.length == detections.length &&
        detectionScales.any((s) => (s - 1.0).abs() > 0.01);

    double baseC = totalNutrition!.calories * factor;
    double baseP = totalNutrition!.proteinG * factor;
    double baseF = totalNutrition!.fatG * factor;
    double baseCb = totalNutrition!.carbsG * factor;

    if (hasCustomScales) {
      baseC = 0;
      baseP = 0;
      baseF = 0;
      baseCb = 0;
      for (int i = 0; i < detections.length; i++) {
        final s = detectionScales[i] * factor;
        if (s <= 0) continue;
        baseC += (detections[i].nutrition.calories ?? 0) * s;
        baseP += (detections[i].nutrition.proteinG ?? 0) * s;
        baseF += (detections[i].nutrition.fatG ?? 0) * s;
        baseCb += (detections[i].nutrition.carbsG ?? 0) * s;
      }
    }

    final finalP = baseP * (modExtraProtein ? 1.25 : 1.0);
    final finalF = baseF * (modLessFat ? 0.70 : 1.0);
    final finalCb = baseCb * (modLessCarb ? 0.75 : 1.0);

    final deltaKcal =
        (finalP - baseP) * 4.0 +
        (finalF - baseF) * 9.0 +
        (finalCb - baseCb) * 4.0;
    final finalC = math.max(0.0, baseC + deltaKcal);

    return TotalNutrition(
      calories: finalC,
      proteinG: finalP,
      fatG: finalF,
      carbsG: finalCb,
    );
  }

  // Chon "mon chinh" de hien thi noi bat o tren cung: la detection co
  // confidence cao nhat trong tam anh. Cac detection con lai (bun, rau,
  // nuoc cham...) duoc coi la "thanh phan" cua mam com, hien ben duoi.
  int? get mainDishIndex {
    if (detections.isEmpty) {
      return null;
    }

    int best = 0;

    for (int i = 1; i < detections.length; i++) {
      if (detections[i].confidence > detections[best].confidence) {
        best = i;
      }
    }

    return best;
  }

  String get mainDishName {
    final index = mainDishIndex;

    if (index == null) {
      return '';
    }

    return detections[index].nameVi;
  }

  // Ten hien thi tren banner: uu tien ten tu Gemini Vision (nhan dien dung
  // ten mon thuc te, khong gioi han 68 class YOLO), fallback ve ten thanh
  // phan co confidence cao nhat cua YOLO neu Gemini chua tra ve duoc.
  String get mainDishDisplayName {
    if (geminiMainDish != null && geminiMainDish!.isNotEmpty) {
      return geminiMainDish!;
    }

    return mainDishName;
  }

  // Them CA mon (theo so "phan an" da chon) vao nhat ky, dung ten + dinh
  // duong tu Gemini (hoac fallback YOLO) thay vi tung thanh phan rieng le -
  // vi danh sach "nguyen lieu" gio chi la thong tin tham khao, khong co
  // du lieu dinh duong rieng cho tung nguyen lieu.
  Future<void> addWholeDishToMeal() async {
    if (totalNutrition == null) {
      return;
    }

    final meal = await pickMealSlot(context);

    if (meal == null) {
      return;
    }

    final nutrition = scaledTotal;

    // Uu tien khoi luong uoc tinh tu Gemini/YOLO (estimatedWeightG), fallback 350g.
    final estimatedGramsPerServing =
        estimatedWeightG > 0 ? estimatedWeightG : 350;
    final adjustedGrams =
        (estimatedGramsPerServing * servings * portionSizeFactor).round();

    await widget.onAddMeal(
      MealEntry(
        name: mainDishDisplayName.isNotEmpty ? mainDishDisplayName : 'Món ăn',

        mealType: meal,

        time: DateTime.now(),

        portionG: adjustedGrams,

        calories: nutrition.calories,

        proteinG: nutrition.proteinG,

        fatG: nutrition.fatG,

        carbsG: nutrition.carbsG,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),

          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),

                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF0F172A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.biotech_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Quét món AI',
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF059669),
                                        Color(0xFF2563EB),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'HYBRID 4.0',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              'YOLO26 Ensemble + Gemini Vision · Phân tích Nutri-Score & GL',
                              style: TextStyle(
                                color: Color(0xFF047857),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Chỉ số Thực nghiệm Mô hình AI',
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const AiModelMetricsDialog(),
                          );
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEFF6FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.precision_manufacturing_rounded,
                          color: Color(0xFF2563EB),
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBE6DC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _buildModeTab(0, 'Món ăn', Icons.restaurant_rounded),
                        _buildModeTab(1, 'Nhãn bao bì', Icons.document_scanner_rounded),
                        _buildModeTab(2, 'Mã vạch', Icons.qr_code_scanner_rounded),
                      ],
                    ),
                  ),
                ),
              ),

              if (scanMode == 1)
                SliverToBoxAdapter(
                  child: NutritionLabelScannerView(
                    baseUrl: AppConfig.baseUrl,
                    userKey: AppSession.currentUserKey,
                    onAddMeal: _onAddFromScanner,
                  ),
                ),

              if (scanMode == 2)
                SliverToBoxAdapter(
                  child: BarcodeScannerView(
                    baseUrl: AppConfig.baseUrl,
                    userKey: AppSession.currentUserKey,
                    onAddMeal: _onAddFromScanner,
                  ),
                ),

              if (scanMode == 0) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),

                  child: HeroImageBlock(
                    image: decodedImage,

                    detections: detections,

                    onCamera: () {
                      pickImage(ImageSource.camera);
                    },

                    onGallery: () {
                      pickImage(ImageSource.gallery);
                    },
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 34, 20, 0),

                  child: AnalyzeButton(
                    loading: loading,

                    enabled: selectedImageBytes != null && !loading,

                    onTap: detect,
                  ),
                ),
              ),

              if (errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final meal = await showOfflineFoodPicker(
                              context,
                              suggestedIds: offlineSuggestions,
                            );
                            if (meal != null) {
                              await widget.onAddMeal(meal);
                            }
                          },
                          icon: const Icon(Icons.cloud_off_rounded, size: 18),
                          label: const Text(
                            'Không có mạng? Chọn món thủ công (offline)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Hien ket qua nhan dien theo dung thu tu nguoi dung muon doc:
              // 1) Mon an chinh la gi, 2) Tong dinh duong, 3) Canh bao ca nhan (neu co).
              if (hasScanResult)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),

                    child: MainDishBanner(
                      name: mainDishDisplayName.isNotEmpty
                          ? mainDishDisplayName
                          : 'Món ăn nhận diện',

                      confidence: mainDishIndex != null
                          ? detections[mainDishIndex!].confidence
                          : 0.95,

                      componentCount: detections.length,

                      fromGemini:
                          geminiMainDish != null && geminiMainDish!.isNotEmpty,
                    ),
                  ),
                ),

              if (hasScanResult)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (estimatedWeightG > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Khẩu phần ước tính: ~${(estimatedWeightG * servings * portionSizeFactor).round()} g',
                              style: const TextStyle(
                                color: Color(0xFF7F8A85),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        NutritionSummary(nutrition: scaledTotal),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 16,
                                    color: primaryDark,
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'TÙY CHỈNH KHẨU PHẦN & CÁCH ĂN THỰC TẾ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: primaryDark,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: 32,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: primary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      onPressed: addWholeDishToMeal,
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Lưu bữa',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _buildSizeChip('Nhỏ (70%)', 0.7),
                                  const SizedBox(width: 8),
                                  _buildSizeChip('Vừa (100%)', 1.0),
                                  const SizedBox(width: 8),
                                  _buildSizeChip('Lớn (130%)', 1.3),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildModifierChip(
                                    label: '🍚 Ít cơm/bún (-25% Carb)',
                                    selected: modLessCarb,
                                    onTap: () => setState(
                                      () => modLessCarb = !modLessCarb,
                                    ),
                                  ),
                                  _buildModifierChip(
                                    label: '🥣 Bỏ nước béo/mỡ (-30% Béo)',
                                    selected: modLessFat,
                                    onTap: () => setState(
                                      () => modLessFat = !modLessFat,
                                    ),
                                  ),
                                  _buildModifierChip(
                                    label: '🥩 Thêm đạm (+25% Đạm)',
                                    selected: modExtraProtein,
                                    onTap: () => setState(
                                      () => modExtraProtein = !modExtraProtein,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (modLessCarb && modLessFat) {
                                      modLessCarb = false;
                                      modLessFat = false;
                                    } else {
                                      modLessCarb = true;
                                      modLessFat = true;
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: (modLessCarb && modLessFat)
                                          ? const [
                                              Color(0xFF059669),
                                              Color(0xFF047857),
                                            ]
                                          : const [
                                              Color(0xFFEFF6FF),
                                              Color(0xFFECFDF5),
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (modLessCarb && modLessFat)
                                          ? const Color(0xFF059669)
                                          : const Color(0xFF93C5FD),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        (modLessCarb && modLessFat)
                                            ? Icons.verified_rounded
                                            : Icons.auto_fix_high_rounded,
                                        size: 16,
                                        color: (modLessCarb && modLessFat)
                                            ? Colors.white
                                            : const Color(0xFF1D4ED8),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          (modLessCarb && modLessFat)
                                              ? 'Đã bật Chế độ Ăn Lành Mạnh (Giảm Tinh bột & Mỡ bão hòa) · Bấm để hoàn tác'
                                              : '✨ 1-Chạm Tối ưu Sức khỏe (Healthy Swap: Giảm ~25% Calo, Mỡ & GL)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: (modLessCarb && modLessFat)
                                                ? Colors.white
                                                : const Color(0xFF1E3A8A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (warnings.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: buildWarnings(),
                  ),
                ),

              if (diseaseBreakdown.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: buildDiseaseBreakdown(diseaseBreakdown),
                  ),
                ),

              // Danh sach nguyen lieu do Gemini Vision nhan dien (chi mang
              // tinh tham khao - khong co dinh duong rieng cho tung nguyen
              // lieu, vi tong dinh duong da tinh cho CA mon o tren).
              if (ingredients.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),

                    child: const Text(
                      'Thành phần trong món',

                      style: TextStyle(
                        color: accent,

                        fontWeight: FontWeight.w900,

                        fontSize: 17,
                      ),
                    ),
                  ),
                ),

              if (ingredients.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),

                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ingredients
                          .map((item) => IngredientChip(label: item))
                          .toList(),
                    ),
                  ),
                ),

              // Stage 3: Chi hien thi bang chinh khau phan tung mon khi tren
              // mam com co NHIEU hon 1 mon khac nhau (detections.length > 1).
              if (detections.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Các món nhận diện trên ảnh (Tùy chỉnh khẩu phần)',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(detections.length, (idx) {
                          final d = detections[idx];
                          final scale = idx < detectionScales.length
                              ? detectionScales[idx]
                              : 1.0;
                          if (scale <= 0) return const SizedBox.shrink();
                          final baseG = d.portionG ?? 150;
                          final scaledG = (baseG * scale).round();
                          final scaledCal =
                              ((d.nutrition.calories ?? 0) * scale).round();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: d.confidenceColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.nameVi,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: accent,
                                        ),
                                      ),
                                      Text(
                                        '~$scaledG g · $scaledCal kcal (${(d.confidence * 100).round()}%)',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Giảm / Xóa món này',
                                  onPressed: () {
                                    setState(() {
                                      detectionScales[idx] = (scale - 0.5)
                                          .clamp(0.0, 5.0);
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                    size: 18,
                                  ),
                                ),
                                Text(
                                  '${scale.toStringAsFixed(1)}x',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Tăng khẩu phần',
                                  onPressed: () {
                                    setState(() {
                                      detectionScales[idx] = (scale + 0.5)
                                          .clamp(0.5, 5.0);
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Lưu riêng món này vào bữa ăn',
                                  color: primary,
                                  onPressed: () => _onAddFromScanner(
                                    d.nameVi,
                                    (d.nutrition.calories ?? 0) * scale,
                                    (d.nutrition.proteinG ?? 0) * scale,
                                    (d.nutrition.fatG ?? 0) * scale,
                                    (d.nutrition.carbsG ?? 0) * scale,
                                    scaledG,
                                  ),
                                  icon: const Icon(
                                    Icons.bookmark_add_outlined,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              // Chon so "phan an", co to/dia va tuy chinh thuc te truoc khi them
              // vao nhat ky - dinh duong se duoc tinh lai tuc thi (xem scaledTotal).
              if (hasScanResult)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Số phần ăn',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: accent,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: servings > 1
                                    ? () {
                                        setState(() {
                                          servings -= 1;
                                        });
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                ),
                              ),
                              Text(
                                '$servings',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: servings < 10
                                    ? () {
                                        setState(() {
                                          servings += 1;
                                        });
                                      }
                                    : null,
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16, color: Color(0xFFF1F5F9)),
                          const Text(
                            'Kích cỡ khẩu phần & Tùy chỉnh cách ăn',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildSizeChip('Nhỏ (70%)', 0.7),
                              const SizedBox(width: 8),
                              _buildSizeChip('Vừa (100%)', 1.0),
                              const SizedBox(width: 8),
                              _buildSizeChip('Lớn (130%)', 1.3),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildModifierChip(
                                label: '🍚 Ít cơm/bún (-25% Carb)',
                                selected: modLessCarb,
                                onTap: () => setState(
                                  () => modLessCarb = !modLessCarb,
                                ),
                              ),
                              _buildModifierChip(
                                label: '🥣 Bỏ nước béo/mỡ (-30% Béo)',
                                selected: modLessFat,
                                onTap: () => setState(
                                  () => modLessFat = !modLessFat,
                                ),
                              ),
                              _buildModifierChip(
                                label: '🥩 Thêm đạm (+25% Đạm)',
                                selected: modExtraProtein,
                                onTap: () => setState(
                                  () => modExtraProtein = !modExtraProtein,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (hasScanResult)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),

                    child: SizedBox(
                      height: 54,

                      width: double.infinity,

                      child: FilledButton.icon(
                        onPressed: addWholeDishToMeal,

                        icon: const Icon(Icons.add_rounded),

                        label: const Text(
                          'Thêm vào bữa',

                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),

                        style: FilledButton.styleFrom(
                          backgroundColor: primary,

                          foregroundColor: Colors.white,

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (hasScanResult)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final dishName = geminiMainDish ?? (detections.isNotEmpty ? detections.first.nameVi : 'Món ăn');
                          final conf = detections.isNotEmpty ? detections.first.confidence : 0.8;
                          final classId = detections.isNotEmpty ? detections.first.classId : null;
                          Map<String, dynamic>? bbox;
                          if (detections.isNotEmpty) {
                            final b = detections.first.box;
                            bbox = {'x1': b.left, 'y1': b.top, 'x2': b.right, 'y2': b.bottom};
                          }
                          FeedbackDialog.show(
                            context,
                            userKey: AppSession.currentUserKey,
                            predictedName: dishName,
                            predictedClassId: classId,
                            confidence: conf,
                            imageBytes: selectedImageBytes,
                            boundingBox: bbox,
                            baseUrl: AppConfig.baseUrl,
                          );
                        },
                        icon: const Icon(Icons.school_outlined, size: 18, color: Color(0xFFD97706)),
                        label: const Text(
                          'AI nhận diện chưa đúng? Góp ý sửa nhãn',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFFBEB),
                          side: const BorderSide(color: Color(0xFFFDE68A), width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SCAN UI
// ============================================================

class HeroImageBlock extends StatelessWidget {
  final ui.Image? image;

  final List<Detection> detections;

  final VoidCallback onCamera;

  final VoidCallback onGallery;

  const HeroImageBlock({
    super.key,
    required this.image,
    required this.detections,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,

      children: [
        AspectRatio(
          aspectRatio: 1.05,

          child: Container(
            clipBehavior: Clip.antiAlias,

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(28),
            ),

            child: image == null
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFF8FAFC),
                          primaryLight.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primary.withValues(alpha: 0.20),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_enhance_rounded,
                              color: primary,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Chụp hoặc tải ảnh món ăn',
                            style: GoogleFonts.plusJakartaSans(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'AI Vision sẽ tự động nhận diện và tính dinh dưỡng',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: DetectionPainter(
                      image: image!,
                      detections: detections,
                    ),
                  ),
          ),
        ),

        Positioned(
          right: 14,

          bottom: -22,

          child: Row(
            children: [
              FloatingActionButton.small(
                heroTag: 'gallery',

                backgroundColor: Colors.white,

                foregroundColor: primaryDark,

                onPressed: onGallery,

                child: const Icon(Icons.photo_library_rounded),
              ),

              const SizedBox(width: 8),

              FloatingActionButton(
                heroTag: 'camera',

                backgroundColor: primary,

                foregroundColor: Colors.white,

                onPressed: onCamera,

                child: const Icon(Icons.camera_alt_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AnalyzeButton extends StatelessWidget {
  final bool loading;
  final bool enabled;

  final VoidCallback onTap;

  const AnalyzeButton({
    super.key,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,

      width: double.infinity,

      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,

        icon: loading
            ? const SizedBox(
                width: 18,

                height: 18,

                child: CircularProgressIndicator(
                  color: Colors.white,

                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.auto_awesome_rounded),

        label: Text(loading ? 'Đang phân tích...' : 'Nhận diện món ăn'),

        style: FilledButton.styleFrom(
          backgroundColor: primary,

          foregroundColor: Colors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN DISH BANNER
// ============================================================
//
// Hien thi noi bat "mon an chinh la gi" ngay sau khi quet xong, truoc khi
// di vao chi tiet tung thanh phan dinh duong - dung thu tu nguoi dung
// muon doc: 1) Day la mon gi, 2) Thanh phan dinh duong nhu the nao.
class MainDishBanner extends StatelessWidget {
  final String name;
  final double confidence;
  final int componentCount;

  // True neu "name" den tu Gemini Vision nhan dien toan anh (chinh xac hon,
  // khong gioi han 68 class YOLO). False neu phai fallback ve ten thanh
  // phan co confidence cao nhat cua YOLO (Gemini loi/het quota).
  final bool fromGemini;

  const MainDishBanner({
    super.key,
    required this.name,
    required this.confidence,
    required this.componentCount,
    this.fromGemini = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primary, primaryDark],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'MÓN ĂN NHẬN DIỆN ĐƯỢC',
                    style: TextStyle(
                      color: primaryDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (fromGemini) '✨ Gemini Vision AI',
                    if (!fromGemini) 'Độ tin cậy ${(confidence * 100).round()}%',
                    if (componentCount > 1) '$componentCount thành phần trong mâm',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NutritionSummary extends StatelessWidget {
  final TotalNutrition nutrition;

  const NutritionSummary({super.key, required this.nutrition});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF43F5E), size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                nutrition.calories.toStringAsFixed(0),
                style: GoogleFonts.plusJakartaSans(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'kcal',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tổng năng lượng',
                  style: TextStyle(
                    color: primaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SummaryMacro(
                title: 'Đạm',
                value: nutrition.proteinG,
                color: const Color(0xFF6366F1),
                bgColor: const Color(0xFFEEF2FF),
              ),
              const SizedBox(width: 8),
              SummaryMacro(
                title: 'Béo',
                value: nutrition.fatG,
                color: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFFFBEB),
              ),
              const SizedBox(width: 8),
              SummaryMacro(
                title: 'Carb',
                value: nutrition.carbsG,
                color: const Color(0xFF10B981),
                bgColor: const Color(0xFFECFDF5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MealQualityBadgeBar(nutrition: nutrition),
        ],
      ),
    );
  }
}

class _MealQualityBadgeBar extends StatelessWidget {
  final TotalNutrition nutrition;

  const _MealQualityBadgeBar({required this.nutrition});

  @override
  Widget build(BuildContext context) {
    final cal = math.max(nutrition.calories, 1.0);
    final pRatio = (nutrition.proteinG * 4.0) / cal;
    final fRatio = (nutrition.fatG * 9.0) / cal;

    // Tinh diem Nutri-Score (A -> E) dua tren do can bang Macro & nang luong
    int score = 75;
    if (pRatio >= 0.20) score += 12;
    if (pRatio < 0.10) score -= 12;
    if (fRatio > 0.42) score -= 18;
    if (fRatio > 0.35) score -= 8;
    if (nutrition.calories > 850) score -= 15;
    if (nutrition.calories <= 600 && pRatio >= 0.18) score += 8;

    String grade = 'B';
    String gradeDesc = 'Cân bằng tốt';
    if (score >= 85) {
      grade = 'A';
      gradeDesc = 'Rất cân bằng';
    } else if (score >= 70) {
      grade = 'B';
      gradeDesc = 'Cân bằng tốt';
    } else if (score >= 55) {
      grade = 'C';
      gradeDesc = 'Trung bình';
    } else if (score >= 40) {
      grade = 'D';
      gradeDesc = 'Nhiều béo/calo';
    } else {
      grade = 'E';
      gradeDesc = 'Năng lượng cao';
    }

    // Tinh Tai luong Duong huyet uoc tinh (Glycemic Load - GL) co tinh hieu ung
    // dem cua Dam va Beo lam cham toc do lam rong da day.
    final macroSum = nutrition.carbsG + nutrition.proteinG + nutrition.fatG + 1.0;
    final bufferFactor =
        1.0 - ((nutrition.proteinG + nutrition.fatG) / macroSum) * 0.25;
    final gl = (nutrition.carbsG * 0.55 * bufferFactor).round();

    String glLabel = 'GL Thấp ($gl)';
    Color glColor = const Color(0xFF059669);
    String tip = 'Ổn định đường huyết sau ăn.';
    if (gl > 22) {
      glLabel = 'GL Cao ($gl)';
      glColor = const Color(0xFFD97706);
      tip = 'Mẹo: Ăn rau và đạm trước tinh bột giúp giảm ~20% đỉnh đường huyết.';
    } else if (gl >= 12) {
      glLabel = 'GL Vừa ($gl)';
      glColor = const Color(0xFF0284C7);
      tip = 'Mức tăng đường huyết vừa phải, phù hợp bữa chính.';
    }

    const grades = ['A', 'B', 'C', 'D', 'E'];
    const gradeColors = {
      'A': Color(0xFF038141),
      'B': Color(0xFF85BB2F),
      'C': Color(0xFFFECB02),
      'D': Color(0xFFEE8100),
      'E': Color(0xFFE63E11),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'NUTRI-SCORE',
                style: TextStyle(
                  color: Color(0xFF6EE7B7),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: grades.map((g) {
                  final active = g == grade;
                  final c = gradeColors[g]!;
                  return Container(
                    margin: const EdgeInsets.only(right: 3),
                    width: active ? 24 : 18,
                    height: active ? 24 : 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? c : c.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(active ? 7 : 5),
                      border: active
                          ? Border.all(color: Colors.white, width: 1.8)
                          : null,
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        color: g == 'C' && active
                            ? const Color(0xFF0F172A)
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: active ? 12 : 9.5,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gradeDesc,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: glColor.withValues(alpha: 0.6)),
                ),
                child: Text(
                  glLabel,
                  style: const TextStyle(
                    color: Color(0xFFFDE68A),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.tips_and_updates_rounded,
                size: 14,
                color: Color(0xFF34D399),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tip,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFA7F3D0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_run_rounded,
                  size: 14,
                  color: Color(0xFF93C5FD),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tiêu hao tương đương: ~${math.max((cal / 10).round(), 3)}p chạy bộ · ~${math.max((cal / 5.5).round(), 5)}p đi bộ nhanh · ~${math.max((cal / 8).round(), 4)}p đạp xe',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFDBEAFE),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryMacro extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final Color bgColor;

  const SummaryMacro({
    super.key,
    required this.title,
    required this.value,
    this.color = primary,
    this.bgColor = const Color(0xFFF1F5F9),
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${value.toStringAsFixed(1)}g',
              style: GoogleFonts.plusJakartaSans(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mot "chip" hien thi 1 nguyen lieu/thanh phan trong mon (do Gemini Vision
// liet ke) - chi mang tinh tham khao, khong co dinh duong rieng.
class IngredientChip extends StatelessWidget {
  final String label;

  const IngredientChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: primary.withValues(alpha: 0.18)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          const Icon(Icons.circle, size: 6, color: primary),

          const SizedBox(width: 6),

          Text(
            label,

            style: const TextStyle(
              color: accent,

              fontWeight: FontWeight.w700,

              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),
      ),

      child: Column(
        children: [
          Icon(icon, size: 40, color: primary),

          const SizedBox(height: 10),

          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),

          const SizedBox(height: 5),

          Text(
            subtitle,

            textAlign: TextAlign.center,

            style: TextStyle(color: accent.withValues(alpha: 0.45), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PAINTERS
// ============================================================

class DetectionPainter extends CustomPainter {
  final ui.Image image;

  final List<Detection> detections;

  DetectionPainter({required this.image, required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    final imageWidth = image.width.toDouble();

    final imageHeight = image.height.toDouble();

    final scale = math.max(size.width / imageWidth, size.height / imageHeight);

    final displayWidth = imageWidth * scale;

    final displayHeight = imageHeight * scale;

    final offsetX = (size.width - displayWidth) / 2;

    final offsetY = (size.height - displayHeight) / 2;

    canvas.save();

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawImageRect(
      image,

      Rect.fromLTWH(0, 0, imageWidth, imageHeight),

      Rect.fromLTWH(offsetX, offsetY, displayWidth, displayHeight),

      Paint(),
    );

    for (final detection in detections) {
      final rect = Rect.fromLTRB(
        offsetX + detection.box.left * scale,

        offsetY + detection.box.top * scale,

        offsetX + detection.box.right * scale,

        offsetY + detection.box.bottom * scale,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),

        Paint()
          ..color = detection.confidenceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetectionPainter old) {
    return old.image != image || old.detections != detections;
  }
}
