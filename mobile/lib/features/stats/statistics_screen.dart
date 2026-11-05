import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth_http.dart' as http;
import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_session.dart';
import '../../core/day_stats.dart';
import '../../models/models.dart';
import '../../services/meal_service.dart';

// ============================================================
// STATISTICS SCREEN
// ============================================================

class StatisticsScreen extends StatelessWidget {
  final List<MealEntry> entries;
  final UserProfile profile;

  const StatisticsScreen({
    super.key,
    required this.entries,
    required this.profile,
  });

  DateTime onlyDate(DateTime value) => DayStats.dayOnly(value);

  String dayName(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'T2';
      case DateTime.tuesday:
        return 'T3';
      case DateTime.wednesday:
        return 'T4';
      case DateTime.thursday:
        return 'T5';
      case DateTime.friday:
        return 'T6';
      case DateTime.saturday:
        return 'T7';
      default:
        return 'CN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = onlyDate(DateTime.now());
    final dates = List.generate(
      7,
      (index) => now.subtract(Duration(days: 6 - index)),
    );

    final List<double> caloriesPerDay = [];
    double weeklyCalories = 0;
    double weeklyProtein = 0;
    double weeklyFat = 0;
    double weeklyCarbs = 0;
    int activeDays = 0;

    for (final date in dates) {
      final dayMeals = entries.where((meal) => onlyDate(meal.time) == date);
      final dayCalories = dayMeals.fold<double>(
        0,
        (sum, meal) => sum + meal.calories,
      );

      if (dayCalories > 0) {
        activeDays++;
      }

      caloriesPerDay.add(dayCalories);
    }

    final weekStart = dates.first;
    final weekEntries = entries.where((meal) {
      final date = onlyDate(meal.time);
      return !date.isBefore(weekStart) && !date.isAfter(now);
    }).toList();

    weeklyCalories = weekEntries.fold(0, (sum, e) => sum + e.calories);
    weeklyProtein = weekEntries.fold(0, (sum, e) => sum + e.proteinG);
    weeklyFat = weekEntries.fold(0, (sum, e) => sum + e.fatG);
    weeklyCarbs = weekEntries.fold(0, (sum, e) => sum + e.carbsG);

    // Chia cho so ngay CO GHI (dung chung DayStats voi Trang chu), khong
    // chia 7: ngay khong ghi la thieu du lieu, khong phai an 0 kcal.
    final average = activeDays == 0 ? 0.0 : weeklyCalories / activeDays;
    final maxCalories = caloriesPerDay.isEmpty
        ? profile.dailyGoal
        : caloriesPerDay.reduce(math.max);
    final chartMaximum = math.max(profile.dailyGoal, maxCalories);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
            children: [
              const Text(
                'Thống kê',
                style: TextStyle(
                  color: accent,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Tổng quan dinh dưỡng 7 ngày gần đây',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF123A31), Color(0xFF07201B)],
                  ),
                  borderRadius: BorderRadius.circular(27),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trung bình mỗi ngày có ghi',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${average.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 27,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            activeDays == 0
                                ? 'Chưa có dữ liệu tuần này'
                                : 'Tính trên $activeDays/7 ngày có ghi · mục tiêu ${profile.dailyGoal.toStringAsFixed(0)} kcal',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.43),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.insights_rounded,
                        color: gold,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _WeightTrajectoryCard(
                initialWeightKg: profile.weightKg ?? 65.0,
                dailyGoal: profile.dailyGoal,
                avgDailyCalories: activeDays == 0
                    ? profile.dailyGoal
                    : average,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) =>
                          WeeklyMealPlanSheet(dailyGoal: profile.dailyGoal),
                    );
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text(
                    'Lập Thực Đơn 7 Ngày bằng AI (Theo TDEE & Bệnh lý)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7C3AED),
                          side: const BorderSide(
                            color: Color(0xFFDDD6FE),
                            width: 1.2,
                          ),
                          backgroundColor: const Color(0xFFF5F3FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const FoodComparisonDialog(),
                          );
                        },
                        icon: const Icon(
                          Icons.balance_rounded,
                          color: Color(0xFF7C3AED),
                          size: 18,
                        ),
                        label: const Text(
                          'So sánh 2 món',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: const BorderSide(
                            color: Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const WeeklyClinicalReportDialog(),
                          );
                        },
                        icon: const Icon(
                          Icons.assignment_turned_in_rounded,
                          color: primaryDark,
                          size: 18,
                        ),
                        label: const Text(
                          'Báo cáo & CSV',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A8A),
                    side: const BorderSide(
                      color: Color(0xFFBFDBFE),
                      width: 1.2,
                    ),
                    backgroundColor: const Color(0xFFEFF6FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AiModelMetricsDialog(),
                    );
                  },
                  icon: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: Color(0xFF2563EB),
                    size: 18,
                  ),
                  label: const Text(
                    'Chỉ Số Thực Nghiệm Mô Hình AI & Active Learning',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Calo 7 ngày',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 245,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Stack(
                  children: [
                    // Duong muc tieu calo: nhin cot la biet an thieu/du/vuot
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          // Cot ve trong vung: tru o so (12+4) phia tren va nhan ngay (8+14) phia duoi
                          const topPad = 16.0;
                          const bottomPad = 22.0;
                          final usable = box.maxHeight - topPad - bottomPad;
                          final ratio = chartMaximum <= 0
                              ? 0.0
                              : (profile.dailyGoal / chartMaximum).clamp(0.0, 1.0);
                          final y = topPad + usable * (1 - ratio);
                          return Stack(
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: y,
                                child: Container(
                                  height: 1.5,
                                  color: gold.withValues(alpha: 0.7),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: y - 16,
                                child: Text(
                                  'Mục tiêu ${profile.dailyGoal.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(7, (index) {
                        final value = caloriesPerDay[index];
                        final double percentage = chartMaximum <= 0
                            ? 0
                            : (value / chartMaximum).clamp(0.0, 1.0).toDouble();

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  value == 0 ? '' : value.toStringAsFixed(0),
                                  style: TextStyle(
                                    color: accent.withValues(alpha: 0.5),
                                    fontSize: 8,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: math.max(
                                        percentage,
                                        value > 0 ? 0.05 : 0,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [primary, primaryDark],
                                          ),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  dayName(dates[index]),
                                  style: TextStyle(
                                    color: accent.withValues(alpha: 0.45),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Tổng tuần',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.local_fire_department_rounded,
                      title: 'Calo',
                      value: weeklyCalories.toStringAsFixed(0),
                      unit: 'kcal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.egg_alt_rounded,
                      title: 'Đạm',
                      value: weeklyProtein.toStringAsFixed(1),
                      unit: 'g',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.opacity_rounded,
                      title: 'Chất béo',
                      value: weeklyFat.toStringAsFixed(1),
                      unit: 'g',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.grain_rounded,
                      title: 'Carb',
                      value: weeklyCarbs.toStringAsFixed(1),
                      unit: 'g',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_graph_rounded, color: primaryDark),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        activeDays == 0
                            ? 'Chưa có đủ dữ liệu. Hãy thêm các bữa ăn để hệ thống tạo thống kê.'
                            : 'Bạn đã ghi nhận bữa ăn trong $activeDays ngày của tuần này.',
                        style: const TextStyle(
                          color: accent,
                          height: 1.5,
                          fontSize: 12,
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
    );
  }
}

class WeeklyMealPlanSheet extends StatefulWidget {
  final double dailyGoal;

  const WeeklyMealPlanSheet({super.key, required this.dailyGoal});

  @override
  State<WeeklyMealPlanSheet> createState() => _WeeklyMealPlanSheetState();
}

class _WeeklyMealPlanSheetState extends State<WeeklyMealPlanSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _plan;
  int _selectedDay = 0;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/meal-plan/weekly'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'daily_goal': widget.dailyGoal}),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && body['status'] == 'ok') {
        setState(() {
          _plan = body['plan'] as Map<String, dynamic>?;
          _loading = false;
        });
      } else {
        setState(() {
          _error = body['message']?.toString() ?? 'Không tạo được thực đơn';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi kết nối: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _logMeal(Map<String, dynamic> m) async {
    final ok = await MealService.createMealLog(
      userKey: AppSession.currentUserKey,
      foodName: '${m['name_vi']}',
      mealType: '${m['meal_type']}',
      portionG: (m['portion_g'] as num?)?.toInt() ?? 300,
      calories: (m['calories'] as num?)?.toDouble() ?? 0,
      proteinG: (m['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (m['fat_g'] as num?)?.toDouble() ?? 0,
      carbsG: (m['carbs_g'] as num?)?.toDouble() ?? 0,
      baseUrl: AppConfig.baseUrl,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Đã ghi "${m['name_vi']}" vào nhật ký!'
                : 'Không thể lưu món ăn',
          ),
          backgroundColor: ok ? primary : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = (_plan?['days'] as List?) ?? [];
    final notes = (_plan?['clinical_notes'] as List?) ?? [];
    final currentDay =
        days.isNotEmpty && _selectedDay < days.length ? days[_selectedDay] : null;
    final meals = (currentDay?['meals'] as List?) ?? [];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                const Text(
                  'Thực Đơn 7 Ngày Cá Nhân Hóa (AI)',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                ...notes.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('✨ ', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Text(
                            '$n',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(days.length, (i) {
                      final d = days[i];
                      final sel = i == _selectedDay;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${d['day']}'),
                          selected: sel,
                          selectedColor: primary,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          onSelected: (_) => setState(() => _selectedDay = i),
                        ),
                      );
                    }),
                  ),
                ),
                if (currentDay != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${currentDay['day']} — ${currentDay['focus']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Đạm: ${currentDay['total_protein_g']}g · Béo: ${currentDay['total_fat_g']}g · Carb: ${currentDay['total_carbs_g']}g',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${currentDay['total_calories']} kcal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...meals.map((m) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['meal_type']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${m['name_vi']}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '~${m['portion_g']}g · ${m['calories']} kcal (P: ${m['protein_g']}g · F: ${m['fat_g']}g · C: ${m['carbs_g']}g)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ghi món này vào nhật ký hôm nay',
                            color: primary,
                            onPressed: () =>
                                _logMeal(Map<String, dynamic>.from(m)),
                            icon: const Icon(Icons.add_circle_rounded),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }
}

class WeeklyClinicalReportDialog extends StatefulWidget {
  const WeeklyClinicalReportDialog({super.key});

  @override
  State<WeeklyClinicalReportDialog> createState() =>
      _WeeklyClinicalReportDialogState();
}

class _WeeklyClinicalReportDialogState
    extends State<WeeklyClinicalReportDialog> {
  bool _loading = true;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/report/weekly/${AppSession.currentUserKey}',
        ),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (mounted && res.statusCode == 200) {
        setState(() {
          _report = body['report'] as Map<String, dynamic>?;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatTextReport(Map<String, dynamic> r) {
    final hp = (r['health_profile'] as Map<String, dynamic>?) ?? {};
    final recs = ((r['recommendations'] as List?) ?? []).join('\n- ');
    return '=== BÁO CÁO DINH DƯỠNG & Y KHOA 7 NGÀY (FOODSCAN AI) ===\n'
        'Người dùng: ${r['display_name']}\n'
        'Ngày xuất: ${r['generated_at']}\n'
        'Số ngày ghi nhận: ${r['logged_days']}/7 ngày (${r['total_meals_logged']} bữa)\n'
        'Calo trung bình: ${r['average_daily_calories']} / ${r['daily_goal']} kcal (${r['adherence_percent']}%)\n'
        'Tổng Đạm: ${r['total_protein_g']}g | Béo: ${r['total_fat_g']}g | Carb: ${r['total_carbs_g']}g\n'
        'Nước uống TB: ${r['average_water_ml']} ml/ngày\n'
        'Bệnh lý nền: ${((hp['conditions'] as List?) ?? []).join(', ')}\n'
        'Thuốc đang dùng: ${((hp['medications'] as List?) ?? []).join(', ')}\n'
        'Khuyến nghị lâm sàng:\n- $recs';
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return AlertDialog(
      title: const Text('Báo Cáo Dinh Dưỡng & Y Khoa 7 Ngày'),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            : r == null
            ? const Text('Không tải được báo cáo tuần.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hồ sơ: ${r['display_name']} (${r['generated_at']})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    const Divider(height: 18),
                    Text(
                      '• Số ngày có ghi nhật ký: ${r['logged_days']}/7 ngày (${r['total_meals_logged']} bữa)',
                    ),
                    Text(
                      '• Trung bình Calo: ${r['average_daily_calories']} / ${r['daily_goal']} kcal (${r['adherence_percent']}%)',
                    ),
                    Text(
                      '• Tổng Macro tuần: Đạm ${r['total_protein_g']}g · Béo ${r['total_fat_g']}g · Carb ${r['total_carbs_g']}g',
                    ),
                    Text(
                      '• Trung bình nước uống: ${r['average_water_ml']} ml/ngày',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Đánh giá & Khuyến nghị từ AI:',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: primaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...((r['recommendations'] as List?) ?? []).map(
                      (rec) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $rec',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showDialog<void>(
              context: context,
              builder: (_) => const CsvExportDialog(),
            );
          },
          icon: const Icon(Icons.table_chart_outlined, size: 17),
          label: const Text('Xuất bảng .CSV (Excel)'),
        ),
        if (r != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: primary),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _formatTextReport(r)),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép báo cáo tuần vào bộ nhớ tạm!'),
                    backgroundColor: primary,
                  ),
                );
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.copy_all_rounded, size: 18),
            label: const Text('Sao chép báo cáo'),
          ),
      ],
    );
  }
}

class CsvExportDialog extends StatefulWidget {
  const CsvExportDialog({super.key});

  @override
  State<CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<CsvExportDialog> {
  bool _loading = true;
  String _csv = '';
  int _count = 0;
  int _totalCalories = 0;
  String _filename = 'nhat_ky_dinh_duong.csv';

  @override
  void initState() {
    super.initState();
    _loadCsv();
  }

  Future<void> _loadCsv() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/export/meals-csv/${AppSession.currentUserKey}',
        ),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _csv = '${body['csv'] ?? ''}';
            _count = (body['count'] as num?)?.toInt() ?? 0;
            _totalCalories = (body['total_calories'] as num?)?.toInt() ?? 0;
            _filename = '${body['filename'] ?? 'nhat_ky_dinh_duong.csv'}';
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Xuất Dữ Liệu Nhật Ký (.CSV Excel)'),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tệp: $_filename · $_count bữa ăn · Tổng $_totalCalories kcal',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 210,
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _csv.isEmpty ? 'Chưa có dữ liệu bữa ăn.' : _csv,
                        style: const TextStyle(
                          color: Color(0xFFA7F3D0),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mẹo: Bấm "Sao chép CSV" rồi dán thẳng vào Excel hoặc Google Sheets để tạo bảng thống kê.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: primary),
          onPressed: _csv.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: _csv));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã sao chép $_count dòng CSV ($_filename) vào bộ nhớ tạm!',
                        ),
                        backgroundColor: primary,
                      ),
                    );
                    Navigator.pop(context);
                  }
                },
          icon: const Icon(Icons.download_done_rounded, size: 18),
          label: const Text('Sao chép chuẩn CSV'),
        ),
      ],
    );
  }
}

