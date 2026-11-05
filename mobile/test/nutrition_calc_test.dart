import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/nutrition_calc.dart';

void main() {
  group('NutritionCalculator - Mifflin–St Jeor BMR Tests', () {
    test('calculateBMR for Male (70kg, 175cm, 25 years old)', () {
      // BMR = (10 * 70) + (6.25 * 175) - (5 * 25) + 5
      //     = 700 + 1093.75 - 125 + 5 = 1673.75
      final bmr = NutritionCalculator.calculateBMR(
        weightKg: 70,
        heightCm: 175,
        age: 25,
        gender: Gender.male,
      );
      expect(bmr, closeTo(1673.75, 0.01));
    });

    test('calculateBMR for Female (55kg, 160cm, 28 years old)', () {
      // BMR = (10 * 55) + (6.25 * 160) - (5 * 28) - 161
      //     = 550 + 1000 - 140 - 161 = 1249.0
      final bmr = NutritionCalculator.calculateBMR(
        weightKg: 55,
        heightCm: 160,
        age: 28,
        gender: Gender.female,
      );
      expect(bmr, closeTo(1249.0, 0.01));
    });

    test('calculateBMR handles invalid input safely', () {
      final bmr = NutritionCalculator.calculateBMR(
        weightKg: 0,
        heightCm: 0,
        age: 0,
        gender: Gender.male,
      );
      expect(bmr, equals(1500.0));
    });
  });

  group('NutritionCalculator - TDEE & Goals Tests', () {
    test('calculateTDEE with Moderate activity (multiplier 1.55)', () {
      // 1673.75 * 1.55 = 2594.3125
      final tdee = NutritionCalculator.calculateTDEE(
        weightKg: 70,
        heightCm: 175,
        age: 25,
        gender: Gender.male,
        activityLevel: ActivityLevel.moderate,
      );
      expect(tdee, closeTo(2594.31, 0.1));
    });

    test('calculateTargets for loseWeight reduces 500 kcal', () {
      final targets = NutritionCalculator.calculateTargets(
        weightKg: 70,
        heightCm: 175,
        age: 25,
        gender: Gender.male,
        activityLevel: ActivityLevel.moderate,
        goal: WeightGoal.loseWeight,
      );
      // TDEE ~2594, Target ~ 2094
      expect(targets.calories, closeTo(2094.0, 2.0));
      // Protein: 70 * 1.8 = 126g
      expect(targets.proteinG, equals(126.0));
      expect(targets.fatG, greaterThan(30.0));
      expect(targets.carbsG, greaterThan(50.0));
    });

    test('calculateTargets enforces safe minimum calorie floor', () {
      final femaleTargets = NutritionCalculator.calculateTargets(
        weightKg: 40,
        heightCm: 145,
        age: 40,
        gender: Gender.female,
        activityLevel: ActivityLevel.sedentary,
        goal: WeightGoal.loseWeight,
      );
      // Should not fall below 1200 kcal safe limit for female
      expect(femaleTargets.calories, greaterThanOrEqualTo(1200.0));
    });
  });

  group('NutritionCalculator - Remaining Nutrition Advice Tests', () {
    test('Alerts protein deficit when missing >25g protein', () {
      const target = MacroTargets(
        calories: 2000,
        proteinG: 130,
        fatG: 60,
        carbsG: 235,
      );
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1000,
        consumedProteinG: 60, // Missing 70g protein
        consumedFatG: 30,
        consumedCarbsG: 120,
      );
      expect(advice.proteinLeft, equals(70.0));
      expect(advice.adviceText, contains('đạm (protein)'));
      expect(advice.recommendedFoods, contains('Ức gà áp chảo'));
    });

    test('Congratulates when calories are met or exceeded', () {
      const target = MacroTargets(
        calories: 1800,
        proteinG: 100,
        fatG: 50,
        carbsG: 200,
      );
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1850,
        consumedProteinG: 95,
        consumedFatG: 50,
        consumedCarbsG: 210,
      );
      expect(advice.caloriesLeft, lessThanOrEqualTo(0));
      expect(advice.adviceText, contains('đạt hoặc vượt chỉ tiêu'));
    });

    test('Filters out Dairy (Sữa chua) when user has milk allergy', () {
      const target = MacroTargets(calories: 2000, proteinG: 130, fatG: 60, carbsG: 235);
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1000,
        consumedProteinG: 60, // Deficit
        consumedFatG: 30,
        consumedCarbsG: 120,
        userAllergies: ['sữa'],
      );
      expect(advice.recommendedFoods.any((f) => f.contains('Sữa chua')), isFalse);
    });

    test('Filters out Gluten (Bánh mì, Yến mạch) when user has gluten allergy', () {
      const target = MacroTargets(calories: 2000, proteinG: 130, fatG: 60, carbsG: 235);
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1000,
        consumedProteinG: 120,
        consumedFatG: 50,
        consumedCarbsG: 50, // Carbs deficit
        userAllergies: ['gluten'],
      );
      expect(advice.recommendedFoods.any((f) => f.contains('Bánh mì')), isFalse);
      expect(advice.recommendedFoods.any((f) => f.contains('Yến mạch')), isFalse);
    });

    test('Filters out Banana (Chuối) when user has diabetes', () {
      const target = MacroTargets(calories: 2000, proteinG: 130, fatG: 60, carbsG: 235);
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1000,
        consumedProteinG: 120,
        consumedFatG: 50,
        consumedCarbsG: 50, // Carbs deficit
        userConditions: ['tiểu đường'],
      );
      expect(advice.recommendedFoods.any((f) => f.contains('Chuối')), isFalse);
    });

    test('Unifies calculateTargets with calculateTargetsForMacroBars', () {
      final tdeeTargets = NutritionCalculator.calculateTargets(
        weightKg: 70,
        heightCm: 175,
        age: 25,
        gender: Gender.male,
        activityLevel: ActivityLevel.moderate,
        goal: WeightGoal.maintain,
      );
      final barTargets = NutritionCalculator.calculateTargetsForMacroBars(
        goalKcal: tdeeTargets.calories,
        weightKg: 70,
      );
      expect(tdeeTargets.proteinG, equals(barTargets.proteinG));
      expect(tdeeTargets.fatG, equals(barTargets.fatG));
      expect(tdeeTargets.carbsG, equals(barTargets.carbsG));
    });

    test('habitFoods: uu tien cung khung bua, xep theo so lan, bo mon hom nay', () {
      final foods = NutritionCalculator.habitFoods(
        history: const [
          (name: 'Phở bò', mealType: 'Bữa sáng'),
          (name: 'Bánh mì', mealType: 'Bữa sáng'),
          (name: 'Phở bò', mealType: 'Bữa sáng'),
          (name: 'Cơm tấm', mealType: 'Bữa trưa'),
          (name: 'Xôi gà', mealType: 'Bữa sáng'),
        ],
        currentSlot: 'Bữa sáng',
        eatenToday: const ['xôi gà'],
      );
      expect(foods.first, 'Phở bò');
      expect(foods, isNot(contains('Cơm tấm')));
      expect(foods, isNot(contains('Xôi gà')));
    });

    test('Mon thoi quen luon co cho trong 5 goi y', () {
      const target = MacroTargets(calories: 2000, proteinG: 130, fatG: 60, carbsG: 235);
      final advice = NutritionCalculator.analyzeRemaining(
        target: target,
        consumedCalories: 1000,
        consumedProteinG: 60,
        consumedFatG: 30,
        consumedCarbsG: 120,
        userRecentFoods: const ['Phở bò'],
      );
      expect(advice.recommendedFoods.length, lessThanOrEqualTo(5));
      expect(advice.recommendedFoods, contains('Phở bò'));
    });
  });
}
