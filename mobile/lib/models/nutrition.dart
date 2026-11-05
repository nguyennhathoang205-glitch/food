// ============================================================
// NUTRITION & TOTAL NUTRITION MODELS
// ============================================================

class Nutrition {
  final double? calories;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;

  Nutrition({this.calories, this.proteinG, this.fatG, this.carbsG});

  factory Nutrition.fromJson(Map<String, dynamic> json) {
    return Nutrition(
      calories: (json['calories'] as num?)?.toDouble(),
      proteinG: (json['protein_g'] as num?)?.toDouble(),
      fatG: (json['fat_g'] as num?)?.toDouble(),
      carbsG: (json['carbs_g'] as num?)?.toDouble(),
    );
  }
}

class TotalNutrition {
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;

  const TotalNutrition({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory TotalNutrition.fromJson(Map<String, dynamic> json) {
    return TotalNutrition(
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    );
  }
}
