// ============================================================
// TDEE & GOAL CALCULATOR DIALOG (Mifflin–St Jeor Scientific Engine)
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/nutrition_calc.dart';

class TdeeCalculatorDialog extends StatefulWidget {
  final double initialWeight;
  final double initialHeight;
  final int initialAge;
  final Gender initialGender;
  final Function(MacroTargets targets, double weightKg, double heightCm) onTargetsApplied;

  const TdeeCalculatorDialog({
    super.key,
    this.initialWeight = 65,
    this.initialHeight = 168,
    this.initialAge = 25,
    this.initialGender = Gender.male,
    required this.onTargetsApplied,
  });

  static Future<void> show(
    BuildContext context, {
    double initialWeight = 65,
    double initialHeight = 168,
    int initialAge = 25,
    Gender initialGender = Gender.male,
    required Function(MacroTargets targets, double weightKg, double heightCm) onTargetsApplied,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: TdeeCalculatorDialog(
          initialWeight: initialWeight,
          initialHeight: initialHeight,
          initialAge: initialAge,
          initialGender: initialGender,
          onTargetsApplied: onTargetsApplied,
        ),
      ),
    );
  }

  @override
  State<TdeeCalculatorDialog> createState() => _TdeeCalculatorDialogState();
}

class _TdeeCalculatorDialogState extends State<TdeeCalculatorDialog> {
  late Gender _gender;
  late double _weightKg;
  late double _heightCm;
  late int _age;
  ActivityLevel _activityLevel = ActivityLevel.moderate;
  WeightGoal _goal = WeightGoal.loseWeight;

  late TextEditingController _weightCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _ageCtrl;

  @override
  void initState() {
    super.initState();
    _gender = widget.initialGender;
    _weightKg = widget.initialWeight > 0 ? widget.initialWeight : 65.0;
    _heightCm = widget.initialHeight > 0 ? widget.initialHeight : 168.0;
    _age = widget.initialAge > 0 ? widget.initialAge : 25;

    _weightCtrl = TextEditingController(text: _weightKg.toInt().toString());
    _heightCtrl = TextEditingController(text: _heightCm.toInt().toString());
    _ageCtrl = TextEditingController(text: _age.toString());
  }

  MacroTargets get _currentTargets {
    return NutritionCalculator.calculateTargets(
      weightKg: _weightKg,
      heightCm: _heightCm,
      age: _age,
      gender: _gender,
      activityLevel: _activityLevel,
      goal: _goal,
    );
  }

  double get _bmr {
    return NutritionCalculator.calculateBMR(
      weightKg: _weightKg,
      heightCm: _heightCm,
      age: _age,
      gender: _gender,
    );
  }

  double get _tdee {
    return NutritionCalculator.calculateTDEE(
      weightKg: _weightKg,
      heightCm: _heightCm,
      age: _age,
      gender: _gender,
      activityLevel: _activityLevel,
    );
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targets = _currentTargets;

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
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calculate_outlined, color: Color(0xFF2563EB), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tính Mục Tiêu Tự Động (TDEE)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Dựa trên công thức khoa học Mifflin–St Jeor',
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
            const SizedBox(height: 20),

            // Gioi tinh
            Row(
              children: [
                Expanded(
                  child: _genderButton(
                    label: 'Nam',
                    icon: Icons.male,
                    isSelected: _gender == Gender.male,
                    onTap: () => setState(() => _gender = Gender.male),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _genderButton(
                    label: 'Nữ',
                    icon: Icons.female,
                    isSelected: _gender == Gender.female,
                    onTap: () => setState(() => _gender = Gender.female),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Can nang, chieu cao, tuoi
            Row(
              children: [
                Expanded(
                  child: _numberInput(
                    label: 'Cân nặng (kg)',
                    controller: _weightCtrl,
                    onChanged: (val) {
                      final n = double.tryParse(val) ?? 65;
                      setState(() => _weightKg = n);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberInput(
                    label: 'Chiều cao (cm)',
                    controller: _heightCtrl,
                    onChanged: (val) {
                      final n = double.tryParse(val) ?? 168;
                      setState(() => _heightCm = n);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberInput(
                    label: 'Tuổi',
                    controller: _ageCtrl,
                    onChanged: (val) {
                      final n = int.tryParse(val) ?? 25;
                      setState(() => _age = n);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Muc do van dong
            Text(
              'Mức độ vận động:',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ActivityLevel>(
              initialValue: _activityLevel,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              items: const [
                DropdownMenuItem(value: ActivityLevel.sedentary, child: Text('Ít vận động (ngồi nhiều, văn phòng)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: ActivityLevel.light, child: Text('Nhẹ (tập thể dục 1-3 ngày/tuần)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: ActivityLevel.moderate, child: Text('Vừa phải (tập 3-5 ngày/tuần)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: ActivityLevel.veryActive, child: Text('Nhiều (tập 6-7 ngày/tuần)', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: ActivityLevel.extraActive, child: Text('Rất nhiều (vận động viên / lao động nặng)', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _activityLevel = val);
              },
            ),
            const SizedBox(height: 16),

            // Muc tieu can nang
            Text(
              'Mục tiêu cân nặng:',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _goalChip('Giảm cân', '-500 kcal', WeightGoal.loseWeight, const Color(0xFF10B981)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _goalChip('Giữ cân', 'Duy trì', WeightGoal.maintain, const Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _goalChip('Tăng cân', '+450 kcal', WeightGoal.gainWeight, const Color(0xFFF59E0B)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ket qua tinh toan Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _metricCol('BMR cơ bản', '${_bmr.toInt()} kcal'),
                      _metricCol('TDEE tiêu hao', '${_tdee.toInt()} kcal'),
                      _metricCol('Mục tiêu nạp', '${targets.calories.toInt()} kcal', isHighlighted: true),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _macroCol('Đạm (Protein)', '${targets.proteinG.toInt()}g', const Color(0xFF10B981)),
                      _macroCol('Chất béo (Fat)', '${targets.fatG.toInt()}g', const Color(0xFFF59E0B)),
                      _macroCol('Tinh bột (Carbs)', '${targets.carbsG.toInt()}g', const Color(0xFF38BDF8)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nut Ap dung
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  final w = double.tryParse(_weightCtrl.text) ?? _weightKg;
                  final h = double.tryParse(_heightCtrl.text) ?? _heightCm;
                  widget.onTargetsApplied(targets, w, h);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.check, color: Colors.white),
                label: Text(
                  'Áp dụng làm mục tiêu hằng ngày',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _genderButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6FBF2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF059669) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberInput({
    required String label,
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
      ],
    );
  }

  Widget _goalChip(String title, String subtitle, WeightGoal goal, Color color) {
    final isSelected = _goal == goal;
    return InkWell(
      onTap: () => setState(() => _goal = goal),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: isSelected ? color : const Color(0xFF334155),
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCol(String title, String value, {bool isHighlighted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: isHighlighted ? 18 : 15,
            fontWeight: FontWeight.w800,
            color: isHighlighted ? const Color(0xFF10B981) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _macroCol(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white70),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
