import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/day_stats.dart';
import 'package:mobile/models/models.dart';

MealEntry meal(DateTime t, double kcal) => MealEntry(
      name: 'Món',
      mealType: 'Bữa trưa',
      time: t,
      portionG: 100,
      calories: kcal,
      proteinG: 0,
      fatG: 0,
      carbsG: 0,
    );

void main() {
  final now = DateTime(2026, 10, 30, 20); // Thu 6

  group('DayStats', () {
    test('Trung binh chi chia cho ngay CO GHI, khong chia 7', () {
      final byDay = DayStats.caloriesByDay([
        meal(DateTime(2026, 10, 29, 9), 750),
        meal(DateTime(2026, 10, 29, 12), 185),
      ]);
      final r = DayStats.weeklyAverage(byDay, now: now);
      expect(r.loggedDays, 1);
      expect(r.average, 935);
    });

    test('Chuoi ngay: hom nay chua ghi van tinh den hom qua', () {
      final byDay = DayStats.caloriesByDay([
        meal(DateTime(2026, 10, 27, 12), 500),
        meal(DateTime(2026, 10, 28, 12), 500),
        meal(DateTime(2026, 10, 29, 12), 500),
      ]);
      expect(DayStats.streak(byDay, now: now), 3);
    });

    test('Chuoi ngay bi dut khi bo trong 1 ngay', () {
      final byDay = DayStats.caloriesByDay([
        meal(DateTime(2026, 10, 27, 12), 500),
        meal(DateTime(2026, 10, 29, 12), 500),
        meal(DateTime(2026, 10, 30, 8), 500),
      ]);
      expect(DayStats.streak(byDay, now: now), 2);
    });

    test('Khong co du lieu -> chuoi 0, trung binh 0', () {
      final byDay = DayStats.caloriesByDay([]);
      expect(DayStats.streak(byDay, now: now), 0);
      expect(DayStats.weeklyAverage(byDay, now: now).average, 0);
    });
  });
}
