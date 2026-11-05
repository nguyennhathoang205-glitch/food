// ============================================================
// NUTRITION CALCULATOR (Mifflin–St Jeor & Macro Distribution)
// ============================================================

enum Gender { male, female }

enum ActivityLevel {
  sedentary, // It van dong (van phong, ngoi nhieu)
  light, // Van dong nhe (tap the duc 1-3 ngay/tuan)
  moderate, // Van dong vua (tap 3-5 ngay/tuan)
  veryActive, // Van dong nhieu (tap 6-7 ngay/tuan)
  extraActive, // Van dong rat nhieu (lao dong nang / VDV)
}

enum WeightGoal {
  loseWeight, // Giam can (-500 kcal/ngay)
  maintain, // Giu can (TDEE)
  gainWeight, // Tang can (+500 kcal/ngay)
}

class MacroTargets {
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;

  const MacroTargets({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });
}

class RemainingNutritionAdvice {
  final double caloriesLeft;
  final double proteinLeft;
  final double fatLeft;
  final double carbsLeft;
  final String adviceText;
  final List<String> recommendedFoods;

  const RemainingNutritionAdvice({
    required this.caloriesLeft,
    required this.proteinLeft,
    required this.fatLeft,
    required this.carbsLeft,
    required this.adviceText,
    required this.recommendedFoods,
  });
}

class NutritionCalculator {
  /// Tinh Basal Metabolic Rate (BMR) theo cong thuc Mifflin–St Jeor
  /// - Nam: (10 * weight) + (6.25 * height) - (5 * age) + 5
  /// - Nu:  (10 * weight) + (6.25 * height) - (5 * age) - 161
  static double calculateBMR({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
  }) {
    if (weightKg <= 0 || heightCm <= 0 || age <= 0) return 1500.0;

    final base = (10.0 * weightKg) + (6.25 * heightCm) - (5.0 * age);
    return gender == Gender.male ? (base + 5.0) : (base - 161.0);
  }

