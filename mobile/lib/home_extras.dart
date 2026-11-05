import 'dart:convert';

import 'package:flutter/material.dart';
import 'auth_http.dart' as http;
import 'core/nutrition_calc.dart';

const Color _primary = Color(0xFF10B981);
const Color _primaryDark = Color(0xFF059669);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _water = Color(0xFF0EA5E9);

BoxDecoration _cardDecoration() => BoxDecoration(
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
// MACRO TARGET BARS
// ============================================================

/// Thanh tien do Dam/Beo/Carb thong nhat theo NutritionCalculator (1.8g/kg dam, 25% beo).
class MacroTargetBars extends StatelessWidget {
  final double protein;
  final double fat;
  final double carbs;
  final double goalKcal;
  final double? weightKg;

  const MacroTargetBars({
    super.key,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.goalKcal,
    this.weightKg,
  });

  @override
  Widget build(BuildContext context) {
    final targets = NutritionCalculator.calculateTargetsForMacroBars(
      goalKcal: goalKcal,
      weightKg: weightKg,
    );
    final targetProtein = targets.proteinG;
    final targetFat = targets.fatG;
    final targetCarbs = targets.carbsG;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dinh dưỡng so với mục tiêu',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _bar('Đạm', protein, targetProtein, const Color(0xFF5B7BC0)),
          _bar('Béo', fat, targetFat, const Color(0xFFC9A55C)),
          _bar('Carb', carbs, targetCarbs, const Color(0xFF2E8B74)),
        ],
      ),
    );
  }

  Widget _bar(String label, double value, double target, Color color) {
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} g',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 9,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WATER TRACKER
// ============================================================

class WaterTrackerCard extends StatefulWidget {
  final String baseUrl;
  final String userKey;

  const WaterTrackerCard({
    super.key,
    required this.baseUrl,
    required this.userKey,
  });

  @override
  State<WaterTrackerCard> createState() => _WaterTrackerCardState();
}

