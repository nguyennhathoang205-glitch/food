// ============================================================
// OFFLINE SERVICE - quet/ghi bua an khi khong co mang
//  - OfflineFoods : bang dinh duong 88 mon dong goi san trong app
//  - OfflineMealQueue : hang doi bua an chua gui, tu dong dong bo khi co mang
// ============================================================

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineFood {
  final int classId;
  final String nameVi;
  final double calories;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final int portionG;

  const OfflineFood({
    required this.classId,
    required this.nameVi,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.portionG,
  });

  factory OfflineFood.fromJson(Map<String, dynamic> j) => OfflineFood(
        classId: (j['class_id'] as num?)?.toInt() ?? 0,
        nameVi: (j['name_vi'] ?? '').toString(),
        calories: (j['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toDouble() ?? 0,
        fatG: (j['fat_g'] as num?)?.toDouble() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toDouble() ?? 0,
        portionG: (j['portion_g'] as num?)?.toInt() ?? 250,
      );
}

/// True neu loi la loi mang (mat ket noi, backend tat, timeout).
bool isNetworkError(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed to fetch') ||
      s.contains('TimeoutException') ||
      s.contains('Connection');
}

class OfflineFoods {
  static List<OfflineFood>? _cache;

  static Future<List<OfflineFood>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/foods_offline.json');
    final list = (jsonDecode(raw) as List)
        .whereType<Map<String, dynamic>>()
        .map(OfflineFood.fromJson)
        .where((f) => f.nameVi.isNotEmpty)
        .toList();
    _cache = list;
    return list;
  }
}

class OfflineMealQueue {
  static const _key = 'offline_meal_queue_v1';

  static Future<List<Map<String, dynamic>>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  static Future<int> count() async => (await _read()).length;

  static Future<void> enqueue(Map<String, dynamic> mealJson) async {
    final items = await _read();
    items.add({...mealJson, 'queued_at': DateTime.now().toIso8601String()});
    await _write(items);
  }

  /// Gui lai cac bua da luu offline. [send] tra true neu gui thanh cong.
  /// Tra ve so bua da dong bo.
  static Future<int> flush(
    Future<bool> Function(Map<String, dynamic> meal) send,
  ) async {
    final items = await _read();
    if (items.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final m in items) {
      var ok = false;
      try {
        ok = await send(m);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        synced++;
      } else {
        remaining.add(m);
      }
    }
    await _write(remaining);
    return synced;
  }
}

