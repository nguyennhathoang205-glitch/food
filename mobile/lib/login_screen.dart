import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_http.dart' as http;

const Color _emerald = Color(0xFF10B981);
const Color _emeraldDark = Color(0xFF059669);
const Color _emeraldLight = Color(0xFFE6FBF2);
const Color _slateInk = Color(0xFF0F172A);
const Color _slateMuted = Color(0xFF64748B);
const Color _slateBorder = Color(0xFFE2E8F0);
const Color _bg = Color(0xFFF8FAFC);

class LoginScreen extends StatefulWidget {
  final String baseUrl;
  final VoidCallback onAuthed;

  const LoginScreen({super.key, required this.baseUrl, required this.onAuthed});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool registerMode = false;
  bool hidePassword = true;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _call(String path, [Map<String, dynamic>? body]) async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode != 200 || data['status'] != 'ok') {
        throw Exception(data['message'] ?? 'Có lỗi xảy ra.');
      }

      final user = data['user'];

      await http.AuthSession.save(
        token: data['token'],
        userId: user['id'],
        name: user['name'] ?? '',
        email: user['email'] ?? '',
      );

      widget.onAuthed();
    } on FormatException {
      setState(() => error = 'Máy chủ phản hồi không hợp lệ.');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');

      setState(() {
        error = msg.contains('Failed to fetch') || msg.contains('Connection')
            ? 'Không kết nối được máy chủ. Hãy bật backend rồi thử lại.'
            : msg;
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    _call(registerMode ? '/api/auth/register' : '/api/auth/login', {
      'email': _email.text.trim(),
      'password': _password.text,
      if (registerMode) 'name': _name.text.trim(),
    });
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _slateMuted, fontSize: 13, fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: _emeraldDark, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _slateBorder, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _slateBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _emerald, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background ambient gradient orbs
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _emerald.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 140,
            right: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App Logo & Header
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_emerald, _emeraldDark],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _emerald.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'FoodScan AI',
                        style: GoogleFonts.plusJakartaSans(
                          color: _slateInk,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Theo dõi dinh dưỡng thông minh với AI Vision',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: _slateMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Card form
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _slateBorder, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tab switch
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _tabPill(
                                        title: 'Đăng nhập',
                                        active: !registerMode,
                                        onTap: () => setState(() {
                                          registerMode = false;
                                          error = null;
                                        }),
                                      ),
                                    ),
                                    Expanded(
                                      child: _tabPill(
                                        title: 'Đăng ký',
                                        active: registerMode,
                                        onTap: () => setState(() {
                                          registerMode = true;
                                          error = null;
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Form fields
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                child: registerMode
                                    ? Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: TextFormField(
                                          controller: _name,
                                          textInputAction: TextInputAction.next,
                                          style: const TextStyle(color: _slateInk, fontSize: 14),
                                          decoration: _decoration(
                                            'Tên của bạn',
                                            Icons.person_outline_rounded,
                                          ),
                                          validator: (v) => (v ?? '').trim().isEmpty
                                              ? 'Vui lòng nhập tên của bạn'
                                              : null,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(color: _slateInk, fontSize: 14),
                                decoration: _decoration(
                                  'Email',
                                  Icons.mail_outline_rounded,
                                ),
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                                      ? null
                                      : 'Email không đúng định dạng';
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _password,
                                obscureText: hidePassword,
                                textInputAction: registerMode
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                onFieldSubmitted: (_) =>
                                    registerMode ? null : _submit(),
                                style: const TextStyle(color: _slateInk, fontSize: 14),
                                decoration: _decoration(
                                  'Mật khẩu',
                                  Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    icon: Icon(
                                      hidePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: _slateMuted,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () => hidePassword = !hidePassword,
                                    ),
                                  ),
                                ),
                                validator: (v) => (v ?? '').length < 6
                                    ? 'Mật khẩu tối thiểu 6 ký tự'
                                    : null,
                              ),
                              if (registerMode) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirm,
                                  obscureText: hidePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  style: const TextStyle(color: _slateInk, fontSize: 14),
                                  decoration: _decoration(
                                    'Xác nhận lại mật khẩu',
                                    Icons.lock_reset_rounded,
                                  ),
                                  validator: (v) => v != _password.text
                                      ? 'Mật khẩu xác nhận không khớp'
                                      : null,
                                ),
                              ],
                              if (error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFCA5A5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          error!,
                                          style: const TextStyle(
                                            color: Color(0xFFB91C1C),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),

                              // Submit Button
                              Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: const LinearGradient(
                                    colors: [_emerald, _emeraldDark],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _emerald.withValues(alpha: 0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: loading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: loading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          registerMode ? 'Tạo tài khoản ngay' : 'Đăng nhập',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Guest quick entry
                      InkWell(
                        onTap: loading ? null : () => _call('/api/auth/guest'),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: _emeraldLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _emerald.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt_rounded, color: _emeraldDark, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Dùng thử ngay không cần tài khoản',
                                style: GoogleFonts.plusJakartaSans(
                                  color: _emeraldDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_rounded, color: _emeraldDark, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill({required String title, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: active ? _slateInk : _slateMuted,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
