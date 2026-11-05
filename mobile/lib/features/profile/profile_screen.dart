import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_config.dart';
import '../../core/app_session.dart';
import '../../models/models.dart';
import '../../more_extras.dart' show HealthProfileCard;
import '../tdee_calculator_dialog.dart';

// ============================================================
// PROFILE SCREEN
// ============================================================

class ProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final Future<void> Function(UserProfile) onSave;

  /// Goi khi nguoi dung sua di ung/benh ly -> app tai lai de loc goi y mon.
  final VoidCallback? onHealthChanged;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.onSave,
    this.onHealthChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController nameController;
  late TextEditingController heightController;
  late TextEditingController weightController;
  late TextEditingController calorieController;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    heightController = TextEditingController();
    weightController = TextEditingController();
    calorieController = TextEditingController();
    _fillFrom(widget.profile);
  }

  void _fillFrom(UserProfile p) {
    nameController.text = p.displayName;
    heightController.text =
        p.heightCm == null ? '' : p.heightCm!.toStringAsFixed(0);
    weightController.text =
        p.weightKg == null ? '' : p.weightKg!.toStringAsFixed(1);
    calorieController.text = p.dailyGoal.toStringAsFixed(0);
  }

  // Ho so co the doi tu noi khac (hop tinh TDEE, tai lai du lieu): cap nhat
  // lai o nhap, neu khong man hinh nay van hien so cu.
  @override
  void didUpdateWidget(covariant ProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.profile != widget.profile) {
      _fillFrom(widget.profile);
    }
  }

  void _openTdee() {
    TdeeCalculatorDialog.show(
      context,
      initialWeight: double.tryParse(weightController.text) ?? 65,
      initialHeight: double.tryParse(heightController.text) ?? 168,
      onTargetsApplied: (targets, weightKg, heightCm) {
        setState(() {
          heightController.text = heightCm.toStringAsFixed(0);
          weightController.text = weightKg.toStringAsFixed(1);
          calorieController.text = targets.calories.toStringAsFixed(0);
        });
        widget.onSave(widget.profile.copyWith(
          userKey: AppSession.currentUserKey,
          displayName: nameController.text.trim().isEmpty
              ? null
              : nameController.text.trim(),
          dailyGoal: targets.calories,
          weightKg: weightKg,
          heightCm: heightCm,
        ));
      },
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok == true) {
      AppSession.appLogout?.call();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    heightController.dispose();
    weightController.dispose();
    calorieController.dispose();
    super.dispose();
  }

  double? get bmi {
    final height = double.tryParse(heightController.text);
    final weight = double.tryParse(weightController.text);

    if (height == null || weight == null || height <= 0 || weight <= 0) {
      return null;
    }

    final meters = height / 100;
    return weight / (meters * meters);
  }

  Future<void> save() async {
    setState(() {
      saving = true;
    });

    await widget.onSave(
      UserProfile(
        userKey: widget.profile.userKey.isNotEmpty ? widget.profile.userKey : AppSession.currentUserKey,
        displayName: nameController.text.trim().isEmpty
            ? 'Người dùng Food Scan'
            : nameController.text.trim(),
        heightCm: double.tryParse(heightController.text),
        weightKg: double.tryParse(weightController.text),
        dailyGoal: double.tryParse(calorieController.text) ?? 2000,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
            children: [
              const Text(
                'Hồ sơ của bạn',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 25,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E7F6B), primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(27),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0x33FFFFFF),
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 35,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameController.text.isEmpty
                                ? 'Người dùng Food Scan'
                                : nameController.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.profile.dailyGoal.toStringAsFixed(0)} kcal/ngày',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ProfileMetric(
                      title: 'Chiều cao',
                      value: heightController.text.isEmpty
                          ? '--'
                          : '${heightController.text} cm',
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: ProfileMetric(
                      title: 'Cân nặng',
                      value: weightController.text.isEmpty
                          ? '--'
                          : '${weightController.text} kg',
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: ProfileMetric(
                      title: 'BMI',
                      value: bmi == null ? '--' : bmi!.toStringAsFixed(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      onChanged: (_) {
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Tên hiển thị',
                        filled: true,
                        fillColor: background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: heightController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              setState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Chiều cao',
                              suffixText: 'cm',
                              filled: true,
                              fillColor: background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: weightController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              setState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Cân nặng',
                              suffixText: 'kg',
                              filled: true,
                              fillColor: background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: calorieController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Mục tiêu năng lượng',
                        suffixText: 'kcal/ngày',
                        filled: true,
                        fillColor: background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: saving ? null : save,
                        style: FilledButton.styleFrom(backgroundColor: primary),
                        child: Text(saving ? 'Đang lưu...' : 'Lưu thông tin'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _openTdee,
                        icon: const Icon(Icons.calculate_rounded, size: 18),
                        label: const Text('Tính mục tiêu calo theo cơ thể (TDEE)'),
                        style: TextButton.styleFrom(foregroundColor: primaryDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              HealthProfileCard(
                baseUrl: AppConfig.baseUrl,
                userKey: AppSession.currentUserKey,
                onChanged: widget.onHealthChanged,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Đăng xuất'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileMetric extends StatelessWidget {
  final String title;
  final String value;

  const ProfileMetric({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(color: accent.withValues(alpha: 0.55), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
