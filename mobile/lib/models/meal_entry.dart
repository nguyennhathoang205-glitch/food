// ============================================================
// MEAL ENTRY MODEL
// ============================================================

import '../core/app_session.dart';
import '../core/meal_slot.dart';

class MealEntry {
  final int? id;
  final String name;
  final String mealType;
  final DateTime time;
  final int portionG;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;

  MealEntry({
    this.id,
    required this.name,
    required this.mealType,
    required this.time,
    required this.portionG,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory MealEntry.fromJson(Map<String, dynamic> json) {
    DateTime date;
    try {
      date = DateTime.parse(json['created_at']).toLocal();
    } catch (_) {
      date = DateTime.now();
    }

    return MealEntry(
      id: (json['id'] as num?)?.toInt(),
      name: json['food_name'] ?? 'Không rõ',
      mealType: MealSlot.normalize(json['meal_type'] as String?, fallbackTime: date),
      time: date,
      portionG: (json['portion_g'] as num?)?.toInt() ?? 150,
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson([String? defaultKey]) {
    return {
      'user_key': defaultKey ?? AppSession.currentUserKey,
      'food_name': name,
      'meal_type': mealType,
      'portion_g': portionG,
      'calories': calories,
      'protein_g': proteinG,
      'fat_g': fatG,
      'carbs_g': carbsG,
    };
  }
}
