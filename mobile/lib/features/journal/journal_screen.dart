import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/day_stats.dart';
import '../../core/meal_slot.dart';
import '../../models/models.dart';
import '../../widgets/empty_state.dart';
import '../stats/statistics_screen.dart' show CsvExportDialog;

// ============================================================
// JOURNAL SCREEN
// ============================================================

class JournalScreen extends StatefulWidget {
  final List<MealEntry> entries;
  final Future<void> Function(MealEntry) onDelete;
  final Future<void> Function(MealEntry)? onEdit;
  final Future<void> Function(MealEntry)? onReLog;

  const JournalScreen({
    super.key,
    required this.entries,
    required this.onDelete,
    this.onEdit,
    this.onReLog,
  });

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  // Truoc day Nhat ky hien TAT CA bua an moi ngay gop lai nen trong nhu
  // "hom nay" -> lech voi Trang chu. Gio xem theo tung ngay.
  DateTime selectedDay = DayStats.dayOnly(DateTime.now());

  DateTime get today => DayStats.dayOnly(DateTime.now());

  void _shiftDay(int delta) {
    final next = selectedDay.add(Duration(days: delta));
    if (next.isAfter(today)) return;
    setState(() => selectedDay = next);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDay,
      firstDate: DateTime(2024),
      lastDate: today,
      helpText: 'Chọn ngày',
    );
    if (picked != null) {
      setState(() => selectedDay = DayStats.dayOnly(picked));
    }
  }

  String _dayLabel(DateTime d) {
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    const weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${weekdays[d.weekday - 1]}, $dd/$mm';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries
        .where((e) => DayStats.isSameDay(e.time, selectedDay))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final groups = {
      for (final slot in MealSlot.all)
        slot: entries.where((e) => e.mealType == slot).toList(),
    };

    final calories = entries.fold<double>(0, (sum, e) => sum + e.calories);
    final isToday = selectedDay == today;
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayEntries = widget.entries
        .where((e) => DayStats.isSameDay(e.time, yesterday))
        .toList();

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nhật ký ăn uống',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 25,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryDark,
                      side: const BorderSide(color: Color(0xFFA7F3D0)),
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const CsvExportDialog(),
                      );
                    },
                    icon: const Icon(Icons.table_chart_outlined, size: 16),
                    label: const Text(
                      'Xuất CSV',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Ngày trước',
                      onPressed: () => _shiftDay(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDay,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 16, color: primaryDark),
                              const SizedBox(width: 8),
                              Text(
                                _dayLabel(selectedDay),
                                style: const TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ngày sau',
                      onPressed: isToday ? null : () => _shiftDay(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primary, primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tổng trong ngày',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          Text(
                            '${calories.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${entries.length} món',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (isToday && yesterdayEntries.isNotEmpty && widget.onReLog != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      for (final m in yesterdayEntries) {
                        await widget.onReLog!(
                          MealEntry(
                            name: m.name,
                            mealType: m.mealType,
                            time: DateTime.now(),
                            portionG: m.portionG,
                            calories: m.calories,
                            proteinG: m.proteinG,
                            fatG: m.fatG,
                            carbsG: m.carbsG,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: Text(
                      'Sao chép nhanh ${yesterdayEntries.length} món từ hôm qua',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryDark,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFA7F3D0)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              if (entries.isEmpty)
                EmptyState(
                  icon: Icons.menu_book_rounded,
                  title: isToday ? 'Hôm nay chưa ghi món nào' : 'Không có ghi chép',
                  subtitle: isToday
                      ? 'Quét món ăn và thêm vào bữa để bắt đầu.'
                      : 'Ngày này bạn chưa ghi lại bữa ăn nào.',
                )
              else
                ...groups.entries
                    .where((group) => group.value.isNotEmpty)
                    .map(
                      (group) => MealSection(
                        title: group.key,
                        entries: group.value,
                        onDelete: widget.onDelete,
                        onEdit: widget.onEdit,
                        onReLog: widget.onReLog,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MealSection extends StatelessWidget {
  final String title;
  final List<MealEntry> entries;
  final Future<void> Function(MealEntry) onDelete;
  final Future<void> Function(MealEntry)? onEdit;
  final Future<void> Function(MealEntry)? onReLog;

  const MealSection({
    super.key,
    required this.title,
    required this.entries,
    required this.onDelete,
    this.onEdit,
    this.onReLog,
  });

  void _openEditDialog(BuildContext context, MealEntry meal) {
    int portionG = meal.portionG > 0 ? meal.portionG : 150;
    final int basePortionG = portionG;
    String selectedSlot = meal.mealType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final scale = portionG / basePortionG;
            final newCal = meal.calories * scale;
            final newP = meal.proteinG * scale;
            final newF = meal.fatG * scale;
            final newCb = meal.carbsG * scale;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_note_rounded, color: primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          meal.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          '${newCal.round()} kcal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: primaryDark,
                            fontSize: 15,
                          ),
                        ),
                        Text('Đạm ${newP.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 12)),
                        Text('Béo ${newF.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 12)),
                        Text('Carb ${newCb.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'Khối lượng khẩu phần:',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: portionG > 50
                            ? () => setModalState(() => portionG -= 50)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      Text(
                        '${portionG}g',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      IconButton(
                        onPressed: portionG < 1200
                            ? () => setModalState(() => portionG += 50)
                            : null,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: MealSlot.all.map((slot) {
                      final active = selectedSlot == slot;
                      return ChoiceChip(
                        label: Text(slot),
                        selected: active,
                        selectedColor: primaryLight,
                        onSelected: (_) => setModalState(() => selectedSlot = slot),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (onReLog != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await onReLog!(
                                MealEntry(
                                  name: meal.name,
                                  mealType: selectedSlot,
                                  time: DateTime.now(),
                                  portionG: portionG,
                                  calories: newCal,
                                  proteinG: newP,
                                  fatG: newF,
                                  carbsG: newCb,
                                ),
                              );
                            },
                            icon: const Icon(Icons.replay_rounded, size: 17),
                            label: const Text('Ghi thêm hôm nay'),
                          ),
                        ),
                      if (onReLog != null && onEdit != null)
                        const SizedBox(width: 10),
                      if (onEdit != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await onEdit!(
                                MealEntry(
                                  id: meal.id,
                                  name: meal.name,
                                  mealType: selectedSlot,
                                  time: meal.time,
                                  portionG: portionG,
                                  calories: newCal,
                                  proteinG: newP,
                                  fatG: newF,
                                  carbsG: newCb,
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(backgroundColor: primary),
                            icon: const Icon(Icons.check_rounded, size: 17),
                            label: const Text('Lưu chỉnh sửa'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final calories = entries.fold<double>(0, (sum, e) => sum + e.calories);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${calories.toStringAsFixed(0)} kcal',
                style: const TextStyle(
                  color: primaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...entries.map(
            (meal) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: PremiumMealTile(
                entry: meal,
                onTap: (onEdit != null || onReLog != null)
                    ? () => _openEditDialog(context, meal)
                    : null,
                onDelete: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa món này?'),
                      content: Text('"${meal.name}" sẽ bị xóa khỏi nhật ký.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Xóa'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await onDelete(meal);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumMealTile extends StatelessWidget {
  final MealEntry entry;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const PremiumMealTile({
    super.key,
    required this.entry,
    this.onDelete,
    this.onTap,
  });

  String timeText() {
    final h = entry.time.hour.toString().padLeft(2, '0');
    final m = entry.time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.restaurant_rounded, color: primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.portionG}g · ${timeText()}${onTap != null ? " · Bấm để sửa" : ""}',
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.calories.toStringAsFixed(0)} kcal',
              style: const TextStyle(
                color: primaryDark,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
          ],
        ),
      ),
    );
  }
}
