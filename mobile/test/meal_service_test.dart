import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/meal_service.dart';

void main() {
  group('MealService & ParsedMealItem Tests', () {
    test('ParsedMealItem.fromJson parses correct numbers and defaults', () {
      final json = {
        'name_vi': 'Phở bò',
        'quantity': '1 tô',
        'portion_g': 500,
        'calories': 480,
        'protein_g': 28.5,
        'fat_g': 14.0,
        'carbs_g': 62.0,
      };

      final item = ParsedMealItem.fromJson(json);

      expect(item.nameVi, equals('Phở bò'));
      expect(item.quantity, equals('1 tô'));
      expect(item.portionG, equals(500));
      expect(item.calories, equals(480.0));
      expect(item.proteinG, equals(28.5));
      expect(item.fatG, equals(14.0));
      expect(item.carbsG, equals(62.0));
    });

    test('ParsedMealResult.fromJson parses multiple items and computes totals', () {
      final json = {
        'meal_type': 'lunch',
        'items': [
          {
            'name_vi': 'Phở bò',
            'quantity': '1 tô',
            'portion_g': 500,
            'calories': 480,
            'protein_g': 28.0,
            'fat_g': 14.0,
            'carbs_g': 62.0,
          },
          {
            'name_vi': 'Trà đá',
            'quantity': '1 ly',
            'portion_g': 250,
            'calories': 5,
            'protein_g': 0.0,
            'fat_g': 0.0,
            'carbs_g': 1.0,
          }
        ],
        'total': {
          'calories': 485,
          'protein_g': 28.0,
          'fat_g': 14.0,
          'carbs_g': 63.0,
        }
      };

      final result = ParsedMealResult.fromJson(json);

      expect(result.mealType, equals('lunch'));
      expect(result.items.length, equals(2));
      expect(result.items[0].nameVi, equals('Phở bò'));
      expect(result.items[1].nameVi, equals('Trà đá'));
      expect(result.totalCalories, equals(485.0));
      expect(result.totalProteinG, equals(28.0));
    });
  });
}
