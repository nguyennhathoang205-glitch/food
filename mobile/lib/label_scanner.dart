import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_http.dart' as http;

const Color primary = Color(0xFF10B981);
const Color primaryDark = Color(0xFF059669);
const Color accent = Color(0xFF0F172A);
const Color gold = Color(0xFFF59E0B);

/// Widget Quet Nhan Dinh Duong (Nutrition Facts)
class NutritionLabelScannerView extends StatefulWidget {
  final String baseUrl;
  final String userKey;
  final Future<void> Function(
    String name,
    double calories,
    double protein,
    double fat,
    double carbs,
    int portionG,
  ) onAddMeal;

  const NutritionLabelScannerView({
    super.key,
    required this.baseUrl,
    required this.userKey,
    required this.onAddMeal,
  });

  @override
  State<NutritionLabelScannerView> createState() =>
      _NutritionLabelScannerViewState();
}

class _NutritionLabelScannerViewState extends State<NutritionLabelScannerView> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  List<dynamic> _warnings = [];
  int _servings = 1;

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _result = null;
      _warnings = [];
      _error = null;
      _servings = 1;
    });
    await _scanLabel();
  }

  Future<void> _scanLabel() async {
    if (_imageBytes == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/api/scan-label'),
      );
      req.fields['user_key'] = widget.userKey;
      req.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _imageBytes!,
          filename: 'label.jpg',
        ),
      );

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(utf8.decode(res.bodyBytes));

      if (res.statusCode == 200 && body['status'] == 'ok') {
        setState(() {
          _result = body['data'];
          _warnings = body['warnings'] ?? [];
        });
      } else {
        setState(() {
          _error = body['message'] ?? 'Không thể phân tích nhãn dinh dưỡng';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi kết nối máy chủ: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAddToDiary() async {
    if (_result == null) return;
    final name = _result!['product_name'] ?? 'Sản phẩm đóng gói';
    final cal = ((_result!['calories'] as num?)?.toDouble() ?? 0) * _servings;
    final pro = ((_result!['protein_g'] as num?)?.toDouble() ?? 0) * _servings;
    final fat = ((_result!['fat_g'] as num?)?.toDouble() ?? 0) * _servings;
    final carb = ((_result!['carbs_g'] as num?)?.toDouble() ?? 0) * _servings;
    final portion =
        (((_result!['serving_size_g'] as num?)?.toInt() ?? 100) * _servings);

    await widget.onAddMeal(name, cal, pro, fat, carb, portion);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm "$name" vào nhật ký!'),
          backgroundColor: primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner huong dan
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF123A31), Color(0xFF07201B)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.document_scanner_rounded, color: gold, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quét bảng Nutrition Facts',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'AI đọc calo, đường, muối, chất béo & cảnh báo dị ứng, bệnh lý ngay lập tức.',
                        style: TextStyle(
                          color: Color(0xFFC3D2CC),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Khu vuc chon anh / preview
          if (_imageBytes == null)
            _buildEmptyPicker()
          else
            _buildImagePreview(),

          const SizedBox(height: 16),

          // Trang thai Loading
          if (_loading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  CircularProgressIndicator(color: primary),
                  SizedBox(height: 14),
                  Text(
                    'Gemini AI đang phân tích nhãn dinh dưỡng...',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Đang đối chiếu hồ sơ dị ứng & bệnh lý của bạn',
                    style: TextStyle(color: Color(0xFF7F8A85), fontSize: 12),
                  ),
                ],
              ),
            ),

          // Loi
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE57373)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFD32F2F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFC62828)),
                    ),
                  ),
                ],
              ),
            ),

          // Ket qua doc nhan
          if (_result != null && !_loading) ...[
            _buildResultCard(),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4DFD5), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.center_focus_strong_rounded, color: primary, size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            'Chụp ảnh bảng dinh dưỡng trên vỏ bao bì',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Đảm bảo chữ rõ nét, đủ ánh sáng và không bị lóa',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF7F8A85)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('Chụp ảnh'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: const BorderSide(color: primary),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('Thư viện'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            children: [
              Image.memory(
                _imageBytes!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => setState(() {
                    _imageBytes = null;
                    _result = null;
                    _warnings = [];
                  }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Chụp lại'),
                ),
                TextButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Đổi ảnh'),
                ),
                if (!_loading)
                  FilledButton.icon(
                    onPressed: _scanLabel,
                    style: FilledButton.styleFrom(backgroundColor: primary),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Quét lại'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _result!;
    final name = r['product_name'] ?? 'Sản phẩm đóng gói';
    final brand = r['brand'];
    final serving = r['serving_size'] ?? '100g';
    final rating = r['health_rating'] ?? 'Trung bình';

    Color ratingColor = const Color(0xFF2E7D32);
    if (rating == 'Trung bình') ratingColor = const Color(0xFFE65100);
    if (rating == 'Cần hạn chế') ratingColor = const Color(0xFFC62828);

    final cal = ((r['calories'] as num?)?.toDouble() ?? 0) * _servings;
    final pro = ((r['protein_g'] as num?)?.toDouble() ?? 0) * _servings;
    final fat = ((r['fat_g'] as num?)?.toDouble() ?? 0) * _servings;
    final carb = ((r['carbs_g'] as num?)?.toDouble() ?? 0) * _servings;
    final sugar = ((r['sugar_g'] as num?)?.toDouble() ?? 0) * _servings;
    final sodium = ((r['sodium_mg'] as num?)?.toDouble() ?? 0) * _servings;
    final fiber = ((r['fiber_g'] as num?)?.toDouble() ?? 0) * _servings;
    final satFat = ((r['saturated_fat_g'] as num?)?.toDouble() ?? 0) * _servings;
    final ingredients = (r['ingredients'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header ten & thuong hieu
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (brand != null && brand.toString().isNotEmpty)
                      Text(
                        brand.toString().toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF7F8A85),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Khẩu phần: $serving',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF55605B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ratingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ratingColor),
                ),
                child: Text(
                  rating,
                  style: TextStyle(
                    color: ratingColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          if (r['summary'] != null && r['summary'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r['summary'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3B4842),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Danh gia benh ly chuyen sau
          _buildDiseaseBreakdown((r['disease_breakdown'] as List?) ?? []),

          const SizedBox(height: 8),

          // Canh bao suc khoe (neu co)
          if (_warnings.isNotEmpty) ...[
            ..._warnings.map((w) {
              final red = w['level'] == 'red';
              final color = red ? const Color(0xFFD32F2F) : const Color(0xFFE65100);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  border: Border.all(color: color, width: 1.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      red ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        w['message']?.toString() ?? '',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          // Chon so khau phan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Số khẩu phần ăn:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accent,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: _servings > 1 ? () => setState(() => _servings--) : null,
                    ),
                    Text(
                      '$_servings',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => setState(() => _servings++),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Bang dinh duong dang grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF9F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFECE7DE)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'NĂNG LƯỢNG (CALO)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF7F8A85),
                      ),
                    ),
                    Text(
                      '${cal.toStringAsFixed(0)} kcal',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    _buildNutriItem('Chất đạm', '${pro.toStringAsFixed(1)}g', Icons.fitness_center_rounded),
                    _buildNutriItem('Chất béo', '${fat.toStringAsFixed(1)}g', Icons.opacity_rounded),
                    _buildNutriItem('Tinh bột', '${carb.toStringAsFixed(1)}g', Icons.bakery_dining_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildNutriItem('Đường', '${sugar.toStringAsFixed(1)}g', Icons.cookie_outlined,
                        alert: sugar > 15),
                    _buildNutriItem('Natri (Muối)', '${sodium.toStringAsFixed(0)}mg', Icons.grain_rounded,
                        alert: sodium > 600),
                    _buildNutriItem('Chất xơ', '${fiber.toStringAsFixed(1)}g', Icons.eco_outlined),
                  ],
                ),
                if (satFat > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Chất béo bão hòa: ${satFat.toStringAsFixed(1)}g',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7F8A85)),
                  ),
                ],
              ],
            ),
          ),

          // Danh sach nguyen lieu
          if (ingredients.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Thành phần nguyên liệu đọc được:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ingredients.take(15).map((ing) {
                return Chip(
                  label: Text(ing, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE4DFD5)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 20),

          // Nut them vao nhat ky
          FilledButton.icon(
            onPressed: _handleAddToDiary,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: Text('Ghi ${cal.toStringAsFixed(0)} kcal vào Nhật ký'),
          ),
        ],
      ),
    );
  }

  Widget _buildNutriItem(String label, String value, IconData icon, {bool alert = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: alert ? const Color(0xFFFFF3E0) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: alert ? const Color(0xFFFFB74D) : const Color(0xFFEFECE5),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: alert ? const Color(0xFFE65100) : primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: alert ? const Color(0xFFE65100) : accent,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF7F8A85)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

Widget buildDiseaseBreakdown(List<dynamic> breakdown) =>
    _buildDiseaseBreakdown(breakdown);

Widget _buildDiseaseBreakdown(List<dynamic> breakdown) {
  if (breakdown.isEmpty) return const SizedBox.shrink();

  final cautionCount = breakdown
      .where((item) => item['level'] == 'orange' || item['level'] == 'red')
      .length;
  final userMatchedAlerts = breakdown
      .where(
        (item) =>
            item['user_matched'] == true &&
            (item['level'] == 'orange' || item['level'] == 'red'),
      )
      .length;

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFAFAF7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4DFD5), width: 1.2),
    ),
    child: Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: primary,
            size: 18,
          ),
        ),
        title: const Text(
          'Tham khảo 6 nhóm bệnh lý lâm sàng',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        subtitle: Text(
          userMatchedAlerts > 0
              ? 'Có $userMatchedAlerts lưu ý theo hồ sơ của bạn · Bấm để xem'
              : (cautionCount > 0
                    ? '${6 - cautionCount}/6 nhóm an toàn · Bấm để xem chi tiết'
                    : 'An toàn cho cả 6 nhóm bệnh · Bấm để xem chi tiết'),
          style: TextStyle(
            fontSize: 11,
            color: userMatchedAlerts > 0
                ? const Color(0xFFD97706)
                : const Color(0xFF7F8A85),
            fontWeight:
                userMatchedAlerts > 0 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        children: [
        ...breakdown.map((item) {
          final level = item['level']?.toString() ?? 'green';
          final status = item['status']?.toString() ?? '';
          final cond = item['condition']?.toString() ?? '';
          final detail = item['detail']?.toString() ?? '';
          final userMatched = item['user_matched'] == true;

          Color statusColor = const Color(0xFF2E7D32);
          Color statusBg = const Color(0xFFE8F5E9);
          IconData statusIcon = Icons.check_circle_rounded;

          if (level == 'orange') {
            statusColor = const Color(0xFFE65100);
            statusBg = const Color(0xFFFFF3E0);
            statusIcon = Icons.warning_rounded;
          } else if (level == 'red') {
            statusColor = const Color(0xFFD32F2F);
            statusBg = const Color(0xFFFFEBEE);
            statusIcon = Icons.dangerous_rounded;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: userMatched ? gold : statusColor.withValues(alpha: 0.3),
                width: userMatched ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      cond,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    if (userMatched) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: gold, width: 0.8),
                        ),
                        child: const Text(
                          'Hồ sơ của bạn',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A6D2B),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF55605B),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        ],
      ),
    ),
  );
}

