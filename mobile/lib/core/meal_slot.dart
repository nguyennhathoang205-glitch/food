// ============================================================
// KHUNG BUA AN - nguon duy nhat cho ten bua va khung gio
// ============================================================

class MealSlot {
  static const breakfast = 'Bữa sáng';
  static const lunch = 'Bữa trưa';
  static const dinner = 'Bữa tối';
  static const snack = 'Ăn phụ';

  static const all = [breakfast, lunch, dinner, snack];

  /// Bua an tuong ung voi thoi diem [time].
  static String forTime(DateTime time) {
    final h = time.hour;
    if (h >= 5 && h < 10) return breakfast;
    if (h >= 10 && h < 14) return lunch;
    if (h >= 14 && h < 17) return snack;
    if (h >= 17 && h < 21) return dinner;
    return snack; // khuya
  }

  /// Dua moi kieu ghi (breakfast, 'Bữa phụ', ...) ve 4 ten chuan o tren,
  /// de du lieu cu luu bang tieng Anh van hien dung trong Nhat ky.
  static String normalize(String? raw, {DateTime? fallbackTime}) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'breakfast':
      case 'bữa sáng':
        return breakfast;
      case 'lunch':
      case 'bữa trưa':
        return lunch;
      case 'dinner':
      case 'bữa tối':
        return dinner;
      case 'snack':
      case 'bữa phụ':
      case 'ăn phụ':
        return snack;
      default:
        return fallbackTime != null ? forTime(fallbackTime) : lunch;
    }
  }
}
