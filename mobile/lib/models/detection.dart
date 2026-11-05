// ============================================================
// DETECTION MODEL
// ============================================================

import 'dart:ui';
import 'nutrition.dart';

class Detection {
  final int classId;
  final String nameVi;
  final String nameEn;
  final String? category;
  final double confidence;
  final int? portionG;
  final Nutrition nutrition;
  final Rect box;

  Detection({
    required this.classId,
    required this.nameVi,
    required this.nameEn,
    required this.category,
    required this.confidence,
    required this.portionG,
    required this.nutrition,
    required this.box,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    final b = json['bounding_box'];

    return Detection(
      classId: json['class_id'],
      nameVi: json['name_vi'] ?? json['class_name'] ?? 'Không rõ',
      nameEn: json['name_en'] ?? '',
      category: json['category'],
      confidence: (json['confidence'] as num).toDouble(),
      portionG: json['estimated_portion_g'],
      nutrition: json['nutrition'] != null
          ? Nutrition.fromJson(json['nutrition'])
          : Nutrition(),
      box: Rect.fromLTRB(
        (b['x1'] as num).toDouble(),
        (b['y1'] as num).toDouble(),
        (b['x2'] as num).toDouble(),
        (b['y2'] as num).toDouble(),
      ),
    );
  }

  Color get confidenceColor {
    if (confidence >= 0.75) {
      return const Color(0xFF22A06B);
    }
    if (confidence >= 0.5) {
      return const Color(0xFFE8A02A);
    }
    return const Color(0xFFE0483C);
  }
}
