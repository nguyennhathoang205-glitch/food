// ============================================================
// USER PROFILE MODEL
// ============================================================

import '../core/app_session.dart';

class UserProfile {
  final String userKey;
  final String displayName;
  final double? heightCm;
  final double? weightKg;
  final double dailyGoal;

  UserProfile({
    required this.userKey,
    required this.displayName,
    required this.heightCm,
    required this.weightKg,
    required this.dailyGoal,
  });

  factory UserProfile.empty([String? defaultKey]) {
    return UserProfile(
      userKey: defaultKey ?? AppSession.currentUserKey,
      displayName: 'Người dùng Food Scan',
      heightCm: null,
      weightKg: null,
      dailyGoal: 2000,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json, [String? defaultKey]) {
    return UserProfile(
      userKey: json['user_key'] ?? defaultKey ?? AppSession.currentUserKey,
      displayName: json['display_name'] ?? 'Người dùng Food Scan',
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      dailyGoal: (json['daily_goal'] as num?)?.toDouble() ?? 2000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'display_name': displayName,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'daily_goal': dailyGoal,
    };
  }

  UserProfile copyWith({
    String? userKey,
    String? displayName,
    double? heightCm,
    double? weightKg,
    double? dailyGoal,
  }) {
    return UserProfile(
      userKey: userKey ?? this.userKey,
      displayName: displayName ?? this.displayName,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      dailyGoal: dailyGoal ?? this.dailyGoal,
    );
  }
}