/// Widget Tra cuu & Quet Ma Vach (Barcode)
class BarcodeScannerView extends StatefulWidget {
  final String baseUrl;
  final String userKey;
  final Future<void> Function(
    String name,
    double calories,
    double protein,
    double fat,
    double carbs,
    int portionG,
  ) onAddMeal;

  const BarcodeScannerView({
    super.key,
    required this.baseUrl,
    required this.userKey,
    required this.onAddMeal,
  });

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _product;
  List<dynamic> _warnings = [];
  int _servings = 1;

  final List<Map<String, String>> _samples = [
    {'name': 'Coca-Cola', 'code': '5449000000996'},
    {'name': 'Nutella', 'code': '3017620422003'},
    {'name': 'KitKat', 'code': '7613035345794'},
  ];

  Future<void> _lookup(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _product = null;
      _warnings = [];
      _servings = 1;
    });

    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/barcode/$clean?user_key=${widget.userKey}'),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));

      if (res.statusCode == 200 && body['status'] == 'ok') {
        setState(() {
          _product = body['data'];
          _warnings = body['warnings'] ?? [];
        });
      } else {
        setState(() {
          _error = body['message'] ?? 'Không tìm thấy mã vạch $clean';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi kết nối máy chủ: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanBarcodeImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    setState(() {
      _loading = true;
      _error = null;
      _product = null;
      _warnings = [];
    });

    try {
      // Gui anh de Gemini doc nhan & barcode
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/api/scan-label'),
      );
      req.fields['user_key'] = widget.userKey;
      req.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'barcode_photo.jpg'),
      );

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(utf8.decode(res.bodyBytes));

      if (res.statusCode == 200 && body['status'] == 'ok') {
        final data = body['data'];
        final barcode = data['barcode'];
        if (barcode != null && barcode.toString().isNotEmpty) {
          _controller.text = barcode.toString();
        }
        setState(() {
          _product = data;
          _warnings = body['warnings'] ?? [];
        });
      } else {
        setState(() {
          _error = body['message'] ?? 'Không nhận diện được mã vạch trên ảnh';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi phân tích: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAddToDiary() async {
    if (_product == null) return;
    final name = _product!['product_name'] ?? 'Sản phẩm đóng gói';
    final cal = ((_product!['calories'] as num?)?.toDouble() ?? 0) * _servings;
    final pro = ((_product!['protein_g'] as num?)?.toDouble() ?? 0) * _servings;
    final fat = ((_product!['fat_g'] as num?)?.toDouble() ?? 0) * _servings;
    final carb = ((_product!['carbs_g'] as num?)?.toDouble() ?? 0) * _servings;
    final portion =
        (((_product!['serving_size_g'] as num?)?.toInt() ?? 100) * _servings);

    await widget.onAddMeal(name, cal, pro, fat, carb, portion);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm "$name" vào nhật ký!'),
          backgroundColor: primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF14201C), Color(0xFF0F5C4D)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: gold, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tra cứu mã vạch sản phẩm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tra cứu cơ sở dữ liệu hàng triệu sản phẩm qua Open Food Facts.',
                        style: TextStyle(color: Color(0xFFC3D2CC), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // O nhap ma vach
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE4DFD5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nhập mã vạch (EAN-13, UPC...):',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Ví dụ: 5449000000996',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFE4DFD5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: primary, width: 1.5),
                          ),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        onSubmitted: _lookup,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => _lookup(_controller.text),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Tra cứu'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Chup ma vach qua camera
                OutlinedButton.icon(
                  onPressed: () => _scanBarcodeImage(ImageSource.camera),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primary,
                    side: const BorderSide(color: primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Center(child: Text('Chụp ảnh mã vạch trên bao bì')),
                ),

                const SizedBox(height: 12),
                // Ma vach mau thu nghiem
                const Text(
                  'Mã vạch mẫu để thử nhanh:',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7F8A85)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: _samples.map((s) {
                    return ActionChip(
                      label: Text('${s['name']} (${s['code']})', style: const TextStyle(fontSize: 11)),
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      onPressed: () {
                        _controller.text = s['code']!;
                        _lookup(s['code']!);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_loading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  CircularProgressIndicator(color: primary),
                  SizedBox(height: 12),
                  Text(
                    'Đang tra cứu thông tin sản phẩm...',
                    style: TextStyle(fontWeight: FontWeight.w700, color: accent),
                  ),
                ],
              ),
            ),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE57373)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFD32F2F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFC62828)),
                    ),
                  ),
                ],
              ),
            ),

          if (_product != null && !_loading) ...[
            _buildProductResult(),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildProductResult() {
    final p = _product!;
    final name = p['product_name'] ?? 'Sản phẩm đóng gói';
    final brand = p['brand'];
    final serving = p['serving_size'] ?? '100g';
    final cal = ((p['calories'] as num?)?.toDouble() ?? 0) * _servings;
    final pro = ((p['protein_g'] as num?)?.toDouble() ?? 0) * _servings;
    final fat = ((p['fat_g'] as num?)?.toDouble() ?? 0) * _servings;
    final carb = ((p['carbs_g'] as num?)?.toDouble() ?? 0) * _servings;
    final sugar = ((p['sugar_g'] as num?)?.toDouble() ?? 0) * _servings;
    final sodium = ((p['sodium_mg'] as num?)?.toDouble() ?? 0) * _servings;
    final rating = p['health_rating'] ?? 'Trung bình';

    Color ratingColor = const Color(0xFF2E7D32);
    if (rating == 'Trung bình') ratingColor = const Color(0xFFE65100);
    if (rating == 'Cần hạn chế') ratingColor = const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (brand != null && brand.toString().isNotEmpty)
                      Text(
                        brand.toString().toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF7F8A85),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Khẩu phần: $serving',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF55605B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ratingColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ratingColor),
                ),
                child: Text(
                  rating,
                  style: TextStyle(
                    color: ratingColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          if (p['summary'] != null && p['summary'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p['summary'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3B4842),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Danh gia benh ly chuyen sau
          _buildDiseaseBreakdown((p['disease_breakdown'] as List?) ?? []),

          const SizedBox(height: 8),

          // Canh bao
          if (_warnings.isNotEmpty) ...[
            ..._warnings.map((w) {
              final red = w['level'] == 'red';
              final color = red ? const Color(0xFFD32F2F) : const Color(0xFFE65100);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  border: Border.all(color: color, width: 1.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      red ? Icons.dangerous_rounded : Icons.warning_amber_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        w['message']?.toString() ?? '',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
          ],

          // So khau phan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Số khẩu phần ăn:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: accent),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: _servings > 1 ? () => setState(() => _servings--) : null,
                    ),
                    Text(
                      '$_servings',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: primary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => setState(() => _servings++),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Bang dinh duong
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF9F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFECE7DE)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'NĂNG LƯỢNG (CALO)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF7F8A85),
                      ),
                    ),
                    Text(
                      '${cal.toStringAsFixed(0)} kcal',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    _buildNutriItem('Chất đạm', '${pro.toStringAsFixed(1)}g'),
                    _buildNutriItem('Chất béo', '${fat.toStringAsFixed(1)}g'),
                    _buildNutriItem('Tinh bột', '${carb.toStringAsFixed(1)}g'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildNutriItem('Đường', '${sugar.toStringAsFixed(1)}g', alert: sugar > 15),
                    _buildNutriItem('Natri', '${sodium.toStringAsFixed(0)}mg', alert: sodium > 600),
                    _buildNutriItem('Khẩu phần', '$serving'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: _handleAddToDiary,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.bookmark_add_rounded),
            label: Text('Ghi ${cal.toStringAsFixed(0)} kcal vào Nhật ký'),
          ),
        ],
      ),
    );
  }

  Widget _buildNutriItem(String label, String value, {bool alert = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: alert ? const Color(0xFFFFF3E0) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: alert ? const Color(0xFFFFB74D) : const Color(0xFFEFECE5),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: alert ? const Color(0xFFE65100) : accent,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF7F8A85)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
