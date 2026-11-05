// ============================================================
// SCAN FEEDBACK DIALOG (Active Learning & Model Continuous Improvement)
// ============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/meal_service.dart';

class FeedbackDialog extends StatefulWidget {
  final String userKey;
  final String predictedName;
  final int? predictedClassId;
  final double? confidence;
  final Uint8List? imageBytes;
  final Map<String, dynamic>? boundingBox;
  final String? baseUrl;

  const FeedbackDialog({
    super.key,
    required this.userKey,
    required this.predictedName,
    this.predictedClassId,
    this.confidence,
    this.imageBytes,
    this.boundingBox,
    this.baseUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required String userKey,
    required String predictedName,
    int? predictedClassId,
    double? confidence,
    Uint8List? imageBytes,
    Map<String, dynamic>? boundingBox,
    String? baseUrl,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => FeedbackDialog(
        userKey: userKey,
        predictedName: predictedName,
        predictedClassId: predictedClassId,
        confidence: confidence,
        imageBytes: imageBytes,
        boundingBox: boundingBox,
        baseUrl: baseUrl,
      ),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _correctNameCtrl = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _commonDishes = [
    'Phở bò',
    'Phở gà',
    'Bún bò Huế',
    'Bún chả Hà Nội',
    'Bún đậu mắm tôm',
    'Cơm tấm sườn bì chả',
    'Bánh mì thịt',
    'Bánh xèo',
    'Gỏi cuốn',
    'Chả giò / Nem rán',
  ];

  Future<void> _submitFeedback() async {
    final correctName = _correctNameCtrl.text.trim();
    if (correctName.isEmpty) return;

    setState(() => _isSubmitting = true);

    String? imageB64;
    if (widget.imageBytes != null) {
      imageB64 = base64Encode(widget.imageBytes!);
    }

    final ok = await MealService.sendScanFeedback(
      userKey: widget.userKey,
      predictedName: widget.predictedName,
      correctedName: correctName,
      predictedClassId: widget.predictedClassId,
      confidence: widget.confidence,
      imageBase64: imageB64,
      boundingBox: widget.boundingBox,
      baseUrl: widget.baseUrl,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            ok
                ? 'Cảm ơn bạn! Dữ liệu & ảnh đã được lưu để huấn luyện lại model.'
                : 'Đã ghi nhận phản hồi của bạn!',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _correctNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.school_outlined, color: Color(0xFFD97706), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Góp ý nhận diện (Active Learning)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.imageBytes != null) ...[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    widget.imageBytes!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'AI nhận diện:',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology, color: Color(0xFF64748B), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.predictedName,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  if (widget.confidence != null) ...[
                    const Spacer(),
                    Text(
                      '${(widget.confidence! * 100).toInt()}%',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tên món chính xác thực tế:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _correctNameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Nhập tên món đúng...',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Hoặc chọn nhanh:',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _commonDishes.take(5).map((d) {
                return InkWell(
                  onTap: () => setState(() => _correctNameCtrl.text = d),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      d,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF334155)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Hủy',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade600),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitFeedback,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(
                  'Gửi góp ý',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white),
                ),
        ),
      ],
    );
  }
}
