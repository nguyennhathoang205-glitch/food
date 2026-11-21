import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth_http.dart' as http;
import '../core/app_colors.dart';
import '../core/app_config.dart';
import '../core/app_session.dart';
import '../models/models.dart';
import 'meal_slot_picker.dart';

// ============================================================
// 1. HELPER QUY DOI KHAU PHAN TRUC QUAN & BU NUOC DIEN GIAI
// ============================================================

class VietnamesePortionHelper {
  /// Quy doi so gram uoc tinh sang don vi quen thuoc cua nguoi Viet
  /// (chen com, long ban tay dam, nam tay rau) de khong can can tieu ly.
  static String describe(int grams) {
    if (grams < 220) {
      return '≈ ½ chén cơm/bún + ½ lòng bàn tay đạm (khẩu phần nhỏ)';
    }
    if (grams <= 310) {
      return '≈ 1 chén cơm lưng + 1 lòng bàn tay thịt/cá + 1 nắm rau';
    }
    if (grams <= 420) {
      return '≈ 1 tô/đĩa tiêu chuẩn (1 chén vừa + 1 lòng bàn tay đạm + rau)';
    }
    if (grams <= 520) {
      return '≈ 1 tô lớn (1.5 chén cơm/bún + 1.5 lòng bàn tay đạm)';
    }
    return '≈ Phần đặc biệt lớn (~2 chén + nhiều đạm/nước dùng)';
  }
}

class SaltyMealHydrationHelper {
  static const List<String> _saltyKeywords = [
    'phở',
    'bún bò',
    'bún riêu',
    'bún mắm',
    'bún chả',
    'bún thịt nướng',
    'mì quảng',
    'mì cay',
    'mì gói',
    'mì xào',
    'hủ tiếu',
    'bánh canh',
    'lẩu',
    'kho',
    'nướng',
    'chiên',
    'mắm',
    'cơm tấm',
    'thịt quay',
    'dưa cải',
    'muối',
  ];

  static bool isSaltyOrSavory(String foodName) {
    final low = foodName.toLowerCase();
    return _saltyKeywords.any((k) => low.contains(k));
  }

  static int countTodaySaltyMeals(List<MealEntry> todayMeals) {
    return todayMeals.where((m) => isSaltyOrSavory(m.name)).length;
  }
}

// ============================================================
// 2. SMART MENU ADVISOR SHEET (QUET THUC DON QUAN AN)
// ============================================================

Future<void> showSmartMenuAdvisorSheet(
  BuildContext context, {
  required double dailyGoal,
  Future<void> Function(MealEntry)? onAddMeal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SmartMenuAdvisorSheet(
      dailyGoal: dailyGoal,
      onAddMeal: onAddMeal,
    ),
  );
}

class SmartMenuAdvisorSheet extends StatefulWidget {
  final double dailyGoal;
  final Future<void> Function(MealEntry)? onAddMeal;

  const SmartMenuAdvisorSheet({
    super.key,
    required this.dailyGoal,
    this.onAddMeal,
  });

  @override
  State<SmartMenuAdvisorSheet> createState() => _SmartMenuAdvisorSheetState();
}

