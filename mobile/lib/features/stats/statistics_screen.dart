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

  // Lua chon nguyen lieu / mon muon an rieng cho tung ngay (0..6)
  final Map<int, String> _dayPreferences = {};
  final Map<int, int> _dayVariationSeeds = {};
  final Set<String> _expandedRecipeKeys = {};
  final TextEditingController _customPrefCtrl = TextEditingController();

  static const List<Map<String, String>> _prefOptions = [
    {'id': '', 'label': '✨ Linh hoạt'},
    {'id': 'Thịt gà', 'label': '🐔 Thịt gà'},
    {'id': 'Thịt bò', 'label': '🥩 Thịt bò'},
    {'id': 'Thịt heo', 'label': '🐖 Thịt heo'},
    {'id': 'Cá tươi', 'label': '🐟 Cá tươi'},
    {'id': 'Đậu hũ & Trứng', 'label': '🥚 Đậu hũ & Trứng'},
  ];

  static const Map<String, Map<String, dynamic>> _localPrefPools = {
    'ga': {
      'focus': 'Thực đơn Thịt Gà giàu đạm nạc, ít béo bão hòa',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Phở gà ta ít bánh (bỏ da) + Giá trụng', 'portion_g': 360, 'calories': 420, 'protein_g': 30, 'fat_g': 8, 'carbs_g': 54},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Miến gà nấu nấm hương + Rau thơm', 'portion_g': 350, 'calories': 395, 'protein_g': 28, 'fat_g': 7, 'carbs_g': 52},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Cháo yến mạch ức gà xé + Hành ngò', 'portion_g': 330, 'calories': 380, 'protein_g': 27, 'fat_g': 7, 'carbs_g': 50},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + Ức gà áp chảo sốt tiêu đen + Bông cải xanh luộc', 'portion_g': 400, 'calories': 580, 'protein_g': 42, 'fat_g': 12, 'carbs_g': 72},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + Gà kho gừng sả ít muối + Canh cải ngọt', 'portion_g': 400, 'calories': 590, 'protein_g': 40, 'fat_g': 13, 'carbs_g': 74},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Bún gạo lứt gà nướng mật ong + Salad dưa leo cà chua', 'portion_g': 390, 'calories': 560, 'protein_g': 39, 'fat_g': 11, 'carbs_g': 70},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': 'Ức gà hấp lá chanh + Cơm gạo lứt + Bí xanh luộc', 'portion_g': 370, 'calories': 490, 'protein_g': 38, 'fat_g': 8, 'carbs_g': 64},
        {'meal_type': 'Bữa tối', 'name_vi': 'Gỏi cuốn ức gà rau củ (3 cuốn) + Canh nấm đậu hũ', 'portion_g': 340, 'calories': 450, 'protein_g': 34, 'fat_g': 8, 'carbs_g': 58},
        {'meal_type': 'Bữa tối', 'name_vi': 'Salad ức gà áp chảo + Khoai lang hấp + Súp bí đỏ', 'portion_g': 350, 'calories': 465, 'protein_g': 36, 'fat_g': 9, 'carbs_g': 56},
      ],
    },
    'bo': {
      'focus': 'Thực đơn Thịt Bò bổ máu, giàu Sắt & Kẽm',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Phở bò thăn trần nước trong + Nhiều hành giá', 'portion_g': 380, 'calories': 440, 'protein_g': 31, 'fat_g': 10, 'carbs_g': 55},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bún bò thăn nạc ít mỡ + Rau sống', 'portion_g': 380, 'calories': 455, 'protein_g': 30, 'fat_g': 11, 'carbs_g': 56},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bánh mì nguyên cám kẹp bò áp chảo & xà lách', 'portion_g': 260, 'calories': 415, 'protein_g': 27, 'fat_g': 11, 'carbs_g': 50},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + Thịt bò xào bông cải xanh + Canh bí đao', 'portion_g': 410, 'calories': 600, 'protein_g': 41, 'fat_g': 14, 'carbs_g': 73},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + Bò lúc lắc ớt chuông + Salad rau mầm', 'portion_g': 400, 'calories': 610, 'protein_g': 40, 'fat_g': 15, 'carbs_g': 74},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Bún thịt bò xào sả ớt ít dầu + Dưa leo & rau thơm', 'portion_g': 390, 'calories': 575, 'protein_g': 37, 'fat_g': 13, 'carbs_g': 72},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': 'Thịt bò thăn cuộn nấm kim châm áp chảo + Cơm gạo lứt + Rau luộc', 'portion_g': 370, 'calories': 500, 'protein_g': 36, 'fat_g': 12, 'carbs_g': 62},
        {'meal_type': 'Bữa tối', 'name_vi': 'Canh cải bò băm nấu gừng + Đậu hũ non hấp + 1 chén cơm nhỏ', 'portion_g': 360, 'calories': 475, 'protein_g': 33, 'fat_g': 10, 'carbs_g': 60},
        {'meal_type': 'Bữa tối', 'name_vi': 'Salad bò nướng kiểu Việt + Khoai lang mật hấp', 'portion_g': 350, 'calories': 485, 'protein_g': 35, 'fat_g': 11, 'carbs_g': 58},
      ],
    },
    'heo': {
      'focus': 'Thực đơn Thịt Heo Nạc cân bằng, đậm vị cơm nhà',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bún mọc thịt nạc heo + Rau sống', 'portion_g': 360, 'calories': 425, 'protein_g': 26, 'fat_g': 10, 'carbs_g': 56},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Hủ tiếu thịt heo nạc nước trong + Giá hẹ', 'portion_g': 370, 'calories': 420, 'protein_g': 27, 'fat_g': 9, 'carbs_g': 57},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bánh cuốn nhân thịt heo nạc băm & mộc nhĩ', 'portion_g': 300, 'calories': 405, 'protein_g': 23, 'fat_g': 9, 'carbs_g': 56},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + Thịt thăn heo luộc cuốn rau sống + Canh bí xanh', 'portion_g': 400, 'calories': 585, 'protein_g': 38, 'fat_g': 13, 'carbs_g': 75},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + Sườn heo non rim nhạt + Đậu cô ve luộc', 'portion_g': 400, 'calories': 605, 'protein_g': 37, 'fat_g': 15, 'carbs_g': 74},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Bún thịt heo nướng nạc ít mỡ + Đồ chua & rau thơm', 'portion_g': 380, 'calories': 565, 'protein_g': 34, 'fat_g': 13, 'carbs_g': 72},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': 'Thịt thăn heo áp chảo sả + Cơm gạo lứt + Canh mồng tơi', 'portion_g': 370, 'calories': 495, 'protein_g': 35, 'fat_g': 11, 'carbs_g': 64},
        {'meal_type': 'Bữa tối', 'name_vi': 'Canh bí đỏ nấu thịt heo băm + Đậu phụ luộc + 1 chén cơm', 'portion_g': 360, 'calories': 480, 'protein_g': 28, 'fat_g': 11, 'carbs_g': 66},
        {'meal_type': 'Bữa tối', 'name_vi': 'Bắp cải cuộn thịt nạc heo hấp gừng + Cơm gạo lứt', 'portion_g': 360, 'calories': 470, 'protein_g': 32, 'fat_g': 9, 'carbs_g': 62},
      ],
    },
    'ca': {
      'focus': 'Thực đơn Cá giàu Omega-3, tốt cho tim mạch',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bún cá lóc hấp nghệ + Rau cần & giá đỗ', 'portion_g': 360, 'calories': 410, 'protein_g': 28, 'fat_g': 8, 'carbs_g': 54},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Cháo cá diêu hồng nấu gừng + Hành ngò', 'portion_g': 350, 'calories': 385, 'protein_g': 26, 'fat_g': 7, 'carbs_g': 52},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + Cá hồi áp chảo + Salad dưa leo cà chua', 'portion_g': 390, 'calories': 605, 'protein_g': 40, 'fat_g': 17, 'carbs_g': 68},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + Cá basa kho nghệ ít muối + Canh rau ngót', 'portion_g': 400, 'calories': 580, 'protein_g': 37, 'fat_g': 14, 'carbs_g': 73},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': 'Cá diêu hồng hấp gừng hành + Canh cải ngọt + 1 chén cơm nhỏ', 'portion_g': 380, 'calories': 495, 'protein_g': 36, 'fat_g': 10, 'carbs_g': 62},
        {'meal_type': 'Bữa tối', 'name_vi': 'Cá lóc hấp bầu + Cơm gạo lứt + Rau củ luộc', 'portion_g': 370, 'calories': 485, 'protein_g': 35, 'fat_g': 9, 'carbs_g': 64},
      ],
    },
    'chay': {
      'focus': 'Thực đơn Đậu Hũ, Trứng & Rau Củ thanh đạm, nhẹ bụng',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Khoai lang hấp + 2 quả trứng gà luộc + Sữa hạt', 'portion_g': 300, 'calories': 395, 'protein_g': 19, 'fat_g': 11, 'carbs_g': 53},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bún riêu đậu hũ nấm tươi thanh đạm + Rau sống', 'portion_g': 360, 'calories': 400, 'protein_g': 21, 'fat_g': 9, 'carbs_g': 56},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + Đậu hũ sốt nấm đông cô + Bông cải xanh luộc', 'portion_g': 390, 'calories': 540, 'protein_g': 28, 'fat_g': 12, 'carbs_g': 74},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + Trứng cuộn rau củ + Canh nấm hạt sen', 'portion_g': 380, 'calories': 555, 'protein_g': 29, 'fat_g': 14, 'carbs_g': 72},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': 'Đậu hũ non hấp tương gừng + Rau muống luộc + Cơm gạo lứt', 'portion_g': 360, 'calories': 465, 'protein_g': 25, 'fat_g': 10, 'carbs_g': 66},
        {'meal_type': 'Bữa tối', 'name_vi': 'Miến trộn nấm hương đậu phụ & rau củ thập cẩm', 'portion_g': 350, 'calories': 450, 'protein_g': 24, 'fat_g': 9, 'carbs_g': 65},
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  @override
  void dispose() {
    _customPrefCtrl.dispose();
    super.dispose();
  }

  static Map<String, dynamic> buildLocalRecipeAndShopping(
    String nameVi,
    int portionG,
  ) {
    final low = nameVi.toLowerCase();
    final scale = (portionG / 360.0).clamp(0.7, 1.8);
    int g(num v) => ((v * scale) / 5.0).round() * 5;

    final shopping = <String>[];
    var cookMin = 18;
    var steps = <String>[];

    if (low.contains('gà')) {
      shopping.add('Ức gà / Thịt gà ta lọc da: ${g(160)}g');
    } else if (low.contains('bò')) {
      shopping.add('Thịt bò thăn / bắp bò tươi: ${g(150)}g');
    } else if (low.contains('sườn')) {
      shopping.add('Sườn heo non nhiều nạc: ${g(160)}g');
    } else if (low.contains('heo') ||
        low.contains('lợn') ||
        low.contains('thịt thăn') ||
        low.contains('thịt băm') ||
        low.contains('thịt nướng') ||
        low.contains('mọc')) {
      shopping.add('Thịt thăn heo nạc / mọc heo: ${g(150)}g');
    } else if (low.contains('cá hồi')) {
      shopping.add('Cá hồi phi lê tươi: ${g(150)}g');
    } else if (low.contains('cá')) {
      shopping.add('Cá tươi phi lê (cá lóc / diêu hồng / basa): ${g(160)}g');
    } else if (low.contains('trứng')) {
      shopping.add('Trứng gà ta tươi: 2 quả');
    } else if (low.contains('đậu hũ') || low.contains('đậu phụ')) {
      shopping.add('Đậu hũ non / đậu phụ trắng: ${g(180)}g');
    }

    if (low.contains('nấm')) {
      shopping.add('Nấm hương / nấm đông cô / nấm kim châm: ${g(80)}g');
    }

    if (low.contains('gạo lứt')) {
      shopping.add('Gạo lứt dẻo: ${g(90)}g (nấu thành ~${g(190)}g cơm)');
    } else if (low.contains('cơm')) {
      shopping.add('Gạo trắng thơm: ${g(90)}g (nấu thành ~${g(190)}g cơm)');
    } else if (low.contains('phở')) {
      shopping.add('Bánh phở tươi: ${g(140)}g');
    } else if (low.contains('bún')) {
      shopping.add('Bún tươi sợi nhỏ: ${g(150)}g');
    } else if (low.contains('miến')) {
      shopping.add('Miến dong khô: ${g(65)}g');
    } else if (low.contains('hủ tiếu')) {
      shopping.add('Sợi hủ tiếu dai: ${g(140)}g');
    } else if (low.contains('khoai lang')) {
      shopping.add('Khoai lang mật / khoai lang tím: ${g(180)}g');
    } else if (low.contains('yến mạch')) {
      shopping.add('Yến mạch cán dẹt: ${g(65)}g');
    } else if (low.contains('bánh mì')) {
      shopping.add('Bánh mì nguyên cám / bánh mì giòn: 1 ổ');
    } else if (low.contains('gỏi cuốn') || low.contains('bánh cuốn')) {
      shopping.add('Bánh tráng gạo / bột bánh cuốn & bún tươi: ${g(120)}g');
    }

    if (low.contains('bông cải')) {
      shopping.add('Bông cải xanh (súp lơ): ${g(130)}g');
    } else if (low.contains('bí đỏ')) {
      shopping.add('Bí đỏ tươi: ${g(140)}g');
    } else if (low.contains('bí xanh') || low.contains('bí đao')) {
      shopping.add('Bí xanh (bí đao): ${g(140)}g');
    } else if (low.contains('bầu')) {
      shopping.add('Bầu non tươi: ${g(140)}g');
    } else if (low.contains('rau muống')) {
      shopping.add('Rau muống tươi: ${g(150)}g');
    } else if (low.contains('mồng tơi')) {
      shopping.add('Rau mồng tơi & mướp hương: ${g(140)}g');
    } else if (low.contains('cải')) {
      shopping.add('Rau cải ngọt / cải thìa tươi: ${g(140)}g');
    } else if (low.contains('rau ngót')) {
      shopping.add('Rau ngót tươi: ${g(130)}g');
    } else if (low.contains('đậu cô ve')) {
      shopping.add('Đậu cô ve tươi: ${g(130)}g');
    } else if (low.contains('táo') ||
        low.contains('ổi') ||
        low.contains('thanh long') ||
        low.contains('lê') ||
        low.contains('đu đủ') ||
        low.contains('việt quất') ||
        low.contains('dâu')) {
      shopping.add('Trái cây tươi (${nameVi.split('+').first.trim()}): ${g(160)}g');
      if (low.contains('hạt')) {
        shopping.add('Hạt dinh dưỡng (hạnh nhân / óc chó rang mộc): ${g(25)}g');
      }
      cookMin = 5;
    } else {
      shopping.add('Rau xanh, giá đỗ, dưa leo & hành ngò: ${g(120)}g');
    }

    if (cookMin == 5) {
      steps = [
        'Bước 1 (Sơ chế): Rửa sạch trái cây với nước muối loãng, để ráo và cắt miếng vừa ăn (~${portionG}g).',
        'Bước 2 (Kết hợp): Dùng kèm hạt rang mộc không tẩm muối/đường để bổ sung chất béo tốt giúp no lâu.',
        'Bước 3 (Thưởng thức): Ăn cách bữa chính 2–3 tiếng giúp ổn định đường huyết và nạp vitamin tự nhiên.',
      ];
    } else if (low.contains('phở') ||
        low.contains('bún') ||
        low.contains('miến') ||
        low.contains('hủ tiếu') ||
        low.contains('cháo')) {
      shopping.add('Gia vị nấu: Gừng nướng, hành tím, sả, hành ngò, chanh & nước mắm nhạt');
      cookMin = 20;
      steps = [
        'Bước 1 (Sơ chế): Rửa sạch nguyên liệu đạm và rau; trụng nhanh bún/phở/miến qua nước sôi cho mềm sạch.',
        'Bước 2 (Nấu nước dùng/cháo): Đun nước dùng trong với gừng nướng và hành tím, cho thịt/cá vào chín tới, nêm nhạt dưới 1/2 muỗng cà phê muối.',
        'Bước 3 (Hoàn thiện): Xếp phần tinh bột và đạm vào tô, thêm nhiều rau xanh/giá trụng và hành ngò, hạn chế váng mỡ.',
      ];
    } else if (low.contains('hấp') || low.contains('luộc') || low.contains('cuốn')) {
      shopping.add('Gia vị: Gừng tươi, lá chanh/sả, tỏi, nước chấm pha nhạt');
      cookMin = 18;
      steps = [
        'Bước 1 (Sơ chế): Làm sạch phần đạm chính, ướp nhẹ với gừng thái sợi, sả hoặc lá chanh trong 5 phút để khử mùi và giữ vị ngọt.',
        'Bước 2 (Hấp/Luộc giữ chất): Hấp cách thủy hoặc luộc lửa vừa 10–12 phút cho chín mềm; rau củ luộc chín tới giữ màu xanh và chất xơ.',
        'Bước 3 (Trình bày): Ăn kèm cơm gạo lứt/bánh tráng và nước chấm pha loãng, ưu tiên ăn rau và đạm trước tinh bột.',
      ];
    } else {
      shopping.add('Gia vị: 1 muỗng cà phê dầu oliu/dầu cải, tỏi, tiêu đen, nước tương giảm muối');
      cookMin = 22;
      steps = [
        'Bước 1 (Sơ chế & Ướp): Thái phần đạm vừa ăn, ướp với chút tiêu đen, tỏi băm và 1/2 muỗng nước tương giảm muối trong 10 phút.',
        'Bước 2 (Áp chảo / Xào ít dầu): Làm nóng chảo chống dính với 1 muỗng nhỏ dầu thực vật, áp chảo/xào nhanh trên lửa vừa cho chín vàng đều.',
        'Bước 3 (Canh & Rau ăn kèm): Nấu canh hoặc luộc rau củ thanh mát ít muối, dọn ăn cùng cơm theo đúng định lượng khẩu phần.',
      ];
    }

    return {
      'shopping_items': shopping,
      'cooking_time_min': cookMin,
      'recipe_steps': steps,
    };
  }

  Map<String, dynamic>? _resolveLocalPool(String pref) {
    final low = pref.trim().toLowerCase();
    if (low.isEmpty) return null;
    if (low.contains('gà')) return _localPrefPools['ga'];
    if (low.contains('bò')) return _localPrefPools['bo'];
    if (low.contains('heo') || low.contains('lợn') || low.contains('sườn')) {
      return _localPrefPools['heo'];
    }
    if (low.contains('cá') || low.contains('tôm') || low.contains('hải sản')) {
      return _localPrefPools['ca'];
    }
    if (low.contains('đậu') || low.contains('trứng') || low.contains('chay')) {
      return _localPrefPools['chay'];
    }
    final label = pref.trim();
    return {
      'focus': 'Thực đơn tự chọn theo món bạn muốn: $label',
      'breakfast': [
        {'meal_type': 'Bữa sáng', 'name_vi': 'Bún / Phở $label nấu thanh đạm + Rau sống', 'portion_g': 360, 'calories': 420, 'protein_g': 28, 'fat_g': 9, 'carbs_g': 54},
        {'meal_type': 'Bữa sáng', 'name_vi': 'Cháo yến mạch $label + Hành ngò', 'portion_g': 340, 'calories': 395, 'protein_g': 26, 'fat_g': 8, 'carbs_g': 52},
      ],
      'lunch': [
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm gạo lứt + $label chế biến ít dầu + Bông cải xanh luộc', 'portion_g': 400, 'calories': 585, 'protein_g': 39, 'fat_g': 13, 'carbs_g': 73},
        {'meal_type': 'Bữa trưa', 'name_vi': 'Cơm trắng vừa + $label rim/xào rau củ + Canh cải ngọt', 'portion_g': 400, 'calories': 595, 'protein_g': 38, 'fat_g': 14, 'carbs_g': 74},
      ],
      'dinner': [
        {'meal_type': 'Bữa tối', 'name_vi': '$label hấp/áp chảo thanh nhẹ + Cơm gạo lứt + Canh bí xanh', 'portion_g': 370, 'calories': 490, 'protein_g': 35, 'fat_g': 10, 'carbs_g': 63},
        {'meal_type': 'Bữa tối', 'name_vi': 'Salad / Gỏi cuốn $label rau tươi + Súp nấm', 'portion_g': 350, 'calories': 460, 'protein_g': 33, 'fat_g': 9, 'carbs_g': 58},
      ],
    };
  }

  void _applyLocalCustomizationForDay(int dayIdx, {int? singleMealIdxToSwap}) {
    final days = (_plan?['days'] as List?) ?? [];
    if (dayIdx < 0 || dayIdx >= days.length) return;
    final currentDay = Map<String, dynamic>.from(days[dayIdx] as Map);
    final pref = (_dayPreferences[dayIdx] ?? '').trim();
    final seed = _dayVariationSeeds[dayIdx] ?? 0;

    final pool =
        _resolveLocalPool(pref) ??
        _localPrefPools.values.elementAt((dayIdx + seed) % _localPrefPools.length);

    final bList = pool['breakfast'] as List;
    final lList = pool['lunch'] as List;
    final dList = pool['dinner'] as List;
    final oldMeals = ((currentDay['meals'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    List<Map<String, dynamic>> rawTemplates;
    if (singleMealIdxToSwap != null && oldMeals.length >= 4) {
      rawTemplates = List<Map<String, dynamic>>.from(oldMeals);
      if (singleMealIdxToSwap == 0) {
        rawTemplates[0] = Map<String, dynamic>.from(
          bList[(dayIdx + seed) % bList.length] as Map,
        );
      } else if (singleMealIdxToSwap == 1) {
        rawTemplates[1] = Map<String, dynamic>.from(
          lList[(dayIdx + seed) % lList.length] as Map,
        );
      } else if (singleMealIdxToSwap == 2) {
        rawTemplates[2] = Map<String, dynamic>.from(
          dList[(dayIdx + seed) % dList.length] as Map,
        );
      }
    } else {
      final snackTpl = oldMeals.isNotEmpty
          ? oldMeals.last
          : {
              'meal_type': 'Ăn phụ',
              'name_vi': 'Táo xanh + Hạt hạnh nhân rang mộc',
              'portion_g': 150,
              'calories': 190,
              'protein_g': 5,
              'fat_g': 9,
              'carbs_g': 22,
            };
      rawTemplates = [
        Map<String, dynamic>.from(bList[(dayIdx + seed) % bList.length] as Map),
        Map<String, dynamic>.from(lList[(dayIdx + seed) % lList.length] as Map),
        Map<String, dynamic>.from(dList[(dayIdx + seed) % dList.length] as Map),
        snackTpl,
      ];
    }

    final goal = widget.dailyGoal.clamp(1200.0, 3500.0);
    final baseKcal = rawTemplates.fold<double>(
      0.0,
      (s, m) => s + ((m['calories'] as num?)?.toDouble() ?? 400.0),
    );
    final scale = baseKcal > 0 ? (goal / baseKcal) : 1.0;

    final newMeals = <Map<String, dynamic>>[];
    double dayCal = 0, dayPro = 0, dayFat = 0, dayCarb = 0;

    for (final m in rawTemplates) {
      final c = (((m['calories'] as num?)?.toDouble() ?? 400) * scale).round();
      final p = double.parse(
        (((m['protein_g'] as num?)?.toDouble() ?? 25) * scale).toStringAsFixed(1),
      );
      final f = double.parse(
        (((m['fat_g'] as num?)?.toDouble() ?? 10) * scale).toStringAsFixed(1),
      );
      final cb = double.parse(
        (((m['carbs_g'] as num?)?.toDouble() ?? 55) * scale).toStringAsFixed(1),
      );
      final pg = math.max(
        80,
        ((((m['portion_g'] as num?)?.toDouble() ?? 350) * scale) / 10.0)
                .round() *
            10,
      );
      final nameVi = '${m['name_vi']}';
      final extra = buildLocalRecipeAndShopping(nameVi, pg);

      newMeals.add({
        'meal_type': m['meal_type'],
        'name_vi': nameVi,
        'portion_g': pg,
        'calories': c,
        'protein_g': p,
        'fat_g': f,
        'carbs_g': cb,
        'shopping_items': extra['shopping_items'],
        'cooking_time_min': extra['cooking_time_min'],
        'recipe_steps': extra['recipe_steps'],
      });
      dayCal += c;
      dayPro += p;
      dayFat += f;
      dayCarb += cb;
    }

    currentDay['focus'] = pref.isNotEmpty
        ? pool['focus']
        : '${currentDay['focus']}';
    currentDay['preference'] = pref.isNotEmpty ? pref : 'Linh hoạt';
    currentDay['total_calories'] = dayCal.round();
    currentDay['total_protein_g'] = double.parse(dayPro.toStringAsFixed(1));
    currentDay['total_fat_g'] = double.parse(dayFat.toStringAsFixed(1));
    currentDay['total_carbs_g'] = double.parse(dayCarb.toStringAsFixed(1));
    currentDay['meals'] = newMeals;

    setState(() {
      days[dayIdx] = currentDay;
    });
  }

  Future<void> _loadPlan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefPayload = <String, String>{};
      _dayPreferences.forEach((k, v) {
        if (v.trim().isNotEmpty) prefPayload['$k'] = v.trim();
      });
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/meal-plan/weekly'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'daily_goal': widget.dailyGoal,
          'day_preferences': prefPayload,
        }),
      );
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && body['status'] == 'ok') {
        final rawPlan = body['plan'] as Map<String, dynamic>?;
        final days = (rawPlan?['days'] as List?) ?? [];
        for (final d in days) {
          if (d is Map) {
            final meals = (d['meals'] as List?) ?? [];
            for (final m in meals) {
              if (m is Map && m['shopping_items'] == null) {
                final extra = buildLocalRecipeAndShopping(
                  '${m['name_vi'] ?? ''}',
                  (m['portion_g'] as num?)?.toInt() ?? 350,
                );
                m['shopping_items'] = extra['shopping_items'];
                m['cooking_time_min'] = extra['cooking_time_min'];
                m['recipe_steps'] = extra['recipe_steps'];
              }
            }
          }
        }
        setState(() {
          _plan = rawPlan;
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
                          builder: (_) => _SmartGroceryListDialog(
                            days: days,
                            initialDayIndex: _selectedDay,
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: 16,
                      ),
                      label: const Text(
                        'Đi chợ theo món',
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
                      final prefTag = (_dayPreferences[i] ?? '').trim();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            prefTag.isNotEmpty
                                ? '${d['day']} · $prefTag'
                                : '${d['day']}',
                          ),
                          selected: sel,
                          selectedColor: primary,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          onSelected: (_) {
                            setState(() {
                              _selectedDay = i;
                              _customPrefCtrl.text = _dayPreferences[i] ?? '';
                            });
                          },
                        ),
                      );
                    }),
                  ),
                ),
                if (currentDay != null) ...[
                  const SizedBox(height: 12),
                  // Khung tu quyet dinh mon muon an cho ngay dang chon (Khong co dinh!)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
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
                            Expanded(
                              child: Text(
                                '${currentDay['day']} bạn muốn ăn gì? (AI tự soạn thực đơn & đi chợ)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: accent,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: primaryDark,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () {
                                _dayVariationSeeds[_selectedDay] =
                                    (_dayVariationSeeds[_selectedDay] ?? 0) + 1;
                                _applyLocalCustomizationForDay(_selectedDay);
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text(
                                'Đổi thực đơn khác',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _prefOptions.map((opt) {
                            final id = opt['id']!;
                            final cur = (_dayPreferences[_selectedDay] ?? '')
                                .trim();
                            final selected = cur.toLowerCase() ==
                                id.toLowerCase();
                            return InkWell(
                              onTap: () {
                                _dayPreferences[_selectedDay] = id;
                                _customPrefCtrl.text = id;
                                _dayVariationSeeds[_selectedDay] =
                                    (_dayVariationSeeds[_selectedDay] ?? 0) + 1;
                                _applyLocalCustomizationForDay(_selectedDay);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? primary
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  opt['label']!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? Colors.white : accent,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  controller: _customPrefCtrl,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Hoặc tự gõ món/nguyên liệu (VD: sườn non, vịt, cá hồi...)',
                                    hintStyle: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (val) {
                                    _dayPreferences[_selectedDay] = val.trim();
                                    _dayVariationSeeds[_selectedDay] =
                                        (_dayVariationSeeds[_selectedDay] ??
                                            0) +
                                        1;
                                    _applyLocalCustomizationForDay(
                                      _selectedDay,
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 38,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryDark,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  _dayPreferences[_selectedDay] =
                                      _customPrefCtrl.text.trim();
                                  _dayVariationSeeds[_selectedDay] =
                                      (_dayVariationSeeds[_selectedDay] ?? 0) +
                                      1;
                                  _applyLocalCustomizationForDay(_selectedDay);
                                },
                                child: const Text(
                                  'Soạn món',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  ...List.generate(meals.length, (mIdx) {
                    final m = Map<String, dynamic>.from(meals[mIdx] as Map);
                    final recKey = '$_selectedDay-$mIdx';
                    final isExpanded = _expandedRecipeKeys.contains(recKey);
                    final extra = m['shopping_items'] != null
                        ? m
                        : buildLocalRecipeAndShopping(
                            '${m['name_vi'] ?? ''}',
                            (m['portion_g'] as num?)?.toInt() ?? 350,
                          );
                    final shoppingList =
                        ((extra['shopping_items'] as List?) ?? [])
                            .map((e) => '$e')
                            .toList();
                    final recipeSteps =
                        ((extra['recipe_steps'] as List?) ?? [])
                            .map((e) => '$e')
                            .toList();
                    final cookMin = extra['cooking_time_min'] ?? 18;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                              if (mIdx < 3)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Đổi món khác cho bữa này',
                                  color: const Color(0xFF0284C7),
                                  onPressed: () {
                                    _dayVariationSeeds[_selectedDay] =
                                        (_dayVariationSeeds[_selectedDay] ??
                                            0) +
                                        1;
                                    _applyLocalCustomizationForDay(
                                      _selectedDay,
                                      singleMealIdxToSwap: mIdx,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.autorenew_rounded,
                                    size: 20,
                                  ),
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Ghi món này vào nhật ký hôm nay',
                                color: primary,
                                onPressed: () => _logMeal(m),
                                icon: const Icon(Icons.add_circle_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedRecipeKeys.remove(recKey);
                                } else {
                                  _expandedRecipeKeys.add(recKey);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isExpanded
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isExpanded
                                      ? const Color(0xFFA7F3D0)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.menu_book_rounded,
                                    size: 15,
                                    color: primaryDark,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      isExpanded
                                          ? 'Ẩn nguyên liệu đi chợ & công thức nấu'
                                          : '🛒 Xem nguyên liệu đi chợ (${shoppingList.length} món) & 👩‍🍳 Công thức nấu (~${cookMin}p)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: primaryDark,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: primaryDark,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isExpanded) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '🛒 Nguyên liệu cần mua cho món này:',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...shoppingList.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '• ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: primaryDark,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF334155),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '👩‍🍳 Công thức chế biến (~$cookMin phút):',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      color: primaryDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...recipeSteps.map(
                                    (step) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        step,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          height: 1.35,
                                          color: Color(0xFF334155),
                                        ),
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
  final int initialDayIndex;

  const _SmartGroceryListDialog({
    required this.days,
    this.initialDayIndex = 0,
  });

  @override
  State<_SmartGroceryListDialog> createState() =>
      _SmartGroceryListDialogState();
}

class _SmartGroceryListDialogState extends State<_SmartGroceryListDialog> {
  final Set<String> _checked = {};
  bool _onlySelectedDay = true;

  Map<String, List<String>> _buildCategories() {
    final targetDays = _onlySelectedDay &&
            widget.days.isNotEmpty &&
            widget.initialDayIndex < widget.days.length
        ? [widget.days[widget.initialDayIndex]]
        : widget.days;

    final proteinItems = <String>[];
    final veggieItems = <String>[];
    final carbItems = <String>[];
    final spiceItems = <String>[];

    for (final d in targetDays) {
      if (d is! Map) continue;
      final dayName = '${d['day'] ?? ''}';
      final meals = (d['meals'] as List?) ?? [];
      for (final rawM in meals) {
        if (rawM is! Map) continue;
        final dishName = '${rawM['name_vi'] ?? 'Món ăn'}';
        final portionG = (rawM['portion_g'] as num?)?.toInt() ?? 350;
        final rawShop = rawM['shopping_items'] as List?;
        final shopList = rawShop != null
            ? rawShop.map((e) => '$e').toList()
            : (_WeeklyMealPlanSheetState.buildLocalRecipeAndShopping(
                    dishName,
                    portionG,
                  )['shopping_items'] as List)
                .map((e) => '$e')
                .toList();

        final tag = _onlySelectedDay
            ? '($dishName)'
            : '($dayName · ${dishName.split('+').first.trim()})';

        for (final item in shopList) {
          final low = item.toLowerCase();
          final entry = '$item $tag';
          if (low.contains('gia vị')) {
            if (spiceItems.length < 12 && !spiceItems.contains(item)) {
              spiceItems.add(item);
            }
          } else if (low.contains('gà') ||
              low.contains('bò') ||
              low.contains('heo') ||
              low.contains('sườn') ||
              low.contains('cá') ||
              low.contains('tôm') ||
              low.contains('trứng') ||
              low.contains('đậu hũ')) {
            proteinItems.add(entry);
          } else if (low.contains('gạo') ||
              low.contains('bún') ||
              low.contains('phở') ||
              low.contains('miến') ||
              low.contains('hủ tiếu') ||
              low.contains('khoai') ||
              low.contains('yến mạch') ||
              low.contains('bánh')) {
            carbItems.add(entry);
          } else {
            veggieItems.add(entry);
          }
        }
      }
    }

    return {
      if (proteinItems.isNotEmpty)
        '🥩 Thịt, Cá, Trứng & Đạm theo món đã chọn': proteinItems,
      if (veggieItems.isNotEmpty)
        '🥬 Rau củ, Nấm & Trái cây tươi': veggieItems,
      if (carbItems.isNotEmpty)
        '🌾 Gạo, Bún, Phở & Tinh bột tốt': carbItems,
      if (spiceItems.isNotEmpty)
        '🧂 Gia vị cần chuẩn bị': spiceItems,
    };
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories();
    final allItems = categories.values.expand((e) => e).toList();
    final curDayName = widget.days.isNotEmpty &&
            widget.initialDayIndex < widget.days.length
        ? '${(widget.days[widget.initialDayIndex] as Map)['day']}'
        : 'Hôm nay';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.shopping_basket_rounded, color: primaryDark),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Danh Sách Đi Chợ Theo Thực Đơn',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
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
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text('📅 Riêng $curDayName'),
                      selected: _onlySelectedDay,
                      selectedColor: primary,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _onlySelectedDay ? Colors.white : accent,
                      ),
                      onSelected: (_) =>
                          setState(() => _onlySelectedDay = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('🗓️ Gộp cả 7 ngày'),
                      selected: !_onlySelectedDay,
                      selectedColor: primary,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: !_onlySelectedDay ? Colors.white : accent,
                      ),
                      onSelected: (_) =>
                          setState(() => _onlySelectedDay = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...categories.entries.map((entry) {
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
            }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final categories = _buildCategories();
            final buf = StringBuffer('🛒 DANH SÁCH ĐI CHỢ THEO THỰC ĐƠN (FOODSCAN AI)\n');
            for (final e in categories.entries) {
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
