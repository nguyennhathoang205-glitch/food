// ============================================================
// APP CONFIG & ENVIRONMENT
// ============================================================

import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'Food Scan Pro';
  static const String appVersion = '1.2.0';

  // Configurable base URL:
  // - Local dev on Windows/Web/Desktop: http://localhost:5000
  // - Android Emulator: http://10.0.2.2:5000
  // - Production: Can be replaced with your deployed server (e.g. Render / Railway)
  // Dia chi may chu luc build: flutter build ios --dart-define=API_BASE_URL=https://ten-ban.example.com
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (kIsWeb) return 'http://localhost:5000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      // In physical device debugging or emulator
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  static String baseUrl = defaultBaseUrl;

  static void setBaseUrl(String url) {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
  }
}