class _WaterTrackerCardState extends State<WaterTrackerCard> {
  int todayMl = 0;
  int goalMl = 2000;
  List<int> history = List.filled(7, 0);
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> data) {
    setState(() {
      failed = false;
      todayMl = (data['today_ml'] as num?)?.toInt() ?? 0;
      goalMl = (data['goal_ml'] as num?)?.toInt() ?? 2000;
      history = ((data['history'] as List?) ?? [])
          .map<int>((e) => (e['ml'] as num).toInt())
          .toList();
    });
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/water/${widget.userKey}'),
      );

      if (mounted) {
        _apply(jsonDecode(res.body));
      }
    } catch (_) {
      if (mounted) {
        setState(() => failed = true);
      }
    }
  }

  Future<void> _add(int ml) async {
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/water/${widget.userKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ml': ml}),
      );

      if (mounted) {
        _apply(jsonDecode(res.body));
      }
    } catch (_) {
      if (mounted) {
        setState(() => failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = goalMl <= 0 ? 0.0 : (todayMl / goalMl).clamp(0.0, 1.0);
    final maxHist = history.fold<int>(goalMl, (m, e) => e > m ? e : m);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _water.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.water_drop_rounded, color: _water),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Nước uống hôm nay',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '$todayMl / $goalMl ml',
                style: const TextStyle(
                  color: _water,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: _water,
                backgroundColor: _water.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _chip('+250 ml', () => _add(250)),
              const SizedBox(width: 8),
              _chip('+500 ml', () => _add(500)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Hoàn tác 250 ml',
                onPressed: todayMl > 0 ? () => _add(-250) : null,
                icon: const Icon(Icons.undo_rounded),
                color: _muted,
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: history.map((ml) {
                    final h = maxHist <= 0 ? 4.0 : 4 + 28 * (ml / maxHist);

                    return Container(
                      width: 6,
                      height: h,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: _water.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          if (failed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Không kết nối được máy chủ.',
                style: TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          color: _water,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      backgroundColor: _water.withValues(alpha: 0.10),
      side: BorderSide.none,
      onPressed: onTap,
    );
  }
}

// ============================================================
// SUGGESTIONS
// ============================================================

class SuggestionsCard extends StatefulWidget {
  final String baseUrl;
  final String userKey;
  final double remainingKcal;

  const SuggestionsCard({
    super.key,
    required this.baseUrl,
    required this.userKey,
    required this.remainingKcal,
  });

  @override
  State<SuggestionsCard> createState() => _SuggestionsCardState();
}

class _SuggestionsCardState extends State<SuggestionsCard> {
  List<Map<String, dynamic>> items = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SuggestionsCard old) {
    super.didUpdateWidget(old);

    if ((old.remainingKcal - widget.remainingKcal).abs() > 20) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${widget.baseUrl}/api/suggest?user_key=${widget.userKey}'
          '&remaining=${widget.remainingKcal.round()}',
        ),
      );

      final list = (jsonDecode(res.body)['suggestions'] as List)
          .cast<Map<String, dynamic>>();

      if (mounted) {
        setState(() {
          items = list;
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => loaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loaded && items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.remainingKcal > 0
              ? 'Gợi ý cho ${widget.remainingKcal.round()} kcal còn lại'
              : 'Gợi ý món nhẹ bụng',
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ưu tiên nhiều đạm, đã loại món bạn dị ứng.',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: !loaded
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final f = items[i];

                    return Container(
                      width: 150,
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${f['name_vi']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(f['calories'] as num).round()} kcal · '
                            '${(f['protein_g'] as num).round()}g đạm',
                            style: const TextStyle(
                              color: _primaryDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================
// CALORIE GOAL CALCULATOR (BMI + TDEE)
// ============================================================

Future<void> showCalorieGoalDialog(
  BuildContext context, {
  required double? heightCm,
  required double? weightKg,
  required double currentGoal,
  required void Function(double goal) onApply,
}) {
  int age = 25;
  String gender = 'male';
  double activity = 1.375;
  int adjust = 0; // -500 giam can, 0 giu, +300 tang

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final hasBody = heightCm != null && weightKg != null;

        double bmi = 0;
        double goal = currentGoal;

        if (hasBody) {
          final m = heightCm / 100;
          bmi = weightKg / (m * m);

          final bmr =
              10 * weightKg +
              6.25 * heightCm -
              5 * age +
              (gender == 'male' ? 5 : -161);

          goal = (bmr * activity + adjust).clamp(1200, 5000).toDouble();
        }

        String bmiLabel() {
          if (bmi < 18.5) return 'Thiếu cân';
          if (bmi < 23) return 'Bình thường';
          if (bmi < 25) return 'Thừa cân nhẹ';
          return 'Thừa cân / béo phì';
        }

        return AlertDialog(
          title: const Text('Tính mục tiêu calo'),
          content: SingleChildScrollView(
            child: !hasBody
                ? const Text(
                    'Hãy nhập chiều cao và cân nặng ở tab Hồ sơ trước.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BMI: ${bmi.toStringAsFixed(1)} (${bmiLabel()})',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: '$age',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Tuổi'),
                        onChanged: (v) {
                          final n = int.tryParse(v);

                          if (n != null && n > 5 && n < 100) {
                            setLocal(() => age = n);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'male', label: Text('Nam')),
                          ButtonSegment(value: 'female', label: Text('Nữ')),
                        ],
                        selected: {gender},
                        onSelectionChanged: (s) =>
                            setLocal(() => gender = s.first),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<double>(
                        initialValue: activity,
                        decoration: const InputDecoration(
                          labelText: 'Mức vận động',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 1.2,
                            child: Text('Ít vận động'),
                          ),
                          DropdownMenuItem(
                            value: 1.375,
                            child: Text('Nhẹ (1-3 buổi/tuần)'),
                          ),
                          DropdownMenuItem(
                            value: 1.55,
                            child: Text('Vừa (3-5 buổi/tuần)'),
                          ),
                          DropdownMenuItem(
                            value: 1.725,
                            child: Text('Nhiều (6-7 buổi/tuần)'),
                          ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => activity = v ?? activity),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: -500, label: Text('Giảm')),
                          ButtonSegment(value: 0, label: Text('Giữ')),
                          ButtonSegment(value: 300, label: Text('Tăng')),
                        ],
                        selected: {adjust},
                        onSelectionChanged: (s) =>
                            setLocal(() => adjust = s.first),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Mục tiêu đề xuất: ${goal.round()} kcal/ngày',
                        style: const TextStyle(
                          color: _primaryDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            if (hasBody)
              FilledButton(
                onPressed: () {
                  onApply(goal.roundToDouble());
                  Navigator.pop(ctx);
                },
                child: const Text('Áp dụng'),
              ),
          ],
        );
      },
    ),
  );
}