class FoodComparisonDialog extends StatefulWidget {
  const FoodComparisonDialog({super.key});

  @override
  State<FoodComparisonDialog> createState() => _FoodComparisonDialogState();
}

class _FoodComparisonDialogState extends State<FoodComparisonDialog> {
  bool _loadingCatalog = true;
  bool _comparing = false;
  List<Map<String, dynamic>> _foods = [];
  int? _foodAId;
  int? _foodBId;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/foods/catalog'),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final list = ((body['foods'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        if (mounted && list.isNotEmpty) {
          setState(() {
            _foods = list;
            _foodAId = list.first['class_id'] as int?;
            _foodBId = list.length > 1
                ? list[1]['class_id'] as int?
                : _foodAId;
            _loadingCatalog = false;
          });
          _runCompare();
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCatalog = false);
  }

  Future<void> _runCompare() async {
    if (_foodAId == null || _foodBId == null) return;
    setState(() => _comparing = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/foods/compare'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_key': AppSession.currentUserKey,
          'food_a_id': _foodAId,
          'food_b_id': _foodBId,
        }),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _result = body as Map<String, dynamic>;
            _comparing = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _comparing = false);
  }

  Widget _buildFoodCol(Map<String, dynamic> f, bool isWinner) {
    final grade = '${f['nutri_score'] ?? 'B'}';
    final score = f['health_score'] ?? 75;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWinner ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
            width: isWinner ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isWinner ? primary : const Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isWinner ? '🏆 TỐT HƠN' : 'ĐỐI CHIẾU',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Nutri $grade',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: primaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${f['name_vi'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '🔥 ${f['calories']} kcal (~${f['portion_g']}g)',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: Color(0xFFE11D48),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Đạm: ${f['protein_g']}g · Béo: ${f['fat_g']}g\nCarb: ${f['carbs_g']}g · GL: ${f['glycemic_load']}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF334155),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '🏃 Đốt: ${f['burn_run_min']}p chạy / ${f['burn_walk_min']}p đi bộ',
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Điểm sức khỏe: $score/100',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fa = _result?['food_a'] as Map<String, dynamic>?;
    final fb = _result?['food_b'] as Map<String, dynamic>?;
    final winner = '${_result?['winner'] ?? 'A'}';

    return AlertDialog(
      title: const Text('So Sánh 2 Món Ăn (Food Vs. Food)'),
      content: SizedBox(
        width: 460,
        child: _loadingCatalog
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chọn 2 món ăn bất kỳ để AI đặt lên bàn cân dinh dưỡng & đối chiếu bệnh lý của bạn:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _foodAId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Món thứ 1 (Món A)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: _foods
                          .map(
                            (f) => DropdownMenuItem<int>(
                              value: f['class_id'] as int,
                              child: Text(
                                '${f['name_vi']} (${f['calories']} kcal)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _foodAId = v);
                          _runCompare();
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _foodBId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Món thứ 2 (Món B)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: _foods
                          .map(
                            (f) => DropdownMenuItem<int>(
                              value: f['class_id'] as int,
                              child: Text(
                                '${f['name_vi']} (${f['calories']} kcal)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _foodBId = v);
                          _runCompare();
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_comparing)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(color: primary),
                        ),
                      )
                    else if (fa != null && fb != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFoodCol(fa, winner == 'A'),
                          const SizedBox(width: 8),
                          _buildFoodCol(fb, winner == 'B'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFF34D399),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_result?['verdict'] ?? ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class StatisticCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String unit;

  const StatisticCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primaryDark, size: 19),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: accent.withValues(alpha: 0.45),
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value $unit',
            style: const TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightTrajectoryCard extends StatefulWidget {
  final double initialWeightKg;
  final double dailyGoal;
  final double avgDailyCalories;

  const _WeightTrajectoryCard({
    required this.initialWeightKg,
    required this.dailyGoal,
    required this.avgDailyCalories,
  });

  @override
  State<_WeightTrajectoryCard> createState() => _WeightTrajectoryCardState();
}

class _WeightTrajectoryCardState extends State<_WeightTrajectoryCard> {
  double? _loggedWeightKg;

  @override
  void initState() {
    super.initState();
    _fetchWeight();
  }

  Future<void> _fetchWeight() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/weight/${AppSession.currentUserKey}?avg_calories=${widget.avgDailyCalories}&daily_goal=${widget.dailyGoal}&current_weight_kg=${widget.initialWeightKg}',
        ),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final forecast = body['forecast'] as Map<String, dynamic>?;
        final w = (forecast?['current_weight_kg'] as num?)?.toDouble();
        if (mounted && w != null) {
          setState(() => _loggedWeightKg = w);
        }
      }
    } catch (_) {}
  }

  Future<void> _promptUpdateWeight(double currentW) async {
    final ctrl = TextEditingController(text: currentW.toStringAsFixed(1));
    final newW = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi nhận cân nặng hôm nay'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Cân nặng (kg)',
            suffixText: 'kg',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: primary),
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, v);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newW != null && newW > 20 && newW < 300) {
      setState(() => _loggedWeightKg = newW);
      try {
        await http.post(
          Uri.parse(
            '${AppConfig.baseUrl}/api/weight/${AppSession.currentUserKey}',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'weight_kg': newW}),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentW = _loggedWeightKg ?? widget.initialWeightKg;
    final dailyBalance = widget.avgDailyCalories - widget.dailyGoal;
    final delta30dKg = (dailyBalance * 30.0) / 7700.0;
    final projected30dKg = currentW + delta30dKg;
    final isDeficit = dailyBalance < -80;
    final isSurplus = dailyBalance > 80;
    final badgeColor = isDeficit
        ? const Color(0xFF059669)
        : (isSurplus ? const Color(0xFFD97706) : const Color(0xFF2563EB));
    final trendLabel = isDeficit
        ? 'Xu hướng giảm cân'
        : (isSurplus ? 'Xu hướng tăng cân' : 'Duy trì ổn định');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.monitor_weight_outlined,
                color: primaryDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dự Báo Biến Thiên Cân Nặng 30 Ngày',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: primaryDark,
                ),
                onPressed: () => _promptUpdateWeight(currentW),
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: const Text(
                  'Cập nhật kg',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hiện tại',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${currentW.toStringAsFixed(1)} kg',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.trending_flat_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dự kiến sau 30 ngày',
                        style: TextStyle(
                          fontSize: 11,
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${projected30dKg.toStringAsFixed(1)} kg (${delta30dKg >= 0 ? '+' : ''}${delta30dKg.toStringAsFixed(2)} kg)',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$trendLabel · Chênh lệch năng lượng TB: ${dailyBalance >= 0 ? '+' : ''}${dailyBalance.round()} kcal/ngày (quy đổi 7.700 kcal ≈ 1 kg mô mỡ).',
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF475569),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class AiModelMetricsDialog extends StatefulWidget {
  const AiModelMetricsDialog({super.key});

  @override
  State<AiModelMetricsDialog> createState() => _AiModelMetricsDialogState();
}

class _AiModelMetricsDialogState extends State<AiModelMetricsDialog> {
  bool _loading = true;
  Map<String, dynamic>? _metrics;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/ai/metrics'),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _metrics = body['metrics'] as Map<String, dynamic>?;
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    final models = (m?['benchmarks'] as List?) ?? [];
    final al = (m?['active_learning'] as Map<String, dynamic>?) ?? {};

    return AlertDialog(
      title: const Text('Thực Nghiệm Mô Hình AI & Active Learning'),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: primary)),
              )
            : m == null
            ? const Text('Không tải được dữ liệu thực nghiệm AI.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. So sánh hiệu năng mô hình (${m['total_classes'] ?? 88} lớp: ${m['food_classes'] ?? 68} món ăn + ${m['fruit_classes'] ?? 20} trái cây)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...models.map((item) {
                      final modelName = '${item['model'] ?? item['name'] ?? ''}';
                      final active = modelName.toLowerCase().contains('yolo26');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    modelName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? primary
                                        : const Color(0xFF94A3B8),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    active ? 'Đang chạy' : 'Baseline',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'mAP@50: ${(((item['mAP50'] as num?) ?? 0) * 100).toStringAsFixed(1)}% · mAP@50-95: ${(((item['mAP50_95'] as num?) ?? 0) * 100).toStringAsFixed(1)}% · P: ${(((item['precision'] as num?) ?? 0) * 100).toStringAsFixed(1)}% · R: ${(((item['recall'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: primaryDark,
                              ),
                            ),
                            Text(
                              'Độ trễ: ${item['inference_ms_per_image'] ?? item['inference_ms'] ?? 4.5} ms/ảnh · Kích thước: ${item['size_mb'] ?? 19.5} MB',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 20),
                    const Text(
                      '2. Pipeline Học Chủ Động (Active Learning sang chuẩn YOLO)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Tổng lượt người dùng sửa nhãn: ${al['total_feedback'] ?? 0} lượt',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Mẫu ảnh + nhãn YOLO đã trích xuất: ${al['exported_yolo_samples'] ?? 0} mẫu',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Text(
                      '• Tự động sinh cấu trúc images/train + labels/train + active_data.yaml để Fine-tune mô hình.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Divider(height: 20),
                    const Text(
                      '3. Cơ chế Hybrid YOLO26 + Cross-Model Suppression + Gemini',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• Ngưỡng lọc trùng lặp chéo (Cross-Model IoU Suppression): 0.35\n'
                      '• Ngưỡng chặn nhận diện nhầm trái cây trên đĩa thức ăn nấu chín: 80% confidence',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