  /// He so van dong (Activity Multiplier)
  static double getActivityMultiplier(ActivityLevel level) {
    switch (level) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.light:
        return 1.375;
      case ActivityLevel.moderate:
        return 1.55;
      case ActivityLevel.veryActive:
        return 1.725;
      case ActivityLevel.extraActive:
        return 1.9;
    }
  }

  /// Tinh Tong tieu hao nang luong hang ngay (TDEE = BMR * ActivityMultiplier)
  static double calculateTDEE({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
    required ActivityLevel activityLevel,
  }) {
    final bmr = calculateBMR(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    );
    return bmr * getActivityMultiplier(activityLevel);
  }

  /// Tinh muc tieu Calo va phan bo Macro (Protein, Fat, Carbs)
  static MacroTargets calculateTargets({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
    required ActivityLevel activityLevel,
    required WeightGoal goal,
  }) {
    final tdee = calculateTDEE(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
      activityLevel: activityLevel,
    );

    double targetCalories;
    switch (goal) {
      case WeightGoal.loseWeight:
        // Giam can: thâm hụt 500 kcal, nhưng không dưới ngưỡng an toàn (Nam >= 1500, Nữ >= 1200)
        final safeFloor = gender == Gender.male ? 1500.0 : 1200.0;
        targetCalories = (tdee - 500.0).clamp(safeFloor, 4000.0);
        break;
      case WeightGoal.maintain:
        targetCalories = tdee;
        break;
      case WeightGoal.gainWeight:
        // Tang can: thặng dư 400-500 kcal
        targetCalories = tdee + 450.0;
        break;
    }

    // Single Source of Truth: Su dung calculateTargetsForMacroBars de dong nhat 100% macro
    return calculateTargetsForMacroBars(
      goalKcal: targetCalories,
      weightKg: weightKg,
    );
  }

  /// Single Source of Truth: Tinh muc tieu macro dua tren tong calo va can nang
  /// - Protein: 1.8g / kg the trong (neu khong co can nang thi mac dinh 65kg)
  /// - Fat: 25% tong calo / 9 kcal
  /// - Carbs: phan calo con lai / 4 kcal
  static MacroTargets calculateTargetsForMacroBars({
    required double goalKcal,
    double? weightKg,
  }) {
    final weight = (weightKg != null && weightKg > 0) ? weightKg : 65.0;
    final proteinG = (weight * 1.8).clamp(45.0, 220.0);
    final fatKcal = goalKcal * 0.25;
    final fatG = (fatKcal / 9.0).clamp(30.0, 120.0);
    final remainingKcal = goalKcal - (proteinG * 4.0) - (fatG * 9.0);
    final carbsG = (remainingKcal / 4.0).clamp(40.0, 500.0);

    return MacroTargets(
      calories: goalKcal.roundToDouble(),
      proteinG: proteinG.roundToDouble(),
      fatG: fatG.roundToDouble(),
      carbsG: carbsG.roundToDouble(),
    );
  }

  /// Mon "an lai theo thoi quen" tu lich su cac ngay truoc.
  /// - Uu tien mon cung khung bua [currentSlot]; neu chua co thi lay moi bua.
  /// - Xep theo so lan an, nhieu nhat truoc.
  /// - Bo mon da an trong hom nay (khong ghi phan biet hoa thuong).
  static List<String> habitFoods({
    required List<({String name, String mealType})> history,
    required String currentSlot,
    List<String> eatenToday = const [],
    int limit = 5,
  }) {
    final eaten = eatenToday.map((e) => e.trim().toLowerCase()).toSet();
    final sameSlot = history.where((m) => m.mealType == currentSlot).toList();
    final source = sameSlot.isNotEmpty ? sameSlot : history;

    final counts = <String, int>{};
    final display = <String, String>{};
    for (final m in source) {
      final key = m.name.trim().toLowerCase();
      if (key.isEmpty || eaten.contains(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => m.name.trim());
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys.take(limit).map((k) => display[k]!).toList();
  }

  /// Sinh loi khuyen va goi y mon an thong minh:
  /// - Kiem tra di ung (sua, trung, dau nanh, hai san, gluten, me...)
  /// - Kiem tra benh ly (tieu duong, gout, huyet ap cao, mo mau...)
  /// - Loc bo cac mon nguy hai, uu tien mon lanh manh phu hop ho so suc khoe
  static RemainingNutritionAdvice analyzeRemaining({
    required MacroTargets target,
    required double consumedCalories,
    required double consumedProteinG,
    required double consumedFatG,
    required double consumedCarbsG,
    List<String> userAllergies = const [],
    List<String> userConditions = const [],
    List<String> userRecentFoods = const [],
  }) {
    final calLeft = target.calories - consumedCalories;
    final pLeft = target.proteinG - consumedProteinG;
    final fLeft = target.fatG - consumedFatG;
    final cLeft = target.carbsG - consumedCarbsG;

    final pool = <String>[];
    String advice;

    final allergiesLower = userAllergies.map((e) => e.toLowerCase()).toList();
    final conditionsLower = userConditions.map((e) => e.toLowerCase()).toList();

    bool isAllergicTo(String food) {
      final f = food.toLowerCase();
      // Di ung sua & che pham sua
      if (allergiesLower.any((a) => a.contains('sữa') || a.contains('milk')) &&
          (f.contains('sữa') || f.contains('phô mai') || f.contains('kem'))) {
        return true;
      }
      // Di ung trung
      if (allergiesLower.any((a) => a.contains('trứng') || a.contains('egg')) &&
          f.contains('trứng')) {
        return true;
      }
      // Di ung dau nanh / dau phong
      if (allergiesLower.any((a) => a.contains('đậu') || a.contains('soy')) &&
          (f.contains('đậu phụ') || f.contains('đậu nành') || f.contains('đậu phộng') || f.contains('lạc'))) {
        return true;
      }
      // Di ung hai san (tom, cua, ca, muc)
      if (allergiesLower.any((a) => a.contains('hải sản') || a.contains('tôm') || a.contains('cua')) &&
          (f.contains('tôm') || f.contains('cua') || f.contains('mực') || f.contains('cá'))) {
        return true;
      }
      // Di ung Gluten / lua mi / yen mach
      if (allergiesLower.any((a) => a.contains('gluten') || a.contains('lúa mì') || a.contains('wheat')) &&
          (f.contains('bánh mì') || f.contains('ngũ cốc') || f.contains('mì') || f.contains('lúa mì') || f.contains('yến mạch') || f.contains('nui'))) {
        return true;
      }
      // Di ung Me / Vung / Sesame
      if (allergiesLower.any((a) => a.contains('mè') || a.contains('vừng') || a.contains('sesame')) &&
          (f.contains('mè') || f.contains('vừng'))) {
        return true;
      }
      return false;
    }

    bool isUnhealthyForCondition(String food) {
      final f = food.toLowerCase();
      // Tieu duong: loai bo chuoi chin ngot, che, do ngot
      if (conditionsLower.any((c) => c.contains('tiểu đường')) &&
          (f.contains('chuối') || f.contains('chè') || f.contains('nước ngọt') || f.contains('xôi'))) {
        return true;
      }
      // Gout: loai bo thit bo, hai san, noi tang
      if (conditionsLower.any((c) => c.contains('gout')) &&
          (f.contains('thịt bò') || f.contains('tôm') || f.contains('mực') || f.contains('lòng'))) {
        return true;
      }
      // Mo mau / Cholesterol cao: loai bo mo, chien, ran
      if (conditionsLower.any((c) => c.contains('mỡ máu') || c.contains('cholesterol')) &&
          (f.contains('mỡ') || f.contains('chiên') || f.contains('rán'))) {
        return true;
      }
      return false;
    }

    if (calLeft <= 0) {
      advice = 'Bạn đã đạt hoặc vượt chỉ tiêu calo hôm nay. Hãy uống thêm nước lọc và hạn chế ăn vặt ban đêm.';
      pool.addAll(['Trà xanh', 'Nước chanh ấm', 'Dưa chuột thái lát']);
    } else if (pLeft > 25) {
      advice = 'Hôm nay bạn còn thiếu ${(pLeft).toStringAsFixed(0)}g đạm (protein). Bữa tiếp theo nên ưu tiên các món giàu protein nạc phù hợp sức khỏe.';
      pool.addAll(['Ức gà áp chảo', 'Đậu phụ sốt cà chua', 'Trứng gà luộc', 'Cá hồi hấp', 'Tôm luộc', 'Sữa chua Hy Lạp', 'Thịt lợn nạc luộc']);
    } else if (cLeft > 50) {
      advice = 'Năng lượng từ tinh bột còn thiếu. Nên bổ sung tinh bột chuyển hóa chậm (GI thấp) để giữ năng lượng bền bỉ.';
      pool.addAll(['Yến mạch ngâm', 'Khoai lang luộc', 'Cơm gạo lứt', 'Bánh mì ngũ cốc nguyên cám', 'Chuối chín']);
    } else {
      advice = 'Chế độ ăn hôm nay của bạn rất cân bằng! Còn thiếu khoảng ${(calLeft).toStringAsFixed(0)} kcal cho một bữa nhẹ.';
      pool.addAll(['Hạt hạnh nhân', 'Táo xanh', 'Salad ức gà rau củ', 'Sữa chua không đường', 'Dưa chuột']);
    }

    // Loc bo mon di ung va benh ly
    final filtered = pool.where((item) => !isAllergicTo(item) && !isUnhealthyForCondition(item)).toList();

    // Mon theo thoi quen: giu toi da 2 cho trong 5 goi y de chac chan hien ra
    // (truoc day add vao cuoi roi take(5) nen gan nhu khong bao gio thay).
    final habits = userRecentFoods
        .where((f) => !filtered.contains(f) && !isAllergicTo(f) && !isUnhealthyForCondition(f))
        .take(2)
        .toList();
    final suggestions = [...filtered.take(5 - habits.length), ...habits];

    return RemainingNutritionAdvice(
      caloriesLeft: calLeft,
      proteinLeft: pLeft,
      fatLeft: fLeft,
      carbsLeft: cLeft,
      adviceText: advice,
      recommendedFoods: suggestions,
    );
  }
}
