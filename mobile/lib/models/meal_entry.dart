// ============================================================
// MEAL ENTRY MODEL
// ============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

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
  final String? thumb;

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
    this.thumb,
  });

  /// Nen anh chup mon an thanh JPEG base64 nho (~8-15KB) de luu kem nhat ky.
  static String? makeThumbnailBase64(Uint8List? rawBytes, {int maxSide = 160}) {
    if (rawBytes == null || rawBytes.isEmpty) return null;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;
      final resized = decoded.width >= decoded.height
          ? img.copyResize(
              decoded,
              width: decoded.width > maxSide ? maxSide : decoded.width,
            )
          : img.copyResize(
              decoded,
              height: decoded.height > maxSide ? maxSide : decoded.height,
            );
      final jpg = img.encodeJpg(resized, quality: 72);
      return base64Encode(jpg);
    } catch (_) {
      return null;
    }
  }

  factory MealEntry.fromJson(Map<String, dynamic> json) {
    DateTime date;
    try {
      date = DateTime.parse(json['created_at']).toLocal();
    } catch (_) {
      date = DateTime.now();
    }

    final rawThumb = json['thumb'];
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
      thumb: (rawThumb is String && rawThumb.isNotEmpty) ? rawThumb : null,
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
      if (thumb != null && thumb!.isNotEmpty) 'thumb': thumb,
    };
  }
}
