// ============================================================
// MEAL & AI SERVICE (Log, Parse Text, Feedback)
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../auth_http.dart' as http;
import '../core/app_config.dart';

class ParsedMealItem {
  final String nameVi;
  final String quantity;
  final int portionG;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;

  ParsedMealItem({
    required this.nameVi,
    required this.quantity,
    required this.portionG,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory ParsedMealItem.fromJson(Map<String, dynamic> json) {
    return ParsedMealItem(
      nameVi: json['name_vi'] ?? 'Món ăn',
      quantity: json['quantity'] ?? '1 phần',
      portionG: (json['portion_g'] as num?)?.toInt() ?? 150,
      calories: (json['calories'] as num?)?.toDouble() ?? 0.0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0.0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0.0,
      carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ParsedMealResult {
  final String mealType;
  final List<ParsedMealItem> items;
  final double totalCalories;
  final double totalProteinG;
  final double totalFatG;
  final double totalCarbsG;

  ParsedMealResult({
    required this.mealType,
    required this.items,
    required this.totalCalories,
    required this.totalProteinG,
    required this.totalFatG,
    required this.totalCarbsG,
  });

  factory ParsedMealResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    final itemsList = rawItems.map((e) => ParsedMealItem.fromJson(e)).toList();
    final tot = json['total'] as Map<String, dynamic>? ?? {};

    return ParsedMealResult(
      mealType: json['meal_type'] ?? 'lunch',
      items: itemsList,
      totalCalories: (tot['calories'] as num?)?.toDouble() ?? 0.0,
      totalProteinG: (tot['protein_g'] as num?)?.toDouble() ?? 0.0,
      totalFatG: (tot['fat_g'] as num?)?.toDouble() ?? 0.0,
      totalCarbsG: (tot['carbs_g'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MealService {
  /// Parse natural language text into structured meal items with Gemini / fallback
  static Future<ParsedMealResult?> parseMealFromText({
    required String text,
    String mealType = 'lunch',
    String? baseUrl,
  }) async {
    final url = Uri.parse('${baseUrl ?? AppConfig.baseUrl}/api/meals/parse-text');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'meal_type': mealType,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data['status'] == 'ok') {
          return ParsedMealResult.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('Error parsing meal text: $e');
    }
    return null;
  }

  /// Create a meal log entry
  static Future<bool> createMealLog({
    required String userKey,
    required String foodName,
    required String mealType,
    required int portionG,
    required double calories,
    required double proteinG,
    required double fatG,
    required double carbsG,
    String? baseUrl,
  }) async {
    final url = Uri.parse('${baseUrl ?? AppConfig.baseUrl}/api/meals');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_key': userKey,
          'food_name': foodName,
          'meal_type': mealType,
          'portion_g': portionG,
          'calories': calories,
          'protein_g': proteinG,
          'fat_g': fatG,
          'carbs_g': carbsG,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating meal log: $e');
      return false;
    }
  }

  /// Send user correction to feedback endpoint for Active Learning
  static Future<bool> sendScanFeedback({
    required String userKey,
    required String predictedName,
    required String correctedName,
    int? predictedClassId,
    int? correctedClassId,
    double? confidence,
    String? imageBase64,
    Map<String, dynamic>? boundingBox,
    String? baseUrl,
  }) async {
    final url = Uri.parse('${baseUrl ?? AppConfig.baseUrl}/api/feedback');
    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_key': userKey,
          'predicted_name': predictedName,
          'corrected_name': correctedName,
          'predicted_class_id': predictedClassId,
          'corrected_class_id': correctedClassId,
          'predicted_confidence': confidence ?? 0.0,
          'image_base64': imageBase64,
          'bounding_box': boundingBox,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error sending feedback: $e');
      return false;
    }
  }
}