class _SmartMenuAdvisorSheetState extends State<SmartMenuAdvisorSheet> {
  String _sampleType = 'com_van_phong';
  final TextEditingController _menuCtrl = TextEditingController();
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyze({XFile? imageFile}) async {
    setState(() => _loading = true);
    try {
      http.Response res;
      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/menu/analyze'),
        );
        req.fields['user_key'] = AppSession.currentUserKey;
        req.fields['sample_type'] = _sampleType;
        req.fields['daily_goal'] = widget.dailyGoal.toStringAsFixed(0);
        if (_menuCtrl.text.trim().isNotEmpty) {
          req.fields['menu_text'] = _menuCtrl.text.trim();
        }
        req.files.add(
          http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: 'menu.jpg',
          ),
        );
        final streamed = await req.send();
        res = await http.Response.fromStream(streamed);
      } else {
        res = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/menu/analyze'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_key': AppSession.currentUserKey,
            'sample_type': _sampleType,
            'menu_text': _menuCtrl.text.trim(),
            'daily_goal': widget.dailyGoal,
          }),
        );
      }
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _data = body is Map<String, dynamic> ? body : null;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    // Offline fallback de luon hoat dong muot ke ca khi mat mang
    if (mounted) {
      setState(() {
        _data = _offlineMenuFallback(_sampleType);
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _offlineMenuFallback(String group) {
    final customText = _menuCtrl.text.trim();
    if (customText.isNotEmpty) {
      final parts = customText
          .split(RegExp(r'[,\n]'))
          .map((s) => s.trim())
          .where((s) => s.length >= 2)
          .toList();
      if (parts.isNotEmpty) {
        final top = <Map<String, dynamic>>[];
        final caution = <Map<String, dynamic>>[];
        for (var i = 0; i < parts.length; i++) {
          final dish = parts[i];
          final low = dish.toLowerCase();
          final isHeavy = low.contains('chiên') ||
              low.contains('rán') ||
              low.contains('quay') ||
              low.contains('mỡ') ||
              low.contains('lẩu') ||
              low.contains('sườn');
          if (isHeavy && parts.length > 1) {
            caution.add({
              'name_vi': dish,
              'calories': 680,
              'level': 'orange',
              'reason': 'Món nhiều dầu mỡ / năng lượng cao cho 1 bữa.',
            });
          } else {
            top.add({
              'name_vi': dish,
              'badge': 'Top #${top.length + 1} Nên gọi',
              'calories': isHeavy ? 620 : 440,
              'protein_g': 30.0,
              'fat_g': isHeavy ? 22.0 : 10.5,
              'carbs_g': 54.0,
              'portion_g': 360,
              'health_score': isHeavy ? 76 : 91,
              'reason': 'Cân đối đạm & năng lượng phù hợp mục tiêu trong ngày',
            });
          }
        }
        return {
          'restaurant_type': 'Thực đơn bạn vừa nhập',
          'target_meal_kcal': (widget.dailyGoal * 0.33).round(),
          'top_picks': top,
          'caution_dishes': caution,
          'ordering_tip':
              'Mẹo gọi món: Ăn rau xanh trước tinh bột 5 phút và dặn quán để riêng nước sốt.',
        };
      }
    }
    if (group == 'tiec_nhau') {
      return {
        'restaurant_type': 'Thực đơn Nhà Hàng, Lẩu & Đồ Nướng',
        'target_meal_kcal': (widget.dailyGoal * 0.33).round(),
        'top_picks': [
          {
            'name_vi': 'Cá diêu hồng hấp hồng kông cuốn rau cải',
            'badge': 'Top #1 Nên gọi',
            'calories': 410,
            'protein_g': 39.0,
            'fat_g': 11.0,
            'carbs_g': 32.0,
            'portion_g': 350,
            'health_score': 94,
            'reason': 'Đạm cá dễ tiêu (39g), ít béo (11g) · Nhiều rau cuốn',
          },
          {
            'name_vi': 'Gỏi cuốn tôm thịt / Salad ức gà dầu mè',
            'badge': 'Top #2 Nên gọi',
            'calories': 340,
            'protein_g': 26.0,
            'fat_g': 8.0,
            'carbs_g': 40.0,
            'portion_g': 280,
            'health_score': 91,
            'reason': 'Thanh đạm, giàu chất xơ giúp no lâu mà không dư calo',
          },
        ],
        'caution_dishes': [
          {
            'name_vi': 'Ba chỉ bò Mỹ nướng sốt bơ tỏi & khoai tây chiên',
            'calories': 840,
            'level': 'red',
            'reason': 'Lượng mỡ bão hòa rất cao (48g Fat) dễ gây vượt TDEE.',
          },
        ],
        'ordering_tip':
            'Mẹo tiệc & lẩu: Ưu tiên đồ hấp/cuốn, nhúng nhiều rau nấm trước khi ăn thịt và hạn chế chấm sốt bơ/muối ớt đậm.',
      };
    }
    if (group == 'bun_pho') {
      return {
        'restaurant_type': 'Thực đơn Quán Phở, Bún & Miến',
        'target_meal_kcal': (widget.dailyGoal * 0.33).round(),
        'top_picks': [
          {
            'name_vi': 'Phở gà ta (bỏ da, ít bánh phở, nhiều giá trụng)',
            'badge': 'Top #1 Nên gọi',
            'calories': 420,
            'protein_g': 31.0,
            'fat_g': 8.5,
            'carbs_g': 52.0,
            'portion_g': 450,
            'health_score': 92,
            'reason': 'Ít béo (8.5g), giàu đạm nạc (31g) · Dễ tiêu hóa',
          },
          {
            'name_vi': 'Miến gà nấm hương thanh đạm',
            'badge': 'Top #2 Nên gọi',
            'calories': 380,
            'protein_g': 27.0,
            'fat_g': 7.0,
            'carbs_g': 50.0,
            'portion_g': 420,
            'health_score': 90,
            'reason': 'Năng lượng gọn nhẹ (380 kcal) · Tốt cho kiểm soát cân nặng',
          },
        ],
        'caution_dishes': [
          {
            'name_vi': 'Bún bò Huế giò heo & chả cua đặc biệt',
            'calories': 720,
            'level': 'red',
            'reason': 'Nhiều mỡ bão hòa (31g Fat) và nước dùng đậm muối Natri.',
          },
        ],
        'ordering_tip':
            'Mẹo gọi món: Dặn quán trụng nhiều giá/rau, lấy 2/3 lượng bún/phở và hạn chế húp hết nước béo.',
      };
    }
    return {
      'restaurant_type': 'Thực đơn Cơm Văn Phòng & Cơm Tấm',
      'target_meal_kcal': (widget.dailyGoal * 0.33).round(),
      'top_picks': [
        {
          'name_vi': 'Cơm ức gà áp chảo & bông cải luộc',
          'badge': 'Top #1 Nên gọi',
          'calories': 460,
          'protein_g': 38.0,
          'fat_g': 9.5,
          'carbs_g': 54.0,
          'portion_g': 350,
          'health_score': 94,
          'reason': 'Giàu đạm nạc (38g), ít mỡ (9.5g) · Vừa vặn ngân sách TDEE',
        },
        {
          'name_vi': 'Cơm cá thu sốt cà chua & canh rau ngót',
          'badge': 'Top #2 Nên gọi',
          'calories': 510,
          'protein_g': 32.0,
          'fat_g': 14.0,
          'carbs_g': 62.0,
          'portion_g': 380,
          'health_score': 88,
          'reason': 'Giàu Omega-3 tốt cho tim mạch & mỡ máu',
        },
      ],
      'caution_dishes': [
        {
          'name_vi': 'Cơm tấm sườn bì chả trứng ốp la',
          'calories': 760,
          'level': 'orange',
          'reason': 'Lượng tinh bột (82g Carb) và mỡ hành khá cao cho 1 bữa.',
        },
      ],
      'ordering_tip':
          'Mẹo gọi món: Ăn canh và rau luộc trước khi ăn cơm 5 phút giúp giảm ~20% đỉnh đường huyết sau ăn.',
    };
  }

  Future<void> _pickMenuPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xfile != null) {
      await _analyze(imageFile: xfile);
    }
  }

  Future<void> _logDish(Map<String, dynamic> d) async {
    final slot = await pickMealSlot(context);
    if (slot == null || !mounted) return;
    final entry = MealEntry(
      name: (d['name_vi'] ?? 'Món ăn').toString(),
      mealType: slot,
      time: DateTime.now(),
      portionG: (d['portion_g'] as num?)?.toInt() ?? 350,
      calories: (d['calories'] as num?)?.toDouble() ?? 450,
      proteinG: (d['protein_g'] as num?)?.toDouble() ?? 28,
      fatG: (d['fat_g'] as num?)?.toDouble() ?? 12,
      carbsG: (d['carbs_g'] as num?)?.toDouble() ?? 55,
    );
    if (widget.onAddMeal != null) {
      await widget.onAddMeal!(entry);
    } else {
      try {
        await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/meals'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(entry.toJson(AppSession.currentUserKey)),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primaryDark,
        content: Text('Đã chọn & lưu "${entry.name}" vào $slot'),
      ),
    );
  }

  Widget _presetBtn(String id, String label) {
    final active = _sampleType == id;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _sampleType = id);
          _analyze();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? primary : const Color(0xFFE2E8F0),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? primaryDark : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPicks = (_data?['top_picks'] as List?) ?? [];
    final cautions = (_data?['caution_dishes'] as List?) ?? [];
    final tip = (_data?['ordering_tip'] ?? '').toString();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.94,
      minChildSize: 0.55,
      builder: (context, scrollCtrl) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: primaryDark,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cố Vấn Thực Đơn Quán Ăn (Menu AI)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: accent,
                        ),
                      ),
                      Text(
                        'Chụp ảnh tờ Menu hoặc chọn loại quán để AI chọn món hợp bệnh lý & TDEE',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _presetBtn('com_van_phong', '🍱 Cơm văn phòng'),
                const SizedBox(width: 6),
                _presetBtn('bun_pho', '🍜 Quán Bún/Phở'),
                const SizedBox(width: 6),
                _presetBtn('tiec_nhau', '🍲 Lẩu & Nướng'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _menuCtrl,
                    decoration: InputDecoration(
                      hintText: 'Hoặc nhập các món trên menu (cách nhau dấu phẩy)...',
                      hintStyle: const TextStyle(fontSize: 11.5),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _analyze(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Chụp/Tải ảnh tờ Menu',
                  onPressed: _pickMenuPhoto,
                  icon: const Icon(Icons.camera_alt_rounded, size: 19),
                ),
                IconButton.filled(
                  tooltip: 'Phân tích Menu',
                  onPressed: () => _analyze(),
                  style: IconButton.styleFrom(backgroundColor: primaryDark),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Text(
                '✅ TOP MÓN NÊN GỌI TRÊN MENU NÀY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: primaryDark,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              ...topPicks.whereType<Map<String, dynamic>>().map((d) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: primaryDark,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${d['badge'] ?? 'Khuyên dùng'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${d['calories']} kcal · Đạm ${d['protein_g']}g',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${d['name_vi']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d['reason']}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: () => _logDish(d),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryDark,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.add_task_rounded, size: 16),
                          label: const Text(
                            'Chọn ăn món này (Lưu vào bữa)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (cautions.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '⚠️ MÓN NÊN HẠN CHẾ / LƯU Ý TRÊN MENU',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB45309),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                ...cautions.whereType<Map<String, dynamic>>().map((c) {
                  final isRed = c['level'] == 'red';
                  final col = isRed
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFD97706);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: col.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isRed
                                  ? Icons.dangerous_rounded
                                  : Icons.warning_amber_rounded,
                              color: col,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${c['name_vi']} (${c['calories']} kcal)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: col,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${c['reason']}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              if (tip.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tips_and_updates_rounded,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

// ============================================================
// 3. FRIDGE-TO-MEAL AI CHEF (GOI Y MON NAU TU NGUYEN LIEU TU LANH)
// ============================================================

Future<void> showFridgeToMealSheet(
  BuildContext context, {
  required double dailyGoal,
  Future<void> Function(MealEntry)? onAddMeal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => FridgeToMealSheet(
      dailyGoal: dailyGoal,
      onAddMeal: onAddMeal,
    ),
  );
}

class FridgeToMealSheet extends StatefulWidget {
  final double dailyGoal;
  final Future<void> Function(MealEntry)? onAddMeal;

  const FridgeToMealSheet({
    super.key,
    required this.dailyGoal,
    this.onAddMeal,
  });

  @override
  State<FridgeToMealSheet> createState() => _FridgeToMealSheetState();
}

class _FridgeToMealSheetState extends State<FridgeToMealSheet> {
  static const List<String> _allIngredients = [
    'Trứng gà',
    'Ức gà',
    'Đậu hũ',
    'Cà chua',
    'Bông cải xanh',
    'Rau cải',
    'Cá phi lê',
    'Thịt heo nạc',
    'Tôm tươi',
    'Nấm đông cô',
  ];

  final Set<String> _selected = {'Trứng gà', 'Đậu hũ', 'Cà chua', 'Ức gà'};
  final TextEditingController _customIngCtrl = TextEditingController();
  bool _loading = true;
  List<dynamic> _recipes = [];

  @override
  void initState() {
    super.initState();
    _fetchRecipes();
  }

  @override
  void dispose() {
    _customIngCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFridgePhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xfile != null) {
      await _fetchRecipes(imageFile: xfile);
    }
  }

  void _addCustomIngredientsFromText() {
    final raw = _customIngCtrl.text.trim();
    if (raw.isEmpty) {
      _fetchRecipes();
      return;
    }
    final parts = raw
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.length >= 2)
        .toList();
    if (parts.isNotEmpty) {
      setState(() {
        _selected.addAll(parts);
        _customIngCtrl.clear();
      });
    }
    _fetchRecipes();
  }

  Future<void> _fetchRecipes({XFile? imageFile}) async {
    setState(() => _loading = true);
    try {
      http.Response res;
      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/fridge/suggest'),
        );
        req.fields['user_key'] = AppSession.currentUserKey;
        req.fields['daily_goal'] = widget.dailyGoal.toStringAsFixed(0);
        req.fields['ingredients'] = _selected.join(', ');
        req.files.add(
          http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: 'fridge.jpg',
          ),
        );
        final streamed = await req.send();
        res = await http.Response.fromStream(streamed);
      } else {
        res = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/fridge/suggest'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_key': AppSession.currentUserKey,
            'ingredients': _selected.toList(),
            'daily_goal': widget.dailyGoal,
          }),
        );
      }
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted && body is Map<String, dynamic>) {
          final detected = (body['detected_ingredients'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            if (imageFile != null && detected != null && detected.isNotEmpty) {
              _selected.addAll(detected);
            }
            _recipes = (body['recipes'] as List?) ?? [];
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _recipes = [
          {
            'name_vi': 'Canh đậu hũ non cà chua nấu trứng & cơm vừa',
            'cook_time_min': 12,
            'calories': 395,
            'protein_g': 22.0,
            'fat_g': 11.0,
            'carbs_g': 50.0,
            'portion_g': 360,
            'steps_short':
                'Xào mềm cà chua, thêm nước sôi, thả đậu hũ non và khuấy nhẹ trứng.',
            'health_note':
                'Mềm, dễ tiêu hóa, đạm thực vật kết hợp đạm trứng lành mạnh.',
          },
          {
            'name_vi': 'Ức gà áp chảo sốt tiêu chanh & bông cải luộc',
            'cook_time_min': 15,
            'calories': 410,
            'protein_g': 39.0,
            'fat_g': 8.5,
            'carbs_g': 42.0,
            'portion_g': 340,
            'steps_short':
                'Áp chảo ức gà 5 phút mỗi mặt với tiêu chanh, ăn kèm bông cải xanh luộc.',
            'health_note':
                'Giàu đạm nạc, tải lượng đường huyết (GL) thấp, tốt cho giảm mỡ.',
          },
        ];
        _loading = false;
      });
    }
  }

  Future<void> _logRecipe(Map<String, dynamic> r) async {
    final slot = await pickMealSlot(context);
    if (slot == null || !mounted) return;
    final entry = MealEntry(
      name: (r['name_vi'] ?? 'Món tự nấu').toString(),
      mealType: slot,
      time: DateTime.now(),
      portionG: (r['portion_g'] as num?)?.toInt() ?? 350,
      calories: (r['calories'] as num?)?.toDouble() ?? 410,
      proteinG: (r['protein_g'] as num?)?.toDouble() ?? 30,
      fatG: (r['fat_g'] as num?)?.toDouble() ?? 10,
      carbsG: (r['carbs_g'] as num?)?.toDouble() ?? 48,
    );
    if (widget.onAddMeal != null) {
      await widget.onAddMeal!(entry);
    } else {
      try {
        await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/meals'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(entry.toJson(AppSession.currentUserKey)),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primaryDark,
        content: Text('Đã lưu món tự nấu "${entry.name}" vào $slot'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      maxChildSize: 0.94,
      minChildSize: 0.55,
      builder: (context, scrollCtrl) {
        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.kitchen_rounded,
                    color: primaryDark,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gợi Ý Món Nấu Từ Tủ Lạnh (Fridge AI)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: accent,
                        ),
                      ),
                      Text(
                        'Chọn nguyên liệu sẵn có tại nhà -> Gợi ý món Việt 15 phút chuẩn dinh dưỡng',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customIngCtrl,
                    decoration: InputDecoration(
                      hintText: 'Nhập thêm nguyên liệu khác (cách nhau dấu phẩy)...',
                      hintStyle: const TextStyle(fontSize: 11.5),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _addCustomIngredientsFromText(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Chụp/Tải ảnh Tủ lạnh để AI tự nhận diện nguyên liệu',
                  onPressed: _pickFridgePhoto,
                  icon: const Icon(Icons.camera_alt_rounded, size: 19),
                ),
                IconButton.filled(
                  tooltip: 'Thêm & Gợi ý món nấu',
                  onPressed: _addCustomIngredientsFromText,
                  style: IconButton.styleFrom(backgroundColor: primaryDark),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: {..._allIngredients, ..._selected}.map((ing) {
                final on = _selected.contains(ing);
                return FilterChip(
                  selected: on,
                  label: Text(
                    ing,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: on ? primaryDark : const Color(0xFF334155),
                    ),
                  ),
                  selectedColor: const Color(0xFFECFDF5),
                  checkmarkColor: primaryDark,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selected.add(ing);
                      } else if (_selected.length > 1) {
                        _selected.remove(ing);
                      }
                    });
                    _fetchRecipes();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._recipes.whereType<Map<String, dynamic>>().map((r) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '⏱ ${r['cook_time_min'] ?? 15} phút',
                              style: const TextStyle(
                                color: primaryDark,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${r['calories']} kcal · Đạm ${r['protein_g']}g · Béo ${r['fat_g']}g',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${r['name_vi']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cách chế biến: ${r['steps_short']}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '💚 ${r['health_note']}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: () => _logRecipe(r),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text(
                            'Nấu món này & Lưu vào bữa ăn',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// ============================================================
// 4. CIRCADIAN MEAL TIMING & INTERMITTENT FASTING CARD
// ============================================================

class CircadianTimingCard extends StatefulWidget {
  final List<MealEntry> meals;

  const CircadianTimingCard({super.key, required this.meals});

  @override
  State<CircadianTimingCard> createState() => _CircadianTimingCardState();
}

class _CircadianTimingCardState extends State<CircadianTimingCard> {
  int _protocolIndex = 0;

  static const _protocols = [
    (label: '16:8 Đốt mỡ', startHour: 11, endHour: 19, fastHours: 16),
    (label: '14:10 Linh hoạt', startHour: 9, endHour: 19, fastHours: 14),
    (label: '12:12 Cân bằng', startHour: 7, endHour: 19, fastHours: 12),
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final proto = _protocols[_protocolIndex];
    final todayMeals = widget.meals
        .where(
          (m) =>
              m.time.year == now.year &&
              m.time.month == now.month &&
              m.time.day == now.day,
        )
        .toList();

    final source = todayMeals.isNotEmpty
        ? todayMeals
        : widget.meals.take(6).toList();
    bool hasLateNight = false;

    if (source.isNotEmpty) {
      hasLateNight = source.any(
        (m) => m.time.hour >= 21 || (m.time.hour == 20 && m.time.minute >= 30),
      );
    }

    final currentHourDouble = now.hour + now.minute / 60.0;
    final inEatingWindow =
        currentHourDouble >= proto.startHour &&
        currentHourDouble < proto.endHour;

    double progress;
    String phaseTitle;
    String phaseSubtitle;
    if (inEatingWindow) {
      final eatSpan = (proto.endHour - proto.startHour).toDouble();
      final elapsed = (currentHourDouble - proto.startHour).clamp(0.0, eatSpan);
      progress = (elapsed / eatSpan).clamp(0.0, 1.0);
      final remMin = ((eatSpan - elapsed) * 60).round();
      final rh = remMin ~/ 60;
      final rm = remMin % 60;
      phaseTitle =
          '🥗 Đang trong Khung Giờ Ăn (${proto.startHour}:00 – ${proto.endHour}:00)';
      phaseSubtitle =
          'Còn ${rh}h ${rm}p trước khi bước vào chu kỳ nghỉ tiêu hóa & đốt mỡ.';
    } else {
      final fastSpan = proto.fastHours.toDouble();
      double elapsedFast;
      if (currentHourDouble >= proto.endHour) {
        elapsedFast = currentHourDouble - proto.endHour;
      } else {
        elapsedFast = (24.0 - proto.endHour) + currentHourDouble;
      }
      progress = (elapsedFast / fastSpan).clamp(0.0, 1.0);
      final remMin = ((fastSpan - elapsedFast).clamp(0.0, fastSpan) * 60)
          .round();
      final rh = remMin ~/ 60;
      final rm = remMin % 60;
      final stage = elapsedFast >= 12
          ? 'Đang ở vùng Đốt mỡ tự thân (Lipolysis)'
          : 'Đang ổn định Insulin & tiêu hóa';
      phaseTitle =
          '🔥 Đang trong Chu Kỳ Nhịn Ăn Gián Đoạn (${proto.label})';
      phaseSubtitle = '$stage · Còn ${rh}h ${rm}p đến khung bữa ăn tiếp theo.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF7C3AED),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nhịp Sinh Học & Nhịn Ăn Gián Đoạn (IF)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: accent,
                      ),
                    ),
                    Text(
                      'Đồng bộ khung giờ ăn với chu kỳ tiêu hóa & đốt mỡ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasLateNight
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasLateNight ? 'Ăn khuya' : proto.label.split(' ').first,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: hasLateNight
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(_protocols.length, (i) {
              final p = _protocols[i];
              final sel = _protocolIndex == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  child: InkWell(
                    onTap: () => setState(() => _protocolIndex = i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFF7C3AED)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        p.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: inEatingWindow
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: inEatingWindow
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFFDDD6FE),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phaseTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: inEatingWindow
                        ? const Color(0xFF065F46)
                        : const Color(0xFF5B21B6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phaseSubtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    color: inEatingWindow
                        ? const Color(0xFF10B981)
                        : const Color(0xFF7C3AED),
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (hasLateNight) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.nights_stay_rounded,
                    size: 15,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Phát hiện bữa ăn sau 20:30. Kết thúc bữa tối trước 20:00 giúp giảm tích mỡ nội tạng.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

