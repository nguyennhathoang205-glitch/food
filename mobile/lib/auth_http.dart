import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as h;
import 'package:shared_preferences/shared_preferences.dart';

// Re-export toan bo package:http (tru get/post/put/delete/MultipartRequest) de
// cac file chi can doi import thanh 'auth_http.dart' as http la moi request goi
// API tu dong kem token dang nhap.
export 'package:http/http.dart' hide get, post, put, delete, MultipartRequest;

class MultipartRequest extends h.MultipartRequest {
  MultipartRequest(super.method, super.url) {
    if (AuthSession.token != null) {
      headers['Authorization'] = 'Bearer ${AuthSession.token}';
    }
  }
}

/// Phien dang nhap hien tai (luu ben vung bang SharedPreferences).
class AuthSession {
  static String? token;
  static String? userId;
  static String? name;
  static String? email;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      token = p.getString('auth_token');
      userId = p.getString('auth_uid');
      name = p.getString('auth_name');
      email = p.getString('auth_email');
    } catch (e) {
      // Phong truong hop Flutter Web chua duoc build lai sau khi them plugin
      debugPrint('[AuthSession] SharedPreferences fallback to memory: $e');
    }
  }

  static Future<void> save({
    required String token,
    required String userId,
    required String name,
    required String email,
  }) async {
    AuthSession.token = token;
    AuthSession.userId = userId;
    AuthSession.name = name;
    AuthSession.email = email;

    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('auth_token', token);
      await p.setString('auth_uid', userId);
      await p.setString('auth_name', name);
      await p.setString('auth_email', email);
    } catch (_) {}
  }

  static Future<void> clear() async {
    token = null;
    userId = null;
    name = null;
    email = null;

    try {
      final p = await SharedPreferences.getInstance();
      for (final k in ['auth_token', 'auth_uid', 'auth_name', 'auth_email']) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}

Map<String, String> _withAuth(Map<String, String>? headers) => {
  ...?headers,
  if (AuthSession.token != null) 'Authorization': 'Bearer ${AuthSession.token}',
};

Future<h.Response> get(Uri url, {Map<String, String>? headers}) =>
    h.get(url, headers: _withAuth(headers));

Future<h.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => h.post(
  url,
  headers: _withAuth(headers),
  body: body,
  encoding: encoding,
);

Future<h.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => h.put(
  url,
  headers: _withAuth(headers),
  body: body,
  encoding: encoding,
);

Future<h.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => h.delete(
  url,
  headers: _withAuth(headers),
  body: body,
  encoding: encoding,
);
