import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_http.dart' as http;
import 'core/day_stats.dart';
import 'core/meal_slot.dart';

const Color _primary = Color(0xFF10B981);
const Color _primaryDark = Color(0xFF059669);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);

BoxDecoration _card() => BoxDecoration(
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
);

// ============================================================
// STREAK + WEEKLY INSIGHT
// ============================================================

/// [dayKcal]: tong kcal theo tung ngay (key = ngay, bo gio).
class StreakInsightCard extends StatelessWidget {
  final Map<DateTime, double> dayKcal;
  final double goalKcal;

  const StreakInsightCard({
    super.key,
    required this.dayKcal,
    required this.goalKcal,
  });

  static DateTime dayOnly(DateTime d) => DayStats.dayOnly(d);

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final week = List.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );

    final stats = DayStats.weeklyAverage(dayKcal);
    final avg = stats.average;
    final loggedDays = stats.loggedDays;

    final streak = DayStats.streak(dayKcal);

    String insight;

    // Chua du ngay co ghi chep thi KHONG ket luan an it/an nhieu: ngay trong
    // co the la quen ghi chu khong phai nhin an.
    if (loggedDays == 0) {
      insight = 'Ghi lại bữa ăn đầu tiên để bắt đầu theo dõi nhé!';
    } else if (loggedDays < DayStats.minDaysForInsight) {
      insight =
          'Đã ghi $loggedDays/${DayStats.minDaysForInsight} ngày. '
          'Ghi thêm vài ngày để xem nhận xét về thói quen ăn uống.';
    } else if (goalKcal > 0 && avg > goalKcal * 1.1) {
      insight =
          'Trung bình tuần này vượt mục tiêu '
          '${(avg - goalKcal).round()} kcal/ngày. Thử giảm tinh bột buổi tối.';
    } else if (goalKcal > 0 && avg < goalKcal * 0.7) {
      insight =
          'Bạn đang ăn ít hơn mục tiêu khá nhiều, '
          'hãy bổ sung đủ bữa để không bị hụt năng lượng.';
    } else {
      insight = 'Tuần này bạn giữ calo rất đều, tiếp tục phát huy! 💪';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                streak > 0 ? '🔥 $streak ngày liên tiếp' : '🔥 Chưa có chuỗi',
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                loggedDays == 0
                    ? ''
                    : 'TB ${avg.round()} kcal/ngày ($loggedDays ngày có ghi)',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: week.map((d) {
              final has = dayKcal.containsKey(d);
              final isToday = d == today;
              const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

              return Column(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: has
                          ? _primary
                          : _primary.withValues(alpha: 0.08),
                      border: isToday
                          ? Border.all(color: _primaryDark, width: 2)
                          : null,
                    ),
                    child: has
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    names[d.weekday - 1],
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(insight, style: const TextStyle(color: _ink, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================
// MANUAL ADD (khong can quet)
// ============================================================

typedef ManualMealCallback =
    void Function({
      required String name,
      required String mealType,
      required int portionG,
      required double calories,
      required double proteinG,
      required double fatG,
      required double carbsG,
    });

Future<void> showManualAddSheet(
  BuildContext context, {
  required String baseUrl,
  required ManualMealCallback onAdd,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ManualAddBody(baseUrl: baseUrl, onAdd: onAdd),
    ),
  );
}

class _ManualAddBody extends StatefulWidget {
  final String baseUrl;
  final ManualMealCallback onAdd;

  const _ManualAddBody({required this.baseUrl, required this.onAdd});

  @override
  State<_ManualAddBody> createState() => _ManualAddBodyState();
}

class _ManualAddBodyState extends State<_ManualAddBody> {
  static const types = ['Bữa sáng', 'Bữa trưa', 'Bữa tối', 'Ăn phụ'];

  List<Map<String, dynamic>> foods = [];
  Map<String, dynamic>? selected;
  String query = '';
  String mealType = types[1];
  int portion = 150;
  bool loading = true;

  @override
  void initState() {
    super.initState();

    mealType = MealSlot.forTime(DateTime.now());

    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/foods'));

      final list = (jsonDecode(res.body)['foods'] as List)
          .cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          foods = list;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  static String _fold(String s) {
    const from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

    final lower = s.toLowerCase();
    final b = StringBuffer();

    for (final r in lower.runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : c);
    }

    return b.toString();
  }

  double _num(String key) => ((selected?[key] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    final q = _fold(query.trim());
    final filtered = foods
        .where(
          (f) => q.isEmpty || _fold('${f['name_vi']}').contains(q),
        )
        .take(30)
        .toList();

    final factor = portion / 100.0;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thêm món thủ công',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'Tìm món ăn (vd: phở, cơm tấm...)',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _primary),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final f = filtered[i];
                        final isSel = identical(f, selected);

                        return ListTile(
                          dense: true,
                          selected: isSel,
                          selectedTileColor: _primary.withValues(alpha: 0.10),
                          title: Text('${f['name_vi']}'),
                          subtitle: Text(
                            '${((f['calories_per_100g'] as num?) ?? 0).round()}'
                            ' kcal / 100g',
                          ),
                          onTap: () => setState(() => selected = f),
                        );
                      },
                    ),
            ),
            if (selected != null) ...[
              const Divider(),
              Row(
                children: [
                  const Text('Khẩu phần'),
                  Expanded(
                    child: Slider(
                      value: portion.toDouble(),
                      min: 30,
                      max: 600,
                      divisions: 57,
                      activeColor: _primary,
                      label: '$portion g',
                      onChanged: (v) => setState(() => portion = v.round()),
                    ),
                  ),
                  Text('$portion g'),
                ],
              ),
              Wrap(
                spacing: 6,
                children: types
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t),
                        selected: mealType == t,
                        onSelected: (_) => setState(() => mealType = t),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    widget.onAdd(
                      name: '${selected!['name_vi']}',
                      mealType: mealType,
                      portionG: portion,
                      calories: _num('calories_per_100g') * factor,
                      proteinG: _num('protein_g') * factor,
                      fatG: _num('fat_g') * factor,
                      carbsG: _num('carbs_g') * factor,
                    );

                    Navigator.pop(context);
                  },
                  child: Text(
                    'Thêm ${(_num('calories_per_100g') * factor).round()} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HEALTH PROFILE (di ung / benh ly / thuoc / OCR ho so y te)
// ============================================================

const List<String> kAllergyOptions = [
  'đậu nành', 'đậu phộng', 'tôm', 'cua/ghẹ', 'hải sản',
  'sữa', 'trứng', 'gluten', 'mè',
];

const List<String> kConditionOptions = [
  'tiểu đường', 'gout', 'huyết áp cao', 'mỡ máu',
  'cholesterol cao', 'béo phì', 'bệnh thận', 'đau dạ dày',
];

const List<String> kMedicationOptions = [
  'Statin (mỡ máu)',
  'Metformin (tiểu đường)',
  'Thuốc huyết áp (ACEi/ARB)',
  'Warfarin (chống đông)',
  'Allopurinol (Gout)',
  'Kháng sinh',
  'NSAID / Thuốc dạ dày',
];

Future<Map<String, List<String>>> fetchHealthProfile(
  String baseUrl,
  String userKey,
) async {
  try {
    final res = await http.get(Uri.parse('$baseUrl/api/health/$userKey'));
    final h = jsonDecode(res.body)['health'];

    return {
      'allergies': ((h['allergies'] as List?) ?? []).map((e) => '$e').toList(),
      'conditions': ((h['conditions'] as List?) ?? []).map((e) => '$e').toList(),
      'medications': ((h['medications'] as List?) ?? []).map((e) => '$e').toList(),
    };
  } catch (_) {
    return {'allergies': [], 'conditions': [], 'medications': []};
  }
}

/// Tra ve true neu nguoi dung da luu.
Future<bool> showHealthProfileDialog(
  BuildContext context, {
  required String baseUrl,
  required String userKey,
}) async {
  final profile = await fetchHealthProfile(baseUrl, userKey);

  if (!context.mounted) {
    return false;
  }

  final allergies = (profile['allergies'] ?? []).toSet();
  final conditions = (profile['conditions'] ?? []).toSet();
  final medications = (profile['medications'] ?? []).toSet();
  var saved = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final allergyCtrl = TextEditingController();
      final conditionCtrl = TextEditingController();
      final medicationCtrl = TextEditingController();

      return StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget section(
            String title,
            IconData icon,
            List<String> options,
            Set<String> selected,
            TextEditingController ctrl,
            String hint,
          ) {
            final custom = selected.where((e) => !options.contains(e));

            void addCustom() {
              final v = ctrl.text.trim();

              if (v.isNotEmpty) {
                setLocal(() => selected.add(v));
                ctrl.clear();
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: _primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ...options.map(
                      (o) => FilterChip(
                        label: Text(o),
                        selected: selected.contains(o),
                        selectedColor: _primary.withValues(alpha: 0.15),
                        onSelected: (v) => setLocal(() {
                          v ? selected.add(o) : selected.remove(o);
                        }),
                      ),
                    ),
                    ...custom.map(
                      (o) => InputChip(
                        label: Text(o),
                        onDeleted: () => setLocal(() => selected.remove(o)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add_circle_rounded),
                      color: _primary,
                      onPressed: addCustom,
                    ),
                  ),
                  onSubmitted: (_) => addCustom(),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Hồ sơ sức khỏe & Đơn thuốc'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    section(
                      'Dị ứng thực phẩm',
                      Icons.warning_amber_rounded,
                      kAllergyOptions,
                      allergies,
                      allergyCtrl,
                      'Thêm dị ứng khác (vd: xoài, cá hồi)',
                    ),
                    const SizedBox(height: 18),
                    section(
                      'Bệnh lý nền',
                      Icons.monitor_heart_rounded,
                      kConditionOptions,
                      conditions,
                      conditionCtrl,
                      'Thêm bệnh khác',
                    ),
                    const SizedBox(height: 18),
                    section(
                      'Thuốc đang dùng (Cảnh báo tương tác)',
                      Icons.medication_rounded,
                      kMedicationOptions,
                      medications,
                      medicationCtrl,
                      'Nhập tên thuốc (vd: Atorvastatin 10mg, Losartan)',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chỉ mang tính tham khảo dinh dưỡng lâm sàng, không thay thế chỉ định của bác sĩ.',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _primary),
                onPressed: () async {
                  try {
                    await http.put(
                      Uri.parse('$baseUrl/api/health/$userKey'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'allergies': allergies.toList(),
                        'conditions': conditions.toList(),
                        'medications': medications.toList(),
                      }),
                    );
                    saved = true;
                  } catch (_) {}

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      );
    },
  );

  return saved;
}

/// Mo BottomSheet quet Don thuoc / Phieu xet nghiem mau bang AI OCR.
Future<bool> showMedicalOcrSheet(
  BuildContext context, {
  required String baseUrl,
  required String userKey,
}) async {
  var synced = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _MedicalOcrSheetBody(
      baseUrl: baseUrl,
      userKey: userKey,
      onSynced: () {
        synced = true;
      },
    ),
  );
  return synced;
}

class _MedicalOcrSheetBody extends StatefulWidget {
  final String baseUrl;
  final String userKey;
  final VoidCallback onSynced;

  const _MedicalOcrSheetBody({
    required this.baseUrl,
    required this.userKey,
    required this.onSynced,
  });

  @override
  State<_MedicalOcrSheetBody> createState() => _MedicalOcrSheetBodyState();
}

class _MedicalOcrSheetBodyState extends State<_MedicalOcrSheetBody> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;
  bool _loading = false;
  bool _syncing = false;
  String? _error;
  Map<String, dynamic>? _record;

  Future<void> _scanWithSample(String sampleType) async {
    setState(() {
      _loading = true;
      _error = null;
      _imageBytes = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/health/scan-medical'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sample': sampleType}),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && body['status'] == 'ok') {
        setState(() {
          _record = body['medical_record'] as Map<String, dynamic>?;
        });
      } else {
        setState(() {
          _error = body['message']?.toString() ?? 'Không đọc được hồ sơ y tế';
        });
      }
    } catch (e) {
      setState(() => _error = 'Lỗi kết nối: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndScanImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _loading = true;
      _error = null;
      _record = null;
    });

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${widget.baseUrl}/api/health/scan-medical'),
      );
      req.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'medical.jpg'),
      );
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && body['status'] == 'ok') {
        setState(() {
          _record = body['medical_record'] as Map<String, dynamic>?;
        });
      } else {
        setState(() {
          _error = body['message']?.toString() ?? 'Không đọc được ảnh y tế';
        });
      }
    } catch (e) {
      setState(() => _error = 'Lỗi kết nối: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncToHealthProfile() async {
    if (_record == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final current = await fetchHealthProfile(widget.baseUrl, widget.userKey);
      final allergies = <String>{
        ...(current['allergies'] ?? []),
        ...((_record!['detected_allergies'] as List?) ?? []).map((e) => '$e'),
      };
      final conditions = <String>{
        ...(current['conditions'] ?? []),
        ...((_record!['detected_conditions'] as List?) ?? []).map((e) => '$e'),
      };
      final medications = <String>{
        ...(current['medications'] ?? []),
        ...((_record!['detected_medications'] as List?) ?? []).map((e) => '$e'),
      };

      await http.put(
        Uri.parse('${widget.baseUrl}/api/health/${widget.userKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'allergies': allergies.toList(),
          'conditions': conditions.toList(),
          'medications': medications.toList(),
        }),
      );
      widget.onSynced();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã đồng bộ bệnh lý & đơn thuốc vào Hồ sơ sức khỏe!',
            ),
            backgroundColor: _primary,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Không thể lưu hồ sơ: $e');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicators = (_record?['lab_indicators'] as List?) ?? [];
    final conds = (_record?['detected_conditions'] as List?) ?? [];
    final meds = (_record?['detected_medications'] as List?) ?? [];
    final advice = (_record?['dietary_advice'] as List?) ?? [];
    final drugNotes = (_record?['drug_food_notes'] as List?) ?? [];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  color: _primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quét Đơn thuốc & Xét nghiệm (AI OCR)',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Trích xuất chỉ số máu & bệnh lý từ phiếu xét nghiệm',
                      style: TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndScanImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Chụp phiếu'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndScanImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Chọn ảnh'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Hoặc thử nhanh hồ sơ lâm sàng mẫu:',
            style: TextStyle(
              fontSize: 11.5,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(
                  Icons.biotech_rounded,
                  size: 16,
                  color: Color(0xFFD32F2F),
                ),
                label: const Text(
                  'Mẫu Xét nghiệm máu (Tiểu đường, Gout, Mỡ máu)',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                onPressed: _loading ? null : () => _scanWithSample('blood_test'),
              ),
              ActionChip(
                avatar: const Icon(
                  Icons.medication_liquid_rounded,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
                label: const Text(
                  'Mẫu Đơn thuốc Tim mạch - Dạ dày',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                onPressed: _loading
                    ? null
                    : () => _scanWithSample('prescription'),
              ),
            ],
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imageBytes!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: _primary),
                  SizedBox(height: 10),
                  Text(
                    'AI đang đọc chỉ số xét nghiệm và đơn thuốc...',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_record != null && !_loading) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_record!['title'] ?? 'Kết quả phân tích y tế'}',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_record!['summary'] ?? ''}',
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                  if (conds.isNotEmpty || meds.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...conds.map(
                          (c) => Chip(
                            avatar: const Icon(
                              Icons.monitor_heart_rounded,
                              size: 15,
                              color: Color(0xFFD32F2F),
                            ),
                            label: Text(
                              '$c',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        ...meds.map(
                          (m) => Chip(
                            avatar: const Icon(
                              Icons.medication_rounded,
                              size: 15,
                              color: Color(0xFF2563EB),
                            ),
                            label: Text(
                              '$m',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (indicators.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'CHỈ SỐ XÉT NGHIỆM / SINH HIỆU',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...indicators.map((ind) {
                final high = ind['status'] == 'high' || ind['status'] == 'low';
                final color = high
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF059669);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${ind['name'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${ind['value'] ?? ''} (Chuẩn: ${ind['normal_range'] ?? ''})',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ind['meaning'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${ind['meaning']}',
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
            if (drugNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'CẢNH BÁO TƯƠNG TÁC THUỐC – THỰC PHẨM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB45309),
                ),
              ),
              const SizedBox(height: 6),
              ...drugNotes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💊 ', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Text(
                          '$n',
                          style: const TextStyle(fontSize: 12, color: _ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (advice.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'PHÁC ĐỒ DINH DƯỠNG KHUYẾN NGHỊ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _primaryDark,
                ),
              ),
              const SizedBox(height: 6),
              ...advice.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🥗 ', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Text(
                          '$a',
                          style: const TextStyle(fontSize: 12, color: _ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _syncing ? null : _syncToHealthProfile,
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  _syncing
                      ? 'Đang đồng bộ...'
                      : 'Đồng bộ Bệnh lý & Đơn thuốc vào Hồ sơ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The nho tren Trang chu / Ho so hien ho so suc khoe hien tai + nut chinh sua & quet OCR y te.
class HealthProfileCard extends StatefulWidget {
  final String baseUrl;
  final String userKey;

  /// Goi sau khi nguoi dung luu, de app tai lai di ung/benh ly cho goi y mon.
  final VoidCallback? onChanged;

  const HealthProfileCard({
    super.key,
    required this.baseUrl,
    required this.userKey,
    this.onChanged,
  });

  @override
  State<HealthProfileCard> createState() => _HealthProfileCardState();
}

class _HealthProfileCardState extends State<HealthProfileCard> {
  Map<String, List<String>> profile = {
    'allergies': [],
    'conditions': [],
    'medications': [],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await fetchHealthProfile(widget.baseUrl, widget.userKey);

    if (mounted) {
      setState(() => profile = p);
    }
  }

  Future<void> _edit() async {
    final saved = await showHealthProfileDialog(
      context,
      baseUrl: widget.baseUrl,
      userKey: widget.userKey,
    );

    await _load();

    if (saved) {
      widget.onChanged?.call();
    }
  }

  Future<void> _openMedicalOcr() async {
    final synced = await showMedicalOcrSheet(
      context,
      baseUrl: widget.baseUrl,
      userKey: widget.userKey,
    );
    await _load();
    if (synced) {
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = profile['allergies'] ?? [];
    final c = profile['conditions'] ?? [];
    final m = profile['medications'] ?? [];
    final empty = a.isEmpty && c.isEmpty && m.isEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: _edit,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety_rounded, color: _primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Hồ sơ sức khỏe & Đơn thuốc',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  empty ? 'Thiết lập' : 'Chỉnh sửa',
                  style: const TextStyle(
                    color: _primaryDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (empty)
              const Text(
                'Khai báo dị ứng, bệnh lý và đơn thuốc đang dùng để AI cảnh báo tương tác ngay khi bạn quét món.',
                style: TextStyle(color: _muted, fontSize: 12),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...a.map(
                    (e) => Chip(
                      avatar: const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFFD32F2F),
                      ),
                      label: Text(e),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ...c.map(
                    (e) => Chip(
                      avatar: const Icon(
                        Icons.monitor_heart_rounded,
                        size: 16,
                        color: _primary,
                      ),
                      label: Text(e),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ...m.map(
                    (e) => Chip(
                      avatar: const Icon(
                        Icons.medication_rounded,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                      label: Text(e),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryDark,
                  side: BorderSide(color: _primary.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _openMedicalOcr,
                icon: const Icon(Icons.document_scanner_rounded, size: 18),
                label: const Text(
                  'Quét Đơn thuốc / Phiếu xét nghiệm máu (AI OCR)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}