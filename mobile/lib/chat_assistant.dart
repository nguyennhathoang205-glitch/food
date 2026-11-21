import 'dart:convert';

import 'package:flutter/material.dart';
import 'auth_http.dart' as http;

const _primary = Color(0xFF10B981);
const _primaryDark = Color(0xFF059669);
const _accent = Color(0xFF0F172A);

class ChatMessage {
  final String role; // "user" hoac "assistant"
  final String text;

  /// De xuat hanh dong do AI tra ve (ghi mon / xoa mon), cho nguoi dung xac nhan.
  /// Chi la de xuat: KHONG co gi duoc ghi cho den khi nguoi dung bam xac nhan.
  final Map<String, dynamic>? pending;

  /// 'open' (cho xac nhan) | 'done' | 'dismissed'
  String pendingState;

  ChatMessage({
    required this.role,
    required this.text,
    this.pending,
    this.pendingState = 'open',
  });
}

/// Nut tron noi goc duoi man hinh, bam vao mo khung chat tro ly AI.
/// Dat widget nay trong 1 Stack cung voi noi dung chinh cua man hinh.
///
/// [scanContext]: JSON ket qua tra ve tu /detect gan nhat (hoac null neu
/// chua scan gi), duoc gui kem moi cau hoi de AI tu van theo ngu canh.
class FloatingHelpButton extends StatelessWidget {
  final String backendBaseUrl;
  final Map<String, dynamic>? scanContext;

  /// Goi sau khi chat ghi / xoa mon trong nhat ky (de man hinh khac tai lai).
  final VoidCallback? onMealsChanged;

  const FloatingHelpButton({
    super.key,
    required this.backendBaseUrl,
    this.scanContext,
    this.onMealsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 18,
      bottom: 18,
      child: _PulsingFab(onTap: () => _openChatSheet(context)),
    );
  }

  void _openChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatSheet(
        backendBaseUrl: backendBaseUrl,
        scanContext: scanContext,
        onMealsChanged: onMealsChanged,
      ),
    );
  }
}

/// Nut FAB co hieu ung "tho" nhe (scale len xuong) de thu hut chu y
/// cho nguoi dung lan dau chua biet co the bam vao day de duoc ho tro.
class _PulsingFab extends StatefulWidget {
  final VoidCallback onTap;
  const _PulsingFab({required this.onTap});

  @override
  State<_PulsingFab> createState() => _PulsingFabState();
}

class _PulsingFabState extends State<_PulsingFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.06);
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_primary, _primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// Khung chat dang bottom sheet, chiem phan lon man hinh.
class ChatSheet extends StatefulWidget {
  final String backendBaseUrl;
  final Map<String, dynamic>? scanContext;
  final VoidCallback? onMealsChanged;

