import 'dart:convert';
import 'package:flutter/material.dart';
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
import '../journal/journal_screen.dart' show PremiumMealTile;
import '../smart_meal_dialog.dart';
import '../stats/statistics_screen.dart'
    show
        WeeklyMealPlanSheet,
        WeeklyClinicalReportDialog,
        AiModelMetricsDialog,
        FoodComparisonDialog;

// ============================================================
// HOME
// ============================================================

class HomeScreen extends StatelessWidget {
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

    final double progress = profile.dailyGoal <= 0
        ? 0
        : (calories / profile.dailyGoal).clamp(0.0, 1.0).toDouble();

    final double remaining = (profile.dailyGoal - calories)
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

    // Chuoi ngay: dung CHUNG 1 cach tinh voi the "ngay lien tiep" ben duoi.
    final caloriesByDay = DayStats.caloriesByDay(entries);
    final streak = DayStats.streak(caloriesByDay);

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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF0F172A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.biotech_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'FoodScan AI',
                                style: GoogleFonts.plusJakartaSans(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: -0.3,
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
                                  'PRO 4.0',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'YOLO26 Ensemble · Gemini Vision · Lâm sàng Cá nhân hóa',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF047857),
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
                        Icons.analytics_outlined,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting(),
                          style: GoogleFonts.plusJakartaSans(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 21,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.displayName.isEmpty
                              ? 'Bạn ơi!'
                              : profile.displayName,
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (streak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              color: Color(0xFFF59E0B),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$streak ngày liên tiếp',
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
                            colors: [Color(0xFF0F172A), Color(0xFF064E3B)],
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
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.22),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF34D399,
                                                ).withValues(alpha: 0.45),
                                              ),
                                            ),
                                            child: const Text(
                                              'NĂNG LƯỢNG & SINH HỌC HÔM NAY',
                                              style: TextStyle(
                                                color: Color(0xFF6EE7B7),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.4,
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
                                                  ' / ${profile.dailyGoal.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF94A3B8),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const TextSpan(
                                              text: ' kcal',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF6EE7B7),
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
                                                ? Icons.bolt_rounded
                                                : Icons.warning_amber_rounded,
                                            size: 15,
                                            color: remaining > 0
                                                ? const Color(0xFF34D399)
                                                : const Color(0xFFF87171),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            remaining > 0
                                                ? 'Còn lại ${remaining.toStringAsFixed(0)} kcal cho hôm nay'
                                                : 'Đã vượt ${(calories - profile.dailyGoal).toStringAsFixed(0)} kcal',
                                            style: TextStyle(
                                              color: remaining > 0
                                                  ? const Color(0xFFA7F3D0)
                                                  : const Color(0xFFFCA5A5),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [primary, primaryDark],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: onScan,
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                          label: Text(
                            'Quét món',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
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
                          icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                          label: Text(
                            'Ghi bằng chữ',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: () => showManualAddSheet(
                      context,
                      baseUrl: AppConfig.baseUrl,
                      onAdd: onManualAdd,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note_rounded, color: accent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Thêm món thủ công',
                          style: GoogleFonts.plusJakartaSans(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ProToolsQuickHub(dailyGoal: profile.dailyGoal),

                // LỜI KHUYÊN & GỢI Ý BỮA TIẾP THEO (AI DAILY LOOP)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
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
                            child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Gợi ý bữa tiếp theo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                          children: remainingAdvice.recommendedFoods.map((food) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: Text(
                                '🥗 $food',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF047857),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SuggestionsCard(
                  baseUrl: AppConfig.baseUrl,
                  userKey: AppSession.currentUserKey,
                  remainingKcal: remaining,
                ),

                const SizedBox(height: 16),

                const ExerciseTrackerCard(),

                const SizedBox(height: 16),

                WaterTrackerCard(
                  baseUrl: AppConfig.baseUrl,
                  userKey: AppSession.currentUserKey,
                ),

                const SizedBox(height: 16),

                StreakInsightCard(
                  dayKcal: caloriesByDay,
                  goalKcal: profile.dailyGoal,
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Bữa ăn hôm nay',

                        style: TextStyle(
                          color: accent,

                          fontWeight: FontWeight.w900,

                          fontSize: 18,
                        ),
                      ),
                    ),

                    if (today.isNotEmpty)
                      TextButton(
                        onPressed: onJournal,

                        child: const Text(
                          'Xem tất cả',

                          style: TextStyle(color: primaryDark),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                if (today.isEmpty)
                  PremiumEmptyMeal(onScan: onScan)
                else
                  ...today
                      .take(4)
                      .map(
                        (meal) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),

                          child: PremiumMealTile(entry: meal),
                        ),
                      ),
              ],
            ),
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
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),
      ),

      child: Column(
        children: [
          const Icon(Icons.restaurant_menu_rounded, color: primary, size: 40),

          const SizedBox(height: 10),

          const Text(
            'Chưa có bữa ăn nào',

            style: TextStyle(fontWeight: FontWeight.w800),
          ),

          TextButton(
            onPressed: onScan,

            child: const Text(
              'Quét ngay',

              style: TextStyle(color: primaryDark),
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

  const _HomeBiomedicalStatusStrip({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.dailyGoal,
    required this.weightKg,
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
    final glLabel = gl < 40 ? 'Thấp' : (gl <= 80 ? 'Vừa' : 'Cao');

    final effectiveCal = hasFood ? calories : dailyGoal * 0.9;
    final delta30d = ((effectiveCal - dailyGoal) * 30.0) / 7700.0;
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
                  'Nutri $grade',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                hasFood ? 'Cân bằng' : 'Sẵn sàng',
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
            color: Colors.white.withValues(alpha: 0.22),
          ),
          Row(
            children: [
              const Icon(
                Icons.bloodtype_outlined,
                size: 14,
                color: Color(0xFFFCD34D),
              ),
              const SizedBox(width: 3),
              Text(
                'GL: $glLabel ($gl)',
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
            color: Colors.white.withValues(alpha: 0.22),
          ),
          Row(
            children: [
              const Icon(
                Icons.trending_down_rounded,
                size: 14,
                color: Color(0xFF93C5FD),
              ),
              const SizedBox(width: 3),
              Text(
                '30d: ${projectedW.toStringAsFixed(1)}kg',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFBFDBFE),
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

  const _ProToolsQuickHub({required this.dailyGoal});

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
                  'PRO AI SUITE',
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
                  'Trợ lý Y khoa, Thực đơn 7 ngày & Thực nghiệm AI',
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
                      builder: (_) => WeeklyMealPlanSheet(dailyGoal: dailyGoal),
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
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Báo cáo & CSV',
                  subtitle: 'Xuất Y khoa / Excel',
                  color: const Color(0xFFD97706),
                  bg: const Color(0xFFFFFBEB),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const WeeklyClinicalReportDialog(),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _hubButton(
                  icon: Icons.precision_manufacturing_rounded,
                  title: 'Thực nghiệm AI',
                  subtitle: 'YOLO26 & Active',
                  color: const Color(0xFF2563EB),
                  bg: const Color(0xFFEFF6FF),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AiModelMetricsDialog(),
                    );
                  },
                ),
              ),
            ],
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

class ExerciseTrackerCard extends StatefulWidget {
  const ExerciseTrackerCard({super.key});

  @override
  State<ExerciseTrackerCard> createState() => _ExerciseTrackerCardState();
}

class _ExerciseTrackerCardState extends State<ExerciseTrackerCard> {
  int _burnedKcal = 0;
  int _totalMinutes = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _burnedKcal = (body['burned_kcal'] as num?)?.toInt() ?? 0;
            _totalMinutes = (body['total_minutes'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _addExercise(String name, int kcal, int mins) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'activity_name': name,
          'burned_kcal': kcal,
          'minutes': mins,
        }),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (mounted) {
          setState(() {
            _burnedKcal = (body['burned_kcal'] as num?)?.toInt() ?? 0;
            _totalMinutes = (body['total_minutes'] as num?)?.toInt() ?? 0;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _resetExercise() async {
    try {
      final res = await http.delete(
        Uri.parse(
          '${AppConfig.baseUrl}/api/exercise/${AppSession.currentUserKey}',
        ),
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _burnedKcal = 0;
          _totalMinutes = 0;
        });
      }
    } catch (_) {}
  }

  Widget _presetChip(String label, String actName, int kcal, int mins) {
    return InkWell(
      onTap: () => _addExercise(actName, kcal, mins),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFFC2410C),
          ),
        ),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_run_rounded,
                  color: Color(0xFFEA580C),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vận động & Đốt Calo hôm nay',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: accent,
                      ),
                    ),
                    Text(
                      _burnedKcal > 0
                          ? 'Đã đốt $_burnedKcal kcal ($_totalMinutes phút) · Cộng thêm quỹ ăn uống'
                          : 'Bấm chọn bài tập để cộng bù quỹ Calo thực (Net Calories)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_burnedKcal > 0)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Đặt lại vận động hôm nay',
                  onPressed: _resetExercise,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetChip('🚶 Đi bộ 30p (-150 kcal)', 'Đi bộ nhanh', 150, 30),
              _presetChip('🏃 Chạy bộ 20p (-220 kcal)', 'Chạy bộ', 220, 20),
              _presetChip('🏋️ Tập Gym 45p (-300 kcal)', 'Tập Gym', 300, 45),
              _presetChip('🚴 Đạp xe 30p (-240 kcal)', 'Đạp xe', 240, 30),
            ],
          ),
        ],
      ),
    );
  }
}
