import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth_http.dart' as http;
import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_session.dart';
import '../../core/day_stats.dart';
import '../../core/meal_slot.dart';
import '../../core/nutrition_calc.dart';
import '../../models/models.dart';
import '../../home_extras.dart';
import '../../more_extras.dart';
import '../../services/live_motion_tracker.dart';
import '../../widgets/meal_slot_picker.dart';
import '../../widgets/pro_smart_sheets.dart';
import '../journal/journal_screen.dart' show PremiumMealTile;
import '../smart_meal_dialog.dart';
import '../stats/statistics_screen.dart'
    show
        WeeklyMealPlanSheet,
        WeeklyClinicalReportDialog,
        FoodComparisonDialog;

// ============================================================
// HOME
// ============================================================

class HomeScreen extends StatefulWidget {
  final List<MealEntry> entries;

  final UserProfile profile;

  final List<String> userAllergies;

  final List<String> userConditions;

  final VoidCallback onScan;

  final VoidCallback onJournal;

  final Future<void> Function() onRefresh;

  final void Function(UserProfile profile) onSaveProfile;

  final ManualMealCallback onManualAdd;

  /// Chuyen sang tab Ho so (de nhap chieu cao/can nang, suc khoe...).
  final VoidCallback onOpenProfile;

  const HomeScreen({
    super.key,
    required this.entries,
    required this.profile,
    this.userAllergies = const [],
    this.userConditions = const [],
    required this.onScan,
    required this.onJournal,
    required this.onRefresh,
    required this.onSaveProfile,
    required this.onManualAdd,
    required this.onOpenProfile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _burnedKcal = 0;
  int _homeTabIndex = 0; // 0: Hôm nay, 1: Vận động & IF, 2: Tiện ích AI

  List<MealEntry> get entries => widget.entries;
  UserProfile get profile => widget.profile;
  List<String> get userAllergies => widget.userAllergies;
  List<String> get userConditions => widget.userConditions;
  VoidCallback get onScan => widget.onScan;
  VoidCallback get onJournal => widget.onJournal;
  Future<void> Function() get onRefresh => widget.onRefresh;
  void Function(UserProfile profile) get onSaveProfile => widget.onSaveProfile;
  ManualMealCallback get onManualAdd => widget.onManualAdd;
  VoidCallback get onOpenProfile => widget.onOpenProfile;

  bool isToday(DateTime date) {
    final now = DateTime.now();

    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String greeting() {
    final hour = DateTime.now().hour;

    if (hour < 11) {
      return 'Chào buổi sáng ☀️';
    }

    if (hour < 14) {
      return 'Chào buổi trưa 👋';
    }

    if (hour < 18) {
      return 'Chào buổi chiều 🌤️';
    }

    return 'Chào buổi tối 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final today = entries.where((e) => isToday(e.time)).toList();

    final calories = today.fold<double>(0, (sum, e) => sum + e.calories);

    final protein = today.fold<double>(0, (sum, e) => sum + e.proteinG);

    final fat = today.fold<double>(0, (sum, e) => sum + e.fatG);

    final carbs = today.fold<double>(0, (sum, e) => sum + e.carbsG);

    final double effectiveGoal = profile.dailyGoal + _burnedKcal;

    final double progress = effectiveGoal <= 0
        ? 0
        : (calories / effectiveGoal).clamp(0.0, 1.0).toDouble();

    final double remaining = (effectiveGoal - calories)
        .clamp(0.0, double.infinity)
        .toDouble();

    // "An lai theo thoi quen": mon cac ngay truoc, cung khung bua hien tai,
    // xep theo so lan an (nhieu nhat truoc), bo mon da an hom nay.
    final habitFoods = NutritionCalculator.habitFoods(
      history: entries
          .where((e) => !isToday(e.time))
          .map((e) => (name: e.name, mealType: e.mealType))
          .toList(),
      currentSlot: MealSlot.forTime(DateTime.now()),
      eatenToday: today.map((e) => e.name).toList(),
    );

    final targets = NutritionCalculator.calculateTargetsForMacroBars(
      goalKcal: profile.dailyGoal,
      weightKg: profile.weightKg,
    );

    // Chuoi ngay & trung binh 7 ngay: dung CHUNG DayStats voi man Thong ke.
    final caloriesByDay = DayStats.caloriesByDay(entries);
    final streak = DayStats.streak(caloriesByDay);
    final weeklyAvg = DayStats.weeklyAverage(caloriesByDay);

    final missingBody = profile.heightCm == null || profile.weightKg == null;

    final remainingAdvice = NutritionCalculator.analyzeRemaining(
      target: targets,
      consumedCalories: calories,
      consumedProteinG: protein,
      consumedFatG: fat,
      consumedCarbsG: carbs,
      userAllergies: userAllergies,
      userConditions: userConditions,
      userRecentFoods: habitFoods,
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: RefreshIndicator(
            color: primary,
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.spa_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${greeting()} · ${profile.displayName.isEmpty ? 'Bạn ơi!' : profile.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ăn ngon · Sống khỏe mỗi ngày 🌱',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF047857),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFF59E0B),
                            size: 15,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$streak ngày',
                            style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF0D9488)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(26),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.18,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                            ),
                                            child: const Text(
                                              '🌿 DINH DƯỠNG HÔM NAY CỦA BẠN',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.white,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: calories.toStringAsFixed(0),
                                              style: const TextStyle(
                                                fontSize: 32,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: -1,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' / ${effectiveGoal.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFFD1FAE5),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const TextSpan(
                                              text: ' kcal',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            remaining > 0
                                                ? Icons.favorite_rounded
                                                : Icons.warning_amber_rounded,
                                            size: 15,
                                            color: remaining > 0
                                                ? const Color(0xFFA7F3D0)
                                                : const Color(0xFFFDE68A),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              remaining > 0
                                                  ? 'Bạn còn ${remaining.toStringAsFixed(0)} kcal cho hôm nay'
                                                  : 'Hôm nay vượt ${(calories - effectiveGoal).toStringAsFixed(0)} kcal rồi nhé',
                                              style: TextStyle(
                                                color: remaining > 0
                                                    ? const Color(0xFFECFDF5)
                                                    : const Color(0xFFFDE68A),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_burnedKcal > 0) ...[
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFFC4C02,
                                            ).withValues(alpha: 0.22),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(
                                                0xFFFB923C,
                                              ).withValues(alpha: 0.45),
                                            ),
                                          ),
                                          child: Text(
                                            '🏃 Đã cộng bù +$_burnedKcal kcal từ vận động hôm nay',
                                            style: const TextStyle(
                                              color: Color(0xFFFED7AA),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 84,
                                  height: 84,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 78,
                                        height: 78,
                                        child: CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 8,
                                          strokeCap: StrokeCap.round,
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.14),
                                          color: const Color(0xFF34D399),
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${(progress * 100).round()}%',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 17,
                                            ),
                                          ),
                                          const Text(
                                            'TDEE',
                                            style: TextStyle(
                                              color: Color(0xFF6EE7B7),
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _HomeBiomedicalStatusStrip(
                              calories: calories,
                              proteinG: protein,
                              fatG: fat,
                              carbsG: carbs,
                              dailyGoal: profile.dailyGoal,
                              weightKg: profile.weightKg ?? 65.0,
                              avgDailyCalories: weeklyAvg.loggedDays > 0
                                  ? weeklyAvg.average
                                  : profile.dailyGoal,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: MacroGlassCard(
                                title: 'Đạm',
                                value: protein,
                                target: targets.proteinG,
                                color: const Color(0xFF6366F1),
                                bgColor: const Color(0xFFEEF2FF),
                                icon: Icons.fitness_center_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: MacroGlassCard(
                                title: 'Béo',
                                value: fat,
                                target: targets.fatG,
                                color: const Color(0xFFF59E0B),
                                bgColor: const Color(0xFFFFFBEB),
                                icon: Icons.opacity_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: MacroGlassCard(
                                title: 'Carb',
                                value: carbs,
                                target: targets.carbsG,
                                color: const Color(0xFF10B981),
                                bgColor: const Color(0xFFECFDF5),
                                icon: Icons.grain_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (missingBody) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: onOpenProfile,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Mục tiêu đang tính theo số mặc định. Nhập chiều cao, cân nặng để tính đúng cho bạn.',
                                style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: Color(0xFFB45309)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Thanh 3 nút thao tác nhanh trên 1 hàng gọn đẹp
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [primary, primaryDark],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: onScan,
                          icon: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: Text(
                            'Quét món',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () => SmartMealDialog.show(
                            context,
                            userKey: AppSession.currentUserKey,
                            baseUrl: AppConfig.baseUrl,
                            onMealSaved: onRefresh,
                          ),
                          icon: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 17,
                          ),
                          label: Text(
                            'Ghi bằng chữ',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => showManualAddSheet(
                            context,
                            baseUrl: AppConfig.baseUrl,
                            onAdd: onManualAdd,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            backgroundColor: Colors.white,
                            side: const BorderSide(
                              color: Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(
                            Icons.edit_note_rounded,
                            color: primaryDark,
                            size: 18,
                          ),
                          label: Text(
                            'Thủ công',
                            style: GoogleFonts.plusJakartaSans(
                              color: accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Thanh chuyển 3 phân khu trên Trang chủ để giao diện luôn gọn đẹp, không bị cuộn dài
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0).withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _buildHomeSegmentTab(
                        0,
                        'Hôm nay (${today.length})',
                        Icons.restaurant_rounded,
                      ),
                      _buildHomeSegmentTab(
                        1,
                        'Vận động & IF',
                        Icons.directions_run_rounded,
                      ),
                      _buildHomeSegmentTab(
                        2,
                        'Tiện ích AI',
                        Icons.auto_awesome_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_homeTabIndex == 0) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Bữa ăn hôm nay',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (today.isNotEmpty)
                        TextButton(
                          onPressed: onJournal,
                          child: const Text(
                            'Xem tất cả',
                            style: TextStyle(
                              color: primaryDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (today.isEmpty)
                    PremiumEmptyMeal(onScan: onScan)
                  else
                    ...today.take(4).map(
                      (meal) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PremiumMealTile(entry: meal),
                      ),
                    ),
                  const SizedBox(height: 14),
                  WaterTrackerCard(
                    baseUrl: AppConfig.baseUrl,
                    userKey: AppSession.currentUserKey,
                    saltyMealCount:
                        SaltyMealHydrationHelper.countTodaySaltyMeals(today),
                  ),
                  const SizedBox(height: 14),
                  // Gợi ý bữa tiếp theo gọn gàng
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFBBF7D0),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.lightbulb_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Gợi ý cho ${remaining.round()} kcal còn lại',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF065F46),
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  setState(() => _homeTabIndex = 2),
                              child: const Text(
                                'Mở Tiện ích AI →',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          remainingAdvice.adviceText,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E293B),
                            height: 1.4,
                          ),
                        ),
                        if (remainingAdvice.recommendedFoods.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: remainingAdvice.recommendedFoods.map((
                              food,
                            ) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final slot = await pickMealSlot(context);
                                  if (slot == null) return;
                                  final estKcal = remaining > 180
                                      ? (remaining * 0.45).clamp(160.0, 420.0)
                                      : 160.0;
                                  onManualAdd(
                                    name: food,
                                    mealType: slot,
                                    portionG: 200,
                                    calories: estKcal.roundToDouble(),
                                    proteinG: (estKcal * 0.08).roundToDouble(),
                                    fatG: (estKcal * 0.03).roundToDouble(),
                                    carbsG: (estKcal * 0.10).roundToDouble(),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Đã ghi "$food" vào $slot!',
                                        ),
                                        backgroundColor: const Color(
                                          0xFF059669,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF86EFAC),
                                    ),
                                  ),
                                  child: Text(
                                    '🥗 $food  +',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF047857),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (_homeTabIndex == 1) ...[
                  ExerciseTrackerCard(
                    weightKg: profile.weightKg ?? 65.0,
                    onBurnedChanged: (burned) {
                      if (mounted && _burnedKcal != burned) {
                        setState(() => _burnedKcal = burned);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  CircadianTimingCard(meals: entries),
                  const SizedBox(height: 14),
                  StreakInsightCard(
                    dayKcal: caloriesByDay,
                    goalKcal: profile.dailyGoal,
                  ),
                ] else ...[
                  _ProToolsQuickHub(
                    dailyGoal: profile.dailyGoal,
                    onAddMeal: (entry) async {
                      onManualAdd(
                        name: entry.name,
                        mealType: entry.mealType,
                        portionG: entry.portionG,
                        calories: entry.calories,
                        proteinG: entry.proteinG,
                        fatG: entry.fatG,
                        carbsG: entry.carbsG,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SuggestionsCard(
                    baseUrl: AppConfig.baseUrl,
                    userKey: AppSession.currentUserKey,
                    remainingKcal: remaining,
                    onTapFood: (f) async {
                      final slot = await pickMealSlot(context);
                      if (slot == null) return;
                      final dishName = (f['name_vi'] ?? 'Món ăn').toString();
                      onManualAdd(
                        name: dishName,
                        mealType: slot,
                        portionG: ((f['portion_g'] as num?) ?? 150).round(),
                        calories: ((f['calories'] as num?) ?? 200).toDouble(),
                        proteinG: ((f['protein_g'] as num?) ?? 12).toDouble(),
                        fatG: ((f['fat_g'] as num?) ?? 6).toDouble(),
                        carbsG: ((f['carbs_g'] as num?) ?? 20).toDouble(),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã ghi "$dishName" vào $slot!'),
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeSegmentTab(int index, String label, IconData icon) {
    final selected = _homeTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _homeTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
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
                size: 15,
                color: selected ? primaryDark : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? primaryDark : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MacroGlassCard extends StatelessWidget {
  final String title;
  final double value;
  final double? target;
  final Color color;
  final Color bgColor;
  final IconData? icon;

  const MacroGlassCard({
    super.key,
    required this.title,
    required this.value,
    this.target,
    this.color = const Color(0xFF10B981),
    this.bgColor = const Color(0xFFECFDF5),
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: GoogleFonts.plusJakartaSans(color: accent),
              children: [
                TextSpan(
                  text: value.toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                TextSpan(
                  text: target == null ? 'g' : ' / ${target!.toStringAsFixed(0)}g',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (target != null && target! > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (value / target!).clamp(0.0, 1.0),
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PremiumEmptyMeal extends StatelessWidget {
  final VoidCallback onScan;

  const PremiumEmptyMeal({super.key, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD1FAE5), width: 1.4),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.ramen_dining_rounded,
              color: primaryDark,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Hôm nay bạn ăn món gì nhỉ? 🍜',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chụp ảnh món ăn hoặc ghi nhanh bằng chữ để theo dõi dinh dưỡng nhé!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFECFDF5),
              foregroundColor: primaryDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onScan,
            icon: const Icon(Icons.camera_alt_rounded, size: 17),
            label: const Text(
              'Chụp ảnh món ăn ngay',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBiomedicalStatusStrip extends StatelessWidget {
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double dailyGoal;
  final double weightKg;
  final double avgDailyCalories;

  const _HomeBiomedicalStatusStrip({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.dailyGoal,
    required this.weightKg,
    required this.avgDailyCalories,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasFood = calories > 10;
    int score = 78;
    if (hasFood) {
      final proRatio = (proteinG * 4) / calories;
      final fatRatio = (fatG * 9) / calories;
      if (proRatio >= 0.18) score += 10;
      if (fatRatio > 0.38) score -= 15;
      if (carbsG > 180) score -= 12;
      if (calories > dailyGoal * 1.15) score -= 15;
    }
    final grade = !hasFood
        ? 'A'
        : (score >= 80
              ? 'A'
              : (score >= 68 ? 'B' : (score >= 55 ? 'C' : 'D')));
    final gradeColor = (grade == 'A' || grade == 'B')
        ? const Color(0xFF059669)
        : (grade == 'C' ? const Color(0xFFD97706) : const Color(0xFFDC2626));

    final gl = (carbsG * 0.55).round();
    final glDisplay = !hasFood
        ? 'Tải đường (GL): Chưa ăn'
        : 'Tải đường (GL): ${gl < 40 ? 'Ổn định' : (gl <= 80 ? 'Vừa' : 'Cao')} ($gl)';

    // Dung cung cong thuc trung binh 7 ngay co ghi chep voi man Thong ke:
    // Khi chua ghi mon nao -> avgDailyCalories == dailyGoal -> delta30d == 0.
    final delta30d = ((avgDailyCalories - dailyGoal) * 30.0) / 7700.0;
    final projectedW = weightKg + delta30d;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: gradeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                  child: Text(
                    'Điểm $grade',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  hasFood ? 'Ăn cân đối' : 'Khởi đầu ngày mới',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withValues(alpha: 0.25),
            ),
            Row(
              children: [
                const Icon(
                  Icons.spa_outlined,
                  size: 14,
                  color: Color(0xFFFDE68A),
                ),
                const SizedBox(width: 3),
                Text(
                  glDisplay,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFDE68A),
                  ),
                ),
              ],
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withValues(alpha: 0.25),
            ),
            Row(
              children: [
                const Icon(
                  Icons.monitor_weight_outlined,
                  size: 14,
                  color: Color(0xFFE0F2FE),
                ),
                const SizedBox(width: 3),
                Text(
                  'Dự kiến 30 ngày: ${projectedW.toStringAsFixed(1)}kg',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
        ],
      ),
      ),
    );
  }
}

class _ProToolsQuickHub extends StatelessWidget {
  final double dailyGoal;
  final Future<void> Function(MealEntry)? onAddMeal;

  const _ProToolsQuickHub({required this.dailyGoal, this.onAddMeal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TIỆN ÍCH AI',
                  style: TextStyle(
                    color: primaryDark,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Thực đơn 7 ngày, Cố vấn chọn món & Nấu ăn tại nhà',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _hubButton(
                  icon: Icons.calendar_month_rounded,
                  title: 'Thực đơn 7 ngày',
                  subtitle: 'Theo TDEE & Bệnh',
                  color: const Color(0xFF059669),
                  bg: const Color(0xFFECFDF5),
                  onTap: () {
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
                        dailyGoal: dailyGoal,
                        onAddMeal: onAddMeal,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _hubButton(
                  icon: Icons.balance_rounded,
                  title: 'So sánh 2 món',
                  subtitle: 'Bàn cân A vs B',
                  color: const Color(0xFF7C3AED),
                  bg: const Color(0xFFF5F3FF),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const FoodComparisonDialog(),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _hubButton(
                  icon: Icons.restaurant_menu_rounded,
                  title: 'Quét Menu Quán',
                  subtitle: 'Cố vấn chọn món',
                  color: const Color(0xFF0D9488),
                  bg: const Color(0xFFF0FDFA),
                  onTap: () => showSmartMenuAdvisorSheet(
                    context,
                    dailyGoal: dailyGoal,
                    onAddMeal: onAddMeal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _hubButton(
                  icon: Icons.kitchen_rounded,
                  title: 'Tủ Lạnh Gợi Ý',
                  subtitle: 'Nấu nhanh 15 phút',
                  color: const Color(0xFFEA580C),
                  bg: const Color(0xFFFFF7ED),
                  onTap: () => showFridgeToMealSheet(
                    context,
                    dailyGoal: dailyGoal,
                    onAddMeal: onAddMeal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _hubButton(
            icon: Icons.assignment_turned_in_rounded,
            title: 'Báo cáo Dinh dưỡng 7 ngày & Xuất bảng Excel (.CSV)',
            subtitle: 'Tổng hợp Calo, Macro, Nước uống & Khuyến nghị sức khỏe',
            color: const Color(0xFFD97706),
            bg: const Color(0xFFFFFBEB),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (_) => const WeeklyClinicalReportDialog(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hubButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StravaSportConfig {
  final String id;
  final String label;
  final IconData icon;
  final double met;
  final double speedKmH;
  final int cadenceStepsPerMin;
  final String paceLabel;

  const _StravaSportConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.met,
    required this.speedKmH,
    required this.cadenceStepsPerMin,
    required this.paceLabel,
  });
}

class ExerciseTrackerCard extends StatefulWidget {
  final double weightKg;
  final ValueChanged<int>? onBurnedChanged;

  const ExerciseTrackerCard({
    super.key,
    this.weightKg = 65.0,
    this.onBurnedChanged,
  });

  @override
  State<ExerciseTrackerCard> createState() => _ExerciseTrackerCardState();
}

class _ExerciseTrackerCardState extends State<ExerciseTrackerCard> {
  static const Color _stravaOrange = Color(0xFFFC4C02);
  static const Color _stravaDark = Color(0xFF0F172A);

  static const List<_StravaSportConfig> _sports = [
    _StravaSportConfig(
      id: 'run',
      label: 'Chạy bộ',
      icon: Icons.directions_run_rounded,
      met: 9.8,
      speedKmH: 8.6,
      cadenceStepsPerMin: 162,
      paceLabel: "6'58\" /km",
    ),
    _StravaSportConfig(
      id: 'walk',
      label: 'Đi bộ',
      icon: Icons.directions_walk_rounded,
      met: 3.8,
      speedKmH: 5.0,
      cadenceStepsPerMin: 112,
      paceLabel: "12'00\" /km",
    ),
    _StravaSportConfig(
      id: 'ride',
      label: 'Đạp xe',
      icon: Icons.directions_bike_rounded,
      met: 6.8,
      speedKmH: 16.5,
      cadenceStepsPerMin: 0,
      paceLabel: '16.5 km/h',
    ),
  ];

  final LiveMotionTracker _motionTracker = LiveMotionTracker();

  int _selectedSportIndex = 0;
  bool _isRecording = false;
  bool _isPaused = false;
  int _elapsedSec = 0;
  int _movingSec = 0;
  double _recordedDistanceKm = 0.0;
  int _recordedSteps = 0;
  DateTime? _lastMovementAt;
  bool _hasGpsFix = false;
  double? _gpsAccuracyM;
  String _gpsStatusText = 'Đang kết nối GPS...';
  bool _demoSimMode = false;
  Timer? _timer;

  int _burnedKcal = 0;
  int _totalMinutes = 0;
  double _totalDistanceKm = 0.0;
  int _totalSteps = 0;
  List<Map<String, dynamic>> _activities = [];
  bool _saving = false;

  _StravaSportConfig get _activeSport => _sports[_selectedSportIndex];

  bool get _isCurrentlyMoving {
    if (_isPaused || !_isRecording) return false;
    if (_demoSimMode) return true;
    if (_lastMovementAt == null) return false;
    return DateTime.now().difference(_lastMovementAt!).inSeconds <= 4;
  }

  double get _liveDistanceKm => _recordedDistanceKm;

  int get _liveSteps => _recordedSteps;

  double get _liveBurnedKcal {
    final w = widget.weightKg > 25 ? widget.weightKg : 65.0;
    // Calo dot dua tren quang duong thuc te va thoi gian thuc su co di chuyen.
    // Khi dung yen (_movingSec == 0 va _recordedDistanceKm == 0) -> 0.0 kcal!
    final kcalByTime = w * _activeSport.met * (_movingSec / 3600.0);
    final kcalByDist =
        w * _recordedDistanceKm * (_activeSport.id == 'ride' ? 0.42 : 0.95);
    return math.max(kcalByTime, kcalByDist);
  }

  String get _livePaceText {
    if (_recordedDistanceKm < 0.005 || _movingSec < 3) {
      return 'Đang đứng yên';
    }
    if (_activeSport.id == 'ride') {
      final kmh = _recordedDistanceKm / (_movingSec / 3600.0);
      return '${kmh.clamp(1.0, 60.0).toStringAsFixed(1)} km/h';
    }
    final secPerKm = (_movingSec / _recordedDistanceKm).clamp(150.0, 1800.0);
    final pMin = (secPerKm ~/ 60);
    final pSec = (secPerKm % 60).round().toString().padLeft(2, '0');
    return "$pMin'$pSec\" /km";
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motionTracker.stop();
    super.dispose();
  }

  void _syncSummaryFromBody(Map<String, dynamic> body) {
    final burned = (body['burned_kcal'] as num?)?.toInt() ?? 0;
    final mins = (body['total_minutes'] as num?)?.toInt() ?? 0;
    final km = (body['total_distance_km'] as num?)?.toDouble() ?? 0.0;
    final steps = (body['total_steps'] as num?)?.toInt() ?? 0;
    final rawActs = (body['activities'] as List?) ?? [];
    final acts = rawActs
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    setState(() {
      _burnedKcal = burned;
      _totalMinutes = mins;
      _totalDistanceKm = km;
      _totalSteps = steps;
      _activities = acts;
    });
    widget.onBurnedChanged?.call(burned);
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic>) {
          _syncSummaryFromBody(body);
        }
      }
    } catch (_) {}
  }

  void _startRecording() {
    _timer?.cancel();
    _motionTracker.stop();
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _elapsedSec = 0;
      _movingSec = 0;
      _recordedDistanceKm = 0.0;
      _recordedSteps = 0;
      _lastMovementAt = null;
      _hasGpsFix = false;
      _gpsAccuracyM = null;
      _gpsStatusText = 'Đang bắt tín hiệu GPS...';
      _demoSimMode = false;
    });

    _motionTracker.start(
      onGpsFix: (lat, lng, acc) {
        if (!mounted || !_isRecording) return;
        setState(() {
          _hasGpsFix = true;
          _gpsAccuracyM = acc;
          _gpsStatusText = 'GPS ±${acc.round()}m';
        });
      },
      onGpsMove: (deltaMeters, lat, lng, acc, speedMps) {
        if (!mounted || !_isRecording || _isPaused) return;
        setState(() {
          _hasGpsFix = true;
          _gpsAccuracyM = acc;
          _lastMovementAt = DateTime.now();
          _recordedDistanceKm += deltaMeters / 1000.0;
          if (_activeSport.cadenceStepsPerMin > 0) {
            final strideM = _activeSport.id == 'run' ? 0.92 : 0.74;
            final estSteps = (deltaMeters / strideM).round();
            if (estSteps > 0) {
              _recordedSteps += estSteps;
            }
          }
        });
      },
      onGpsError: (msg) {
        if (!mounted || !_isRecording) return;
        setState(() {
          _gpsStatusText = msg;
        });
      },
      onStepDetected: () {
        if (!mounted || !_isRecording || _isPaused) return;
        setState(() {
          _lastMovementAt = DateTime.now();
          if (_activeSport.cadenceStepsPerMin > 0) {
            _recordedSteps += 1;
            final strideKm = _activeSport.id == 'run' ? 0.00092 : 0.00074;
            _recordedDistanceKm += strideKm;
          }
        });
      },
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_isRecording && !_isPaused) {
        setState(() {
          _elapsedSec += 1;
          if (_demoSimMode) {
            // Chi khi nguoi dung CHU DONG bat cong tac "Gia lap Demo PC"
            // thi moi tu tang de phuc vu demo tren may tinh ban/laptop.
            _movingSec += 1;
            _lastMovementAt = DateTime.now();
            _recordedDistanceKm += _activeSport.speedKmH / 3600.0;
            if (_activeSport.cadenceStepsPerMin > 0) {
              _recordedSteps += (_activeSport.cadenceStepsPerMin / 60.0).round();
            }
          } else if (_isCurrentlyMoving) {
            _movingSec += 1;
          }
        });
      }
    });
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  void _cancelRecording() {
    _timer?.cancel();
    _motionTracker.stop();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsedSec = 0;
      _movingSec = 0;
      _recordedDistanceKm = 0.0;
      _recordedSteps = 0;
      _lastMovementAt = null;
      _demoSimMode = false;
    });
  }

  Future<void> _finishAndSaveWorkout() async {
    if (_saving) return;

    final distKm = _liveDistanceKm;
    final steps = _liveSteps;
    if (distKm < 0.003 && steps == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFD97706),
          content: Text(
            'Chưa phát hiện di chuyển thực tế (0 m · 0 bước). Hãy cầm máy di chuyển hoặc bật "Mô phỏng Demo PC" nếu đang test trên laptop!',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    _timer?.cancel();
    _motionTracker.stop();

    final sport = _activeSport;
    final durSec = math.max(_movingSec, 1);
    final kcal = math.max(1, _liveBurnedKcal.round());
    final mins = math.max(1, (durSec / 60.0).ceil());
    final paceStr = _livePaceText == 'Đang đứng yên'
        ? sport.paceLabel
        : _livePaceText;

    final distText = distKm >= 0.10
        ? '${distKm.toStringAsFixed(2)} km'
        : '${math.max(1, (distKm * 1000).round())} m';

    final title = steps > 0
        ? '${sport.label} · $distText ($steps bước)'
        : '${sport.label} · $distText ($paceStr)';

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsedSec = 0;
      _movingSec = 0;
      _recordedDistanceKm = 0.0;
      _recordedSteps = 0;
      _lastMovementAt = null;
      _demoSimMode = false;
      _saving = true;
      _burnedKcal += kcal;
      _totalMinutes += mins;
      _totalDistanceKm = double.parse(
        (_totalDistanceKm + distKm).toStringAsFixed(2),
      );
      _totalSteps += steps;
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      _activities = [
        ..._activities,
        {
          'activity_name': title,
          'burned_kcal': kcal,
          'minutes': mins,
          'distance_km': double.parse(distKm.toStringAsFixed(2)),
          'steps': steps,
          'pace': paceStr,
          'duration_sec': durSec,
          'time': '$hh:$mm',
        },
      ];
    });
    widget.onBurnedChanged?.call(_burnedKcal);

    try {
      final res = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'activity_name': title,
          'burned_kcal': kcal,
          'minutes': mins,
          'distance_km': double.parse(distKm.toStringAsFixed(2)),
          'steps': steps,
          'pace': paceStr,
          'duration_sec': durSec,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic>) {
          _syncSummaryFromBody(body);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _stravaOrange,
          content: Text(
            'Đã lưu bài tập Strava: $title (-$kcal kcal)!',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
  }

  Future<void> _resetExercise() async {
    _timer?.cancel();
    _motionTracker.stop();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsedSec = 0;
      _movingSec = 0;
      _recordedDistanceKm = 0.0;
      _recordedSteps = 0;
      _lastMovementAt = null;
      _demoSimMode = false;
      _burnedKcal = 0;
      _totalMinutes = 0;
      _totalDistanceKm = 0.0;
      _totalSteps = 0;
      _activities = [];
    });
    widget.onBurnedChanged?.call(0);
    try {
      await http.delete(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
      );
    } catch (_) {}
  }

  String _formatClock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      final hh = h.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }
    return '$mm:$ss';
  }

  void _showStravaShareDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _stravaDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: _stravaOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Thẻ Thành Tích Vận Động (Strava Card)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 95,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _StravaRouteTrackPainter(
                      distanceKm: math.max(_totalDistanceKm, 0.65),
                      paused: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _metricTile(
                    label: 'TỔNG QUÃNG ĐƯỜNG',
                    value: '${_totalDistanceKm.toStringAsFixed(2)} km',
                    sub: '$_totalMinutes phút vận động',
                    valueColor: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  _metricTile(
                    label: 'TỔNG BƯỚC CHÂN',
                    value: '$_totalSteps bước',
                    sub: '${_activities.length} buổi tập hôm nay',
                    valueColor: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  _metricTile(
                    label: 'CALO ĐÃ ĐỐT',
                    value: '-$_burnedKcal kcal',
                    sub: 'Cộng vào mục tiêu ngày',
                    valueColor: const Color(0xFFFB923C),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final text =
                  '🏃 Thành tích vận động hôm nay trên FoodScan AI:\n'
                  '• Quãng đường: ${_totalDistanceKm.toStringAsFixed(2)} km ($_totalMinutes phút)\n'
                  '• Số bước chân: $_totalSteps bước\n'
                  '• Năng lượng đốt: -$_burnedKcal kcal';
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: _stravaOrange,
                    content: Text('Đã sao chép thẻ thành tích Strava!'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, color: _stravaOrange, size: 16),
            label: const Text(
              'Sao chép chia sẻ',
              style: TextStyle(
                color: _stravaOrange,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _stravaOrange),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildSportSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(_sports.length, (i) {
          final sp = _sports[i];
          final selected = _selectedSportIndex == i;
          return Expanded(
            child: InkWell(
              onTap: _isRecording
                  ? null
                  : () => setState(() => _selectedSportIndex = i),
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _stravaOrange : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _stravaOrange.withValues(alpha: 0.3),
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
                      sp.icon,
                      size: 16,
                      color: selected ? Colors.white : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      sp.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required String sub,
    required Color valueColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveStravaDashboard() {
    final distKm = _liveDistanceKm;
    final meters = (distKm * 1000).round();
    final steps = _liveSteps;
    final kcal = _liveBurnedKcal;
    final moving = _isCurrentlyMoving;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _stravaDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _stravaOrange.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isPaused
                      ? const Color(0xFFF59E0B)
                      : (moving
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isPaused
                      ? 'TẠM DỪNG · ${_activeSport.label.toUpperCase()}'
                      : (moving
                            ? 'STRAVA LIVE · ĐANG DI CHUYỂN (${_activeSport.label.toUpperCase()})'
                            : 'ĐANG ĐỨNG YÊN (AUTO-PAUSE) · CHỜ BẠN DI CHUYỂN'),
                  style: TextStyle(
                    color: moving
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFDE68A),
                    fontSize: 10.2,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (_hasGpsFix || _demoSimMode)
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (_hasGpsFix || _demoSimMode)
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_not_fixed_rounded,
                      size: 11,
                      color: (_hasGpsFix || _demoSimMode)
                          ? const Color(0xFF34D399)
                          : const Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _demoSimMode
                          ? 'Demo PC'
                          : (_hasGpsFix
                                ? 'GPS ±${(_gpsAccuracyM ?? 10).round()}m'
                                : 'Đang dò GPS'),
                      style: TextStyle(
                        color: (_hasGpsFix || _demoSimMode)
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFDE68A),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 92,
              width: double.infinity,
              child: CustomPaint(
                painter: _StravaRouteTrackPainter(
                  distanceKm: distKm,
                  paused: _isPaused || !moving,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Icon(
                  moving
                      ? Icons.directions_run_rounded
                      : Icons.accessibility_new_rounded,
                  size: 15,
                  color: moving
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    moving
                        ? (_demoSimMode
                              ? 'Đang bật giả lập di chuyển để test trên máy tính'
                              : 'Cảm biến GPS / Bước chân đang ghi nhận chuyển động thực')
                        : 'Thiết bị đang đứng yên — Km, Bước chân & Calo chỉ tăng khi bạn di chuyển thực tế ($_gpsStatusText)',
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _demoSimMode = !_demoSimMode),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _demoSimMode
                          ? _stravaOrange
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _demoSimMode ? 'Tắt Demo PC' : 'Giả lập (Test PC)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                Text(
                  'THỜI GIAN DI CHUYỂN THỰC TẾ (TỔNG: ${_formatClock(_elapsedSec)})',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  _formatClock(_movingSec),
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricTile(
                label: 'QUÃNG ĐƯỜNG',
                value: '${distKm.toStringAsFixed(2)} km',
                sub: '$meters mét đã đi',
                valueColor: Colors.white,
              ),
              const SizedBox(width: 8),
              _metricTile(
                label: _activeSport.cadenceStepsPerMin > 0
                    ? 'SỐ BƯỚC CHÂN'
                    : 'TỐC ĐỘ TB',
                value: _activeSport.cadenceStepsPerMin > 0
                    ? '$steps bước'
                    : _livePaceText,
                sub: _livePaceText == 'Đang đứng yên'
                    ? 'Đang đứng yên (0 m/s)'
                    : 'Pace $_livePaceText',
                valueColor: const Color(0xFF38BDF8),
              ),
              const SizedBox(width: 8),
              _metricTile(
                label: 'CALO ĐỐT',
                value: '${kcal.toStringAsFixed(1)} kcal',
                sub:
                    'Theo ${widget.weightKg.toStringAsFixed(0)}kg · ${_activeSport.met} MET',
                valueColor: const Color(0xFFFB923C),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Hủy buổi tập',
                onPressed: _cancelRecording,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFF94A3B8),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _togglePause,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isPaused ? 'Tiếp tục' : 'Tạm dừng',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _finishAndSaveWorkout,
                  style: FilledButton.styleFrom(
                    backgroundColor: _stravaOrange,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_rounded, size: 18),
                  label: const Text(
                    'Kết thúc & Lưu',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFC4C02), Color(0xFFEA580C)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_activeSport.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Ghi Nhận Vận Động',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: const Text(
                            'STRAVA TRACKER',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: _stravaOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _burnedKcal > 0
                          ? 'Hôm nay: ${_totalDistanceKm.toStringAsFixed(2)} km ($_totalMinutes phút · $_totalSteps bước) · -$_burnedKcal kcal'
                          : 'Đo bằng GPS & cảm biến chuyển động thực tế khi bạn chạy/đi bộ',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_burnedKcal > 0 && !_isRecording) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Chia sẻ thẻ thành tích Strava',
                  onPressed: _showStravaShareDialog,
                  icon: const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: _stravaOrange,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Đặt lại nhật ký vận động hôm nay',
                  onPressed: _resetExercise,
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 19,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _buildSportSelector(),
          if (_isRecording)
            _buildLiveStravaDashboard()
          else ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _startRecording,
                style: FilledButton.styleFrom(
                  backgroundColor: _stravaOrange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                label: Text(
                  'Bắt đầu ghi nhận ${_activeSport.label} (GPS Thực tế)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
          if (_activities.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              'HOẠT ĐỘNG ĐÃ GHI NHẬN HÔM NAY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            ..._activities.reversed.take(4).map((act) {
              final name = '${act['activity_name'] ?? 'Vận động'}';
              final kcal = act['burned_kcal'] ?? 0;
              final time = '${act['time'] ?? ''}';
              final pace = '${act['pace'] ?? ''}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.route_rounded,
                        size: 16,
                        color: _stravaOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                            if (time.isNotEmpty || pace.isNotEmpty)
                              Text(
                                [
                                  if (time.isNotEmpty) 'Lúc $time',
                                  if (pace.isNotEmpty) 'Pace $pace',
                                ].join(' · '),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-$kcal kcal',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _stravaOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _StravaRouteTrackPainter extends CustomPainter {
  final double distanceKm;
  final bool paused;

  const _StravaRouteTrackPainter({
    required this.distanceKm,
    required this.paused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Offset.zero & size, bg);

    // Luoi ban do (Map grid)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 20; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 18; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Duong quy dao GPS mau (Track route)
    final pts = <Offset>[
      Offset(size.width * 0.08, size.height * 0.72),
      Offset(size.width * 0.22, size.height * 0.32),
      Offset(size.width * 0.40, size.height * 0.58),
      Offset(size.width * 0.58, size.height * 0.24),
      Offset(size.width * 0.76, size.height * 0.65),
      Offset(size.width * 0.92, size.height * 0.30),
    ];

    final basePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      basePath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    basePath.lineTo(pts.last.dx, pts.last.dy);

    // Ve duong nen mo
    canvas.drawPath(
      basePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    // Tinh tien do di chuyen DUA TREN QUANG DUONG THUC TE (distanceKm):
    // Neu dung yen (distanceKm == 0) -> frac = 0.0 -> cham cam dung yen tai diem xuat phat!
    final metrics = basePath.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final frac = ((distanceKm % 1.0) / 1.0).clamp(0.0, 1.0);
    final activeLen = metric.length * frac;
    if (activeLen > 0.5) {
      final activePath = metric.extractPath(0, activeLen);
      canvas.drawPath(
        activePath,
        Paint()
          ..color = const Color(0xFFFC4C02)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Diem xuat phat (Start pin)
    canvas.drawCircle(
      pts.first,
      4.5,
      Paint()..color = const Color(0xFF10B981),
    );

    // Vi tri GPS hien tai cua nguoi chay
    final tangent = metric.getTangentForOffset(activeLen);
    final pos = tangent?.position ?? pts.first;
    canvas.drawCircle(
      pos,
      paused ? 7 : 10,
      Paint()..color = const Color(0xFFFC4C02).withValues(alpha: 0.28),
    );
    canvas.drawCircle(pos, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(pos, 3.8, Paint()..color = const Color(0xFFFC4C02));
  }

  @override
  bool shouldRepaint(covariant _StravaRouteTrackPainter oldDelegate) {
    return oldDelegate.distanceKm != distanceKm || oldDelegate.paused != paused;
  }
}