  const ChatSheet({
    super.key,
    required this.backendBaseUrl,
    this.scanContext,
    this.onMealsChanged,
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  static const List<String> _suggestedQuestions = [
    'Hôm nay tôi đã ăn bao nhiêu kcal rồi?',
    'Ghi giúp: sáng nay tôi ăn 2 trứng và 1 ổ bánh mì',
    'Món này có phù hợp để giảm cân không?',
    'Bữa ăn này thiếu chất gì?',
    'Gợi ý món ăn kèm cho cân bằng hơn',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        role: 'assistant',
        text: widget.scanContext != null
            ? 'Chào bạn! Mình thấy bạn vừa quét xong 1 tấm ảnh. Bạn muốn hỏi gì về bữa ăn này không? 😊'
            : 'Chào bạn! Mình là trợ lý dinh dưỡng của FoodScan AI. Bạn cần hỗ trợ gì không? 😊',
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text.trim()));
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.role, 'text': m.text})
          .toList();
      final body = jsonEncode({
        'message': text.trim(),
        'history': history,
        'scan_context': widget.scanContext,
      });
      const headers = {'Content-Type': 'application/json'};

      var response = await http.post(
        Uri.parse('${widget.backendBaseUrl}/api/chat/agent'),
        headers: headers,
        body: body,
      );

      // Server chua co chat agent -> dung /chat cu de khong mat tinh nang.
      if (response.statusCode == 404) {
        response = await http.post(
          Uri.parse('${widget.backendBaseUrl}/chat'),
          headers: headers,
          body: body,
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final pending = data['pending'];
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              text: '${data['reply'] ?? ''}',
              pending: pending is Map<String, dynamic> ? pending : null,
            ),
          );
        });
      } else {
        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              text: 'Xin lỗi, mình gặp sự cố khi trả lời. Thử lại sau nhé.',
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            text: 'Không kết nối được tới server. Kiểm tra lại kết nối nhé.',
          ),
        );
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  Future<void> _confirmPending(ChatMessage message) async {
    final pending = message.pending;
    if (pending == null || message.pendingState != 'open' || _isSending) return;

    final payload = pending['type'] == 'delete_meal'
        ? {'type': 'delete_meal', 'meal_id': (pending['meal'] as Map?)?['id']}
        : {
            'type': 'log_meal',
            'meal_type': pending['meal_type'],
            'items': pending['items'],
          };

    setState(() => _isSending = true);
    try {
      final response = await http.post(
        Uri.parse('${widget.backendBaseUrl}/api/chat/agent/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));

      setState(() {
        if (response.statusCode == 200) {
          message.pendingState = 'done';
          _messages.add(
            ChatMessage(role: 'assistant', text: '${data['reply'] ?? 'Xong rồi!'}'),
          );
        } else {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              text: '${data['message'] ?? 'Không thực hiện được, thử lại nhé.'}',
            ),
          );
        }
      });

      if (response.statusCode == 200) widget.onMealsChanged?.call();
    } catch (_) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            text: 'Không kết nối được tới server. Kiểm tra lại kết nối nhé.',
          ),
        );
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _dismissPending(ChatMessage message) {
    if (message.pendingState != 'open') return;
    setState(() => message.pendingState = 'dismissed');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        height: mediaQuery.size.height * 0.82,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [_primary, _primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trợ lý dinh dưỡng',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: _accent,
                          ),
                        ),
                        Text(
                          'Hỏi bất cứ điều gì về bữa ăn của bạn',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF8A958F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _accent),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Danh sach tin nhan
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _messages.length + (_isSending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return const _TypingBubble();
                  }
                  final message = _messages[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChatBubble(message: message),
                      if (message.pending != null)
                        _PendingCard(
                          message: message,
                          onConfirm: () => _confirmPending(message),
                          onDismiss: () => _dismissPending(message),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Goi y cau hoi nhanh (chi hien khi chua chat nhieu)
            if (_messages.length <= 1)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _suggestedQuestions
                      .map(
                        (q) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _SuggestionChip(
                            label: q,
                            onTap: () => _sendMessage(q),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

            // O nhap tin nhan
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFDDE3DE)),
                      ),
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: 'Hỏi hoặc ghi món: "trưa nay tôi ăn phở"...',
                          hintStyle: TextStyle(
                            color: Color(0xFF9AA59F),
                            fontSize: 13.5,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: _sendMessage,
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _sendMessage(_inputController.text),
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The de xuat "Ghi vao nhat ky" / "Xoa mon" - chi ghi that khi bam xac nhan.
class _PendingCard extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _PendingCard({
    required this.message,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final pending = message.pending!;
    final isDelete = pending['type'] == 'delete_meal';
    final state = message.pendingState;

    final lines = <String>[];
    if (isDelete) {
      final meal = (pending['meal'] as Map?) ?? const {};
      lines.add(
        '${meal['food_name']} · ${(meal['calories'] as num?)?.round() ?? 0} kcal',
      );
    } else {
      for (final item in (pending['items'] as List? ?? [])) {
        if (item is Map) {
          lines.add(
            '${item['name_vi']} · ${item['portion_g']} g · ${(item['calories'] as num?)?.round() ?? 0} kcal',
          );
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12, right: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDelete ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDelete ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDelete
                ? 'Xóa khỏi nhật ký'
                : 'Ghi vào ${pending['meal_type']} (ước tính)',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: _accent,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $line', style: const TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 8),
          if (state == 'open')
            Row(
              children: [
                FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: isDelete
                        ? const Color(0xFFDC2626)
                        : _primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(isDelete ? 'Xóa' : 'Ghi vào nhật ký'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDismiss, child: const Text('Bỏ qua')),
              ],
            )
          else
            Text(
              state == 'done'
                  ? (isDelete ? 'Đã xóa ✓' : 'Đã ghi ✓')
                  : 'Đã bỏ qua',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD5E0DA)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: _primaryDark),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(colors: [_primary, _primaryDark])
              : null,
          color: isUser ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : _accent,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: const SizedBox(width: 28, height: 12, child: _TypingDots()),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value - i * 0.2) % 1.0;
            final opacity = t < 0.5 ? 0.3 + t : 0.3 + (1 - t);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: _primaryDark,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}