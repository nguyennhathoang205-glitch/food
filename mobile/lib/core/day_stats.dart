// ============================================================
// THONG KE THEO NGAY - nguon duy nhat cho chuoi ngay, trung binh calo
// (truoc day Trang chu va Thong ke moi noi tu tinh 1 kieu nen lech nhau)
// ============================================================

import '../models/models.dart';

class DayStats {
  /// So ngay toi thieu co ghi chep moi dua ra nhan xet xu huong.
  static const minDaysForInsight = 3;

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Tong calo theo tung ngay (chi gom ngay co ghi chep).
  static Map<DateTime, double> caloriesByDay(List<MealEntry> entries) {
    final map = <DateTime, double>{};
    for (final e in entries) {
      final d = dayOnly(e.time);
      map[d] = (map[d] ?? 0) + e.calories;
    }
    return map;
  }

  /// So ngay ghi chep lien tiep tinh den hom nay. Hom nay chua ghi thi
  /// van tinh chuoi den hom qua (chua bi dut).
  static int streak(Map<DateTime, double> byDay, {DateTime? now}) {
    var day = dayOnly(now ?? DateTime.now());
    if (!byDay.containsKey(day)) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (byDay.containsKey(day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// 7 ngay gan nhat, ngay cu nhat dung truoc.
  static List<DateTime> lastWeek({DateTime? now}) {
    final today = dayOnly(now ?? DateTime.now());
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  /// Trung binh calo tren CAC NGAY CO GHI (khong chia cho ngay trong,
  /// vi ngay trong la thieu du lieu chu khong phai an 0 kcal).
  static ({double average, int loggedDays}) weeklyAverage(
    Map<DateTime, double> byDay, {
    DateTime? now,
  }) {
    final logged = lastWeek(now: now).where(byDay.containsKey).toList();
    if (logged.isEmpty) return (average: 0, loggedDays: 0);
    final sum = logged.fold<double>(0, (s, d) => s + byDay[d]!);
    return (average: sum / logged.length, loggedDays: logged.length);
  }
}
