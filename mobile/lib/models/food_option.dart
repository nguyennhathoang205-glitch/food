// ============================================================
// FOOD OPTION MODEL
// ============================================================

class FoodOption {
  final int id;
  final String nameVi;
  final String nameEn;
  final String? category;
  final double caloriesPer100g;
  final double proteinG;
  final double fatG;
  final double carbsG;

  FoodOption({
    required this.id,
    required this.nameVi,
    required this.nameEn,
    required this.category,
    required this.caloriesPer100g,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory FoodOption.fromJson(Map<String, dynamic> json) {
    return FoodOption(
      id: (json['id'] as num).toInt(),
      nameVi: json['name_vi'] ?? 'Không rõ',
      nameEn: json['name_en'] ?? '',
      category: json['category'],
      caloriesPer100g: (json['calories_per_100g'] as num?)?.toDouble() ?? 0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    );
  }
}
