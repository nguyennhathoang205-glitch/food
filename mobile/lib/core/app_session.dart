import 'package:flutter/foundation.dart';
import '../auth_http.dart';

class AppSession {
  static String _currentUserKey = 'demo-user';
  static String get currentUserKey =>
      (AuthSession.userId != null && AuthSession.userId!.isNotEmpty)
          ? AuthSession.userId!
          : _currentUserKey;
  static set currentUserKey(String v) => _currentUserKey = v;
  static VoidCallback? appLogout;
}
