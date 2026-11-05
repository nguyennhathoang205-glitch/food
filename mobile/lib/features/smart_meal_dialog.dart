// ============================================================
// SMART MEAL LOGGER DIALOG (Text / Voice Natural Language Input)
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/meal_slot.dart';
import '../services/meal_service.dart';

class SmartMealDialog extends StatefulWidget {
  final String userKey;
  final String? baseUrl;
  final VoidCallback onMealSaved;

  const SmartMealDialog({
    super.key,
    required this.userKey,
    this.baseUrl,
    required this.onMealSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required String userKey,
    String? baseUrl,
    required VoidCallback onMealSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SmartMealDialog(
          userKey: userKey,
          baseUrl: baseUrl,
          onMealSaved: onMealSaved,
        ),
      ),
    );
  }

  @override
  State<SmartMealDialog> createState() => _SmartMealDialogState();
}

class _SmartMealDialogState extends State<SmartMealDialog> {
  final _textController = TextEditingController();
  String _selectedMealType = MealSlot.forTime(DateTime.now());
  bool _isAnalyzing = false;
  bool _isSaving = false;
  ParsedMealResult? _parsedResult;
  List<double> _itemScales = [];
  String? _errorMessage;

  final List<String> _quickSamples = [
    '1 tô phở bò nhiều thịt + 1 ly trà đá',
    '1 đĩa cơm tấm sườn trứng ốp la',
    '1 ổ bánh mì thịt nguội + 1 ly cà phê sữa đá',
    '1 hộp sữa chua không đường + 1 quả chuối chín',
    '1 suất bún chả Hà Nội + nem rán',
  ];

  double get _scaledTotalCalories {
    if (_parsedResult == null) return 0;
    double sum = 0;
    for (int i = 0; i < _parsedResult!.items.length; i++) {
      final scale = i < _itemScales.length ? _itemScales[i] : 1.0;
      sum += _parsedResult!.items[i].calories * scale;
    }
    return sum;
  }

  Future<void> _analyzeMeal() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập mô tả bữa ăn');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _parsedResult = null;
      _itemScales = [];
    });

    final res = await MealService.parseMealFromText(
      text: text,
      mealType: _selectedMealType,
      baseUrl: widget.baseUrl,
    );

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
        if (res == null || res.items.isEmpty) {
          _errorMessage = 'Không thể phân tích bữa ăn. Vui lòng thử lại!';
        } else {
          _parsedResult = res;
          _itemScales = List<double>.filled(res.items.length, 1.0);
        }
      });
    }
  }

  Future<void> _saveAllItems() async {
    if (_parsedResult == null || _parsedResult!.items.isEmpty) return;

    setState(() => _isSaving = true);
    int savedCount = 0;

    for (int i = 0; i < _parsedResult!.items.length; i++) {
      final scale = i < _itemScales.length ? _itemScales[i] : 1.0;
      if (scale <= 0) continue;
      final item = _parsedResult!.items[i];
      final ok = await MealService.createMealLog(
        userKey: widget.userKey,
        foodName: item.nameVi,
        mealType: _selectedMealType,
        portionG: (item.portionG * scale).round(),
        calories: item.calories * scale,
        proteinG: item.proteinG * scale,
        fatG: item.fatG * scale,
        carbsG: item.carbsG * scale,
        baseUrl: widget.baseUrl,
      );
      if (ok) savedCount++;
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (savedCount > 0) {
        widget.onMealSaved();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(
              'Đã ghi $savedCount món ăn vào nhật ký!',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6FBF2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ghi bữa ăn bằng AI (NLP)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Nhập hoặc nói tự nhiên, AI tự bóc tách món & calo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Chon bua an
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _mealTypeChip(MealSlot.breakfast, 'Bữa sáng', Icons.wb_sunny_outlined),
                  const SizedBox(width: 8),
                  _mealTypeChip(MealSlot.lunch, 'Bữa trưa', Icons.restaurant),
                  const SizedBox(width: 8),
                  _mealTypeChip(MealSlot.dinner, 'Bữa tối', Icons.nights_stay_outlined),
                  const SizedBox(width: 8),
                  _mealTypeChip(MealSlot.snack, 'Ăn phụ', Icons.local_cafe_outlined),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Input TextField
            TextField(
              controller: _textController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'VD: trưa nay ăn 1 tô phở bò với 1 ly trà đá...',
                hintStyle: GoogleFonts.plusJakartaSans(color: Colors.grey.shade400, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Quick Samples Chips
            Text(
              'Gợi ý nhanh:',
              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickSamples.map((s) {
                return InkWell(
                  onTap: () {
                    _textController.text = s;
                    _analyzeMeal();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF334155)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Nut phan tich
            if (_parsedResult == null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _analyzeMeal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.analytics_outlined, color: Colors.white),
                  label: Text(
                    _isAnalyzing ? 'Đang phân tích món ăn...' : 'Phân tích món & Dinh dưỡng',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

            // Ket qua phan tich
            if (_parsedResult != null) ...[
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Kết quả bóc tách (${_parsedResult!.items.length} món):',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6FBF2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tổng: ${_scaledTotalCalories.round()} kcal',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: const Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(_parsedResult!.items.length, (idx) {
                final it = _parsedResult!.items[idx];
                final scale = idx < _itemScales.length ? _itemScales[idx] : 1.0;
                if (scale <= 0) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.nameVi,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${it.quantity} (~${(it.portionG * scale).round()}g) • P: ${(it.proteinG * scale).toStringAsFixed(1)}g | F: ${(it.fatG * scale).toStringAsFixed(1)}g | C: ${(it.carbsG * scale).toStringAsFixed(1)}g',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Giảm khẩu phần',
                        onPressed: () {
                          setState(() {
                            _itemScales[idx] = (scale - 0.5).clamp(0.0, 5.0);
                          });
                        },
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                      ),
                      Text(
                        '${(it.calories * scale).round()} kcal',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Tăng khẩu phần',
                        onPressed: () {
                          setState(() {
                            _itemScales[idx] = (scale + 0.5).clamp(0.5, 5.0);
                          });
                        },
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _parsedResult = null),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Nhập lại',
                        style: GoogleFonts.plusJakartaSans(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveAllItems,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.save, color: Colors.white, size: 18),
                      label: Text(
                        _isSaving ? 'Đang lưu...' : 'Lưu vào nhật ký',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mealTypeChip(String type, String label, IconData icon) {
    final isSelected = _selectedMealType == type;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _selectedMealType = type);
      },
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : Colors.grey.shade600,
      ),
      label: Text(label),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF334155),
      ),
      selectedColor: const Color(0xFF10B981),
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
      showCheckmark: false,
    );
  }
}
