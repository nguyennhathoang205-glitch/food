import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth_http.dart' as http;
import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_session.dart';
import '../../core/day_stats.dart';
import '../../core/nutrition_calc.dart';
import '../../models/models.dart';
import '../../services/meal_service.dart';

// ============================================================
// STATISTICS SCREEN
// ============================================================

class StatisticsScreen extends StatelessWidget {
  final List<MealEntry> entries;
  final UserProfile profile;
  final Future<void> Function(MealEntry)? onAddMeal;
  final Future<void> Function(UserProfile)? onSaveProfile;

  const StatisticsScreen({
    super.key,
    required this.entries,
    required this.profile,
    this.onAddMeal,
    this.onSaveProfile,
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
    final macroTargets = NutritionCalculator.calculateTargetsForMacroBars(
      goalKcal: profile.dailyGoal,
      weightKg: profile.weightKg,
    );
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
                'Thống kê dinh dưỡng',
                style: TextStyle(
                  color: accent,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hành trình ăn uống & sức khỏe 7 ngày qua của bạn 🌱',
                style: TextStyle(
                  color: Color(0xFF047857),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '✨ Trung bình mỗi ngày có ghi',
                            style: TextStyle(
                              color: Color(0xFFECFDF5),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${average.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeDays == 0
                                ? 'Hãy ghi bữa ăn đầu tiên để xem thống kê tuần nhé!'
                                : 'Đã ghi $activeDays/7 ngày · Mục tiêu ${profile.dailyGoal.toStringAsFixed(0)} kcal/ngày',
                            style: const TextStyle(
                              color: Color(0xFFD1FAE5),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_graph_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Đưa biểu đồ Calo 7 ngày & Tổng tuần lên ngay đầu màn Thống kê
              const Text(
                'Biểu đồ Calo 7 ngày',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 235,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          const topPad = 16.0;
                          const bottomPad = 22.0;
                          final usable = box.maxHeight - topPad - bottomPad;
                          final ratio = chartMaximum <= 0
                              ? 0.0
                              : (profile.dailyGoal / chartMaximum).clamp(
                                  0.0,
                                  1.0,
                                );
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
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.local_fire_department_rounded,
                      title: 'Tổng Calo tuần',
                      value: weeklyCalories.toStringAsFixed(0),
                      unit: 'kcal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.egg_alt_rounded,
                      title: 'Tổng Đạm',
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
                      title: 'Tổng Chất béo',
                      value: weeklyFat.toStringAsFixed(1),
                      unit: 'g',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatisticCard(
                      icon: Icons.grain_rounded,
                      title: 'Tổng Carb',
                      value: weeklyCarbs.toStringAsFixed(1),
                      unit: 'g',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _WeightTrajectoryCard(
                initialWeightKg: profile.weightKg ?? 65.0,
                dailyGoal: profile.dailyGoal,
                avgDailyCalories: activeDays == 0
                    ? profile.dailyGoal
                    : average,
                onWeightUpdated: (newW) {
                  onSaveProfile?.call(
                    UserProfile(
                      userKey: profile.userKey,
                      displayName: profile.displayName,
                      heightCm: profile.heightCm,
                      weightKg: newW,
                      dailyGoal: profile.dailyGoal,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _WeeklyBadgesCard(
                activeDays: activeDays,
                avgCalories: average,
                dailyGoal: profile.dailyGoal,
                weeklyProtein: weeklyProtein,
                targetProteinG: macroTargets.proteinG,
                streakDays: DayStats.streak(DayStats.caloriesByDay(entries)),
              ),
              const SizedBox(height: 16),
              // Cụm Công cụ Phân tích & Báo cáo AI thiết kế dạng lưới 2x2 gọn đẹp
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_mosaic_rounded,
                          size: 18,
                          color: primaryDark,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Công cụ Phân tích & Báo cáo AI',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                                  builder: (_) => WeeklyMealPlanSheet(
                                    dailyGoal: profile.dailyGoal,
                                    onAddMeal: onAddMeal,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.calendar_month_rounded,
                                size: 17,
                              ),
                              label: const Text(
                                'Thực đơn 7 ngày',
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
                                foregroundColor: const Color(0xFF7C3AED),
                                side: const BorderSide(
                                  color: Color(0xFFDDD6FE),
                                  width: 1.2,
                                ),
                                backgroundColor: const Color(0xFFF5F3FF),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                                size: 17,
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
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
                                backgroundColor: const Color(0xFFF8FAFC),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) =>
                                      const WeeklyClinicalReportDialog(),
                                );
                              },
                              icon: const Icon(
                                Icons.assignment_turned_in_rounded,
                                color: primaryDark,
                                size: 17,
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryDark,
                                side: const BorderSide(
                                  color: Color(0xFFA7F3D0),
                                  width: 1.2,
                                ),
                                backgroundColor: const Color(0xFFECFDF5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => const AiMetricsDialog(),
                                );
                              },
                              icon: const Icon(
                                Icons.analytics_rounded,
                                color: primary,
                                size: 17,
                              ),
                              label: const Text(
                                'Chỉ số mô hình AI',
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
  final Future<void> Function(MealEntry)? onAddMeal;

  const WeeklyMealPlanSheet({
    super.key,
    required this.dailyGoal,
    this.onAddMeal,
  });

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
    final entry = MealEntry(
      name: '${m['name_vi']}',
      mealType: '${m['meal_type']}',
      time: DateTime.now(),
      portionG: (m['portion_g'] as num?)?.toInt() ?? 300,
      calories: (m['calories'] as num?)?.toDouble() ?? 0,
      proteinG: (m['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (m['fat_g'] as num?)?.toDouble() ?? 0,
      carbsG: (m['carbs_g'] as num?)?.toDouble() ?? 0,
    );
    bool ok = false;
    if (widget.onAddMeal != null) {
      await widget.onAddMeal!(entry);
      ok = true;
    } else {
      ok = await MealService.createMealLog(
        userKey: AppSession.currentUserKey,
        foodName: entry.name,
        mealType: entry.mealType,
        portionG: entry.portionG,
        calories: entry.calories,
        proteinG: entry.proteinG,
        fatG: entry.fatG,
        carbsG: entry.carbsG,
        baseUrl: AppConfig.baseUrl,
      );
    }
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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Thực Đơn 7 Ngày Cá Nhân Hóa (AI)',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFECFDF5),
                        foregroundColor: primaryDark,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => _SmartGroceryListDialog(days: days),
                        );
                      },
                      icon: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        'Đi chợ 7 ngày',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
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

  Map<String, dynamic> _buildLocalFoodMetrics(Map<String, dynamic> raw) {
    final cal = ((raw['calories'] as num?)?.toDouble() ?? 350.0);
    final pro = ((raw['protein_g'] as num?)?.toDouble() ?? 15.0);
    final fat = ((raw['fat_g'] as num?)?.toDouble() ?? 12.0);
    final carb = ((raw['carbs_g'] as num?)?.toDouble() ?? 45.0);
    final portion = ((raw['portion_g'] as num?)?.toInt() ?? 250);
    final gl = (carb * 0.55 * (1.0 - ((pro + fat) / (carb + pro + fat + 1.0)) * 0.25)).round();
    int score = 75;
    final pRatio = (pro * 4.0) / (cal > 0 ? cal : 1.0);
    final fRatio = (fat * 9.0) / (cal > 0 ? cal : 1.0);
    if (pRatio >= 0.20) score += 10;
    if (fRatio > 0.38) score -= 12;
    if (cal > 600) score -= 10;
    if (cal <= 420) score += 6;
    score = score.clamp(35, 95);
    String grade = 'B';
    if (score >= 82) {
      grade = 'A';
    } else if (score >= 68) {
      grade = 'B';
    } else if (score >= 54) {
      grade = 'C';
    } else {
      grade = 'D';
    }
    return {
      'class_id': raw['class_id'],
      'name_vi': raw['name_vi'] ?? 'Món ăn',
      'portion_g': portion,
      'calories': cal.round(),
      'protein_g': pro,
      'fat_g': fat,
      'carbs_g': carb,
      'glycemic_load': gl,
      'burn_run_min': (cal / 10.0).round(),
      'burn_walk_min': (cal / 5.5).round(),
      'health_score': score,
      'nutri_score': grade,
    };
  }

  void _applyInstantLocalCompare() {
    if (_foodAId == null || _foodBId == null || _foods.isEmpty) return;
    final rawA = _foods.firstWhere(
      (f) => f['class_id'] == _foodAId,
      orElse: () => _foods.first,
    );
    final rawB = _foods.firstWhere(
      (f) => f['class_id'] == _foodBId,
      orElse: () => _foods.last,
    );
    final fa = _buildLocalFoodMetrics(rawA);
    final fb = _buildLocalFoodMetrics(rawB);
    final sa = (fa['health_score'] as int?) ?? 70;
    final sb = (fb['health_score'] as int?) ?? 70;
    final winner = sa >= sb ? 'A' : 'B';
    final winName = winner == 'A' ? fa['name_vi'] : fb['name_vi'];
    _result = {
      'food_a': fa,
      'food_b': fb,
      'winner': winner,
      'verdict': 'Nên ưu tiên $winName vì cân bằng năng lượng và chỉ số đường huyết (GL) tốt hơn.',
    };
  }

  Future<void> _runCompare() async {
    if (_foodAId == null || _foodBId == null) return;
    setState(() {
      _applyInstantLocalCompare();
      _comparing = true;
    });
    final reqA = _foodAId;
    final reqB = _foodBId;
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/foods/compare'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_key': AppSession.currentUserKey,
          'food_a_id': reqA,
          'food_b_id': reqB,
        }),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted && _foodAId == reqA && _foodBId == reqB) {
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
        padding: const EdgeInsets.all(10),
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
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
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
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Nutri $grade',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
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
  final ValueChanged<double>? onWeightUpdated;

  const _WeightTrajectoryCard({
    required this.initialWeightKg,
    required this.dailyGoal,
    required this.avgDailyCalories,
    this.onWeightUpdated,
  });

  @override
  State<_WeightTrajectoryCard> createState() => _WeightTrajectoryCardState();
}

class _WeightTrajectoryCardState extends State<_WeightTrajectoryCard> {
  double? _loggedWeightKg;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _WeightTrajectoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWeightKg != widget.initialWeightKg) {
      _loggedWeightKg = null;
    }
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
      widget.onWeightUpdated?.call(newW);
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

class _WeeklyBadgesCard extends StatelessWidget {
  final int activeDays;
  final double avgCalories;
  final double dailyGoal;
  final double weeklyProtein;
  final double targetProteinG;
  final int streakDays;

  const _WeeklyBadgesCard({
    required this.activeDays,
    required this.avgCalories,
    required this.dailyGoal,
    required this.weeklyProtein,
    required this.targetProteinG,
    required this.streakDays,
  });

  @override
  Widget build(BuildContext context) {
    final bool calOnTarget =
        activeDays > 0 && (avgCalories - dailyGoal).abs() <= dailyGoal * 0.15;
    final double avgProtein = activeDays > 0 ? weeklyProtein / activeDays : 0;
    final int targetP = targetProteinG.round();
    final bool proteinAchieved = activeDays > 0 && avgProtein >= targetP;
    final bool streakAchieved = streakDays >= 3;
    final int unlockedCount = [
      calOnTarget,
      proteinAchieved,
      streakAchieved,
      activeDays >= 5,
    ].where((x) => x).length;

    return Container(
      padding: const EdgeInsets.all(16),
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
                Icons.emoji_events_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Thử Thách & Huy Hiệu Sức Khỏe Tuần',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Đạt $unlockedCount/4',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _badgeItem(
                icon: Icons.track_changes_rounded,
                title: 'Chuẩn TDEE',
                sub: calOnTarget ? 'Đã mở khóa' : 'Sai số ±15%',
                unlocked: calOnTarget,
                color: const Color(0xFF059669),
              ),
              const SizedBox(width: 8),
              _badgeItem(
                icon: Icons.fitness_center_rounded,
                title: 'Đủ Đạm Cơ Bắp',
                sub: '${avgProtein.round()}g / ${targetP}g',
                unlocked: proteinAchieved,
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(width: 8),
              _badgeItem(
                icon: Icons.local_fire_department_rounded,
                title: 'Chuỗi Kiên Trì',
                sub: '$streakDays ngày liên tục',
                unlocked: streakAchieved,
                color: const Color(0xFFEA580C),
              ),
              const SizedBox(width: 8),
              _badgeItem(
                icon: Icons.verified_rounded,
                title: 'Kỷ Luật Tuần',
                sub: '$activeDays/7 ngày ghi',
                unlocked: activeDays >= 5,
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgeItem({
    required IconData icon,
    required String title,
    required String sub,
    required bool unlocked,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: unlocked
              ? color.withValues(alpha: 0.09)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unlocked
                ? color.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: unlocked ? color : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: unlocked ? accent : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: unlocked ? color : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartGroceryListDialog extends StatefulWidget {
  final List<dynamic> days;

  const _SmartGroceryListDialog({required this.days});

  @override
  State<_SmartGroceryListDialog> createState() =>
      _SmartGroceryListDialogState();
}

class _SmartGroceryListDialogState extends State<_SmartGroceryListDialog> {
  final Set<String> _checked = {};

  late final Map<String, List<String>> _categories = _buildCategories();

  Map<String, List<String>> _buildCategories() {
    final dishNames = <String>[];
    for (final d in widget.days) {
      if (d is Map) {
        final meals = (d['meals'] as List?) ?? [];
        for (final m in meals) {
          if (m is Map && m['name_vi'] != null) {
            dishNames.add('${m['name_vi']}');
          }
        }
      }
    }

    return {
      '🥩 Thịt, Cá, Trứng & Đạm (Cho ${dishNames.length} bữa tuần này)': [
        'Ức gà / Thịt gà phi lê: 800g',
        'Thịt bò thăn / bắp bò: 600g',
        'Cá tươi (Cá hồi / Cá lóc / Cá diêu hồng): 700g',
        'Trứng gà ta: 10 quả',
        'Đậu hũ trắng / Đậu hũ non: 4 bìa',
      ],
      '🥬 Rau củ & Trái cây tươi': [
        'Bông cải xanh & Cải thìa: 1 kg',
        'Rau muống / Rau mồng tơi / Xà lách: 1.2 kg',
        'Cà chua, Dưa leo & Cà rốt: 800g',
        'Trái cây ít ngọt (Táo, Ổi, Bưởi, Chuối): 1.5 kg',
      ],
      '🌾 Tinh bột tốt & Ngũ cốc': [
        'Gạo lứt / Gạo trắng nấu cơm: 1.5 kg',
        'Khoai lang mật / Khoai lang tím: 1 kg',
        'Yến mạch cán dẹt & Bánh mì nguyên cám: 1 gói',
        'Bún tươi / Bánh phở tươi: 800g',
      ],
      '🥛 Sữa, Hạt & Gia vị lành mạnh': [
        'Sữa chua không đường / Ít đường: 1 lốc (4 hộp)',
        'Hạt dinh dưỡng (Hạnh nhân, Óc chó, Đậu phộng): 200g',
        'Dầu oliu / Dầu thực vật, Hành tỏi, Gừng, Chanh',
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _categories.values.expand((e) => e).toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.shopping_basket_rounded, color: primaryDark),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Danh Sách Đi Chợ 7 Ngày',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Đã mua ${_checked.length}/${allItems.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: primaryDark,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _categories.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        color: primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...entry.value.map((item) {
                      final done = _checked.contains(item);
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                        activeColor: primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: done,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _checked.add(item);
                            } else {
                              _checked.remove(item);
                            }
                          });
                        },
                        title: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : null,
                            color: done ? const Color(0xFF94A3B8) : accent,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final buf = StringBuffer('🛒 DANH SÁCH ĐI CHỢ 7 NGÀY (FOODSCAN AI)\n');
            for (final e in _categories.entries) {
              buf.writeln('\n${e.key}:');
              for (final item in e.value) {
                final mark = _checked.contains(item) ? '[x]' : '[ ]';
                buf.writeln('  $mark $item');
              }
            }
            await Clipboard.setData(ClipboardData(text: buf.toString()));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã sao chép danh sách đi chợ vào bộ nhớ tạm!'),
                  backgroundColor: primaryDark,
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Sao chép'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: primary),
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

/// Dialog Hien thi Bang Chi so Thuc nghiem AI (YOLOv8s vs YOLO26s Food vs YOLO26s Fruit + Active Learning)
class AiMetricsDialog extends StatefulWidget {
  const AiMetricsDialog({super.key});

  @override
  State<AiMetricsDialog> createState() => _AiMetricsDialogState();
}

class _AiMetricsDialogState extends State<AiMetricsDialog> {
  bool _loading = true;
  int _totalClasses = 88;
  int _foodClasses = 68;
  int _fruitClasses = 20;
  List<Map<String, dynamic>> _benchmarks = [];
  Map<String, dynamic> _activeLearning = {};

  static const List<Map<String, dynamic>> _fallbackBenchmarks = [
    {
      'model': 'YOLOv8s (Baseline, 30% data)',
      'mAP50': 0.7314,
      'mAP50_95': 0.5923,
      'precision': 0.7475,
      'recall': 0.6623,
      'inference_ms_per_image': 4.53,
      'size_mb': 21.5,
    },
    {
      'model': 'YOLO26s Food (68 món Việt)',
      'mAP50': 0.7959,
      'mAP50_95': 0.6582,
      'precision': 0.8260,
      'recall': 0.7186,
      'inference_ms_per_image': 4.43,
      'size_mb': 19.4,
    },
    {
      'model': 'YOLO26s Fruit (20 loại trái cây)',
      'mAP50': 0.7945,
      'mAP50_95': 0.5625,
      'precision': 0.8068,
      'recall': 0.7429,
      'inference_ms_per_image': 4.20,
      'size_mb': 19.4,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.baseUrl}/api/ai/metrics'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = (body['data'] as Map<String, dynamic>?) ?? {};
        final rawBenches = (data['benchmarks'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _totalClasses = (data['total_classes'] as num?)?.toInt() ?? 88;
            _foodClasses = (data['food_classes'] as num?)?.toInt() ?? 68;
            _fruitClasses = (data['fruit_classes'] as num?)?.toInt() ?? 20;
            _benchmarks = rawBenches.isNotEmpty
                ? rawBenches
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
                : _fallbackBenchmarks;
            _activeLearning =
                (data['active_learning'] as Map<String, dynamic>?) ?? {};
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {
      // Fallback ve bang chi so thuc nghiem local khi offline
    }
    if (mounted) {
      setState(() {
        _benchmarks = _fallbackBenchmarks;
        _activeLearning = {
          'total_feedback': 0,
          'exported_yolo_samples': 0,
          'top_corrections': <dynamic>[],
        };
        _loading = false;
      });
    }
  }

  Widget _metricBar(String label, double ratio, Color color) {
    final pct = (ratio * 100).clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (ratio).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalFeedback =
        (_activeLearning['total_feedback'] as num?)?.toInt() ?? 0;
    final exportedSamples =
        (_activeLearning['exported_yolo_samples'] as num?)?.toInt() ?? 0;
    final topCorrections =
        (_activeLearning['top_corrections'] as List?) ?? const [];

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.analytics_rounded, color: primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Thực nghiệm Mô hình AI & Active Learning',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: accent,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tong quan he thong Dual-Model
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14201C), Color(0xFF0F5C4D)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statSummaryCol('Tổng lớp', '$_totalClasses lớp'),
                          _statSummaryCol('Món Việt', '$_foodClasses món'),
                          _statSummaryCol('Trái cây', '$_fruitClasses loại'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Bảng So sánh Hiệu năng Mô hình (Validation Set)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._benchmarks.map((b) {
                      final modelName =
                          b['model']?.toString() ?? 'YOLO Detector';
                      final isYolo26 =
                          modelName.toUpperCase().contains('YOLO26');
                      final map50 = (b['mAP50'] as num?)?.toDouble() ?? 0.0;
                      final map5095 =
                          (b['mAP50_95'] as num?)?.toDouble() ?? 0.0;
                      final prec = (b['precision'] as num?)?.toDouble() ?? 0.0;
                      final rec = (b['recall'] as num?)?.toDouble() ?? 0.0;
                      final ms = (b['inference_ms_per_image'] as num?)
                              ?.toDouble() ??
                          4.4;
                      final sizeMb =
                          (b['size_mb'] as num?)?.toDouble() ?? 19.4;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isYolo26
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isYolo26
                                ? const Color(0xFF86EFAC)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isYolo26
                                      ? Icons.verified_rounded
                                      : Icons.history_rounded,
                                  size: 16,
                                  color: isYolo26
                                      ? primary
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    modelName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                      color: isYolo26 ? primaryDark : accent,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${ms.toStringAsFixed(1)} ms · ${sizeMb.toStringAsFixed(1)} MB',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _metricBar('mAP@50', map50, primary),
                            _metricBar(
                              'mAP@50-95',
                              map5095,
                              const Color(0xFF0284C7),
                            ),
                            _metricBar(
                              'Precision (Độ chính xác)',
                              prec,
                              const Color(0xFF7C3AED),
                            ),
                            _metricBar(
                              'Recall (Độ phủ)',
                              rec,
                              const Color(0xFFD97706),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    // Active Learning Pipeline status
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.model_training_rounded,
                                size: 17,
                                color: Color(0xFFB45309),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Active Learning (Học chủ động từ phản hồi)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• Tổng lượt người dùng hiệu chỉnh nhãn: $totalFeedback mẫu\n'
                            '• Mẫu chuẩn YOLO đã xuất tự động: $exportedSamples ảnh + bounding box',
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: Color(0xFF78350F),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (topCorrections.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: topCorrections.map((c) {
                                final m = c as Map;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${m['name_vi']}: ${m['count']}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _fetchMetrics,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Làm mới'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: primary),
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _statSummaryCol(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFC3D2CC),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
