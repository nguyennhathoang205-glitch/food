import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/models.dart';
import '../services/offline_service.dart';
import 'meal_slot_picker.dart';

/// Man hinh chon mon thu cong khi khong co mang: tim mon trong bang dinh duong
/// luu san trong app, chinh khau phan, roi tra ve [MealEntry] de luu bua.
Future<MealEntry?> showOfflineFoodPicker(
  BuildContext context, {
  List<int> suggestedIds = const [],
}) {
  return showModalBottomSheet<MealEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _OfflineFoodSheet(suggestedIds: suggestedIds),
  );
}

class _OfflineFoodSheet extends StatefulWidget {
  final List<int> suggestedIds;

  const _OfflineFoodSheet({this.suggestedIds = const []});

  @override
  State<_OfflineFoodSheet> createState() => _OfflineFoodSheetState();
}

class _OfflineFoodSheetState extends State<_OfflineFoodSheet> {
  List<OfflineFood> _all = [];
  String _query = '';
  OfflineFood? _selected;
  double _scale = 1.0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    OfflineFoods.load().then((foods) {
      if (!mounted) return;
      setState(() {
        _all = foods..sort((a, b) => a.nameVi.compareTo(b.nameVi));
        _loaded = true;
        for (final id in widget.suggestedIds) {
          final hit = _all.where((f) => f.classId == id);
          if (hit.isNotEmpty) {
            _selected = hit.first;
            break;
          }
        }
      });
    });
  }

  Future<void> _save() async {
    final f = _selected;
    if (f == null) return;
    final slot = await pickMealSlot(context);
    if (slot == null || !mounted) return;
    Navigator.pop(
      context,
      MealEntry(
        name: f.nameVi,
        mealType: slot,
        time: DateTime.now(),
        portionG: (f.portionG * _scale).round(),
        calories: f.calories * _scale,
        proteinG: f.proteinG * _scale,
        fatG: f.fatG * _scale,
        carbsG: f.carbsG * _scale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _all
        : _all.where((f) => f.nameVi.toLowerCase().contains(q)).toList();
    final sel = _selected;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Chế độ offline: chọn món để tính calo',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Tìm món (vd: cơm tấm, phở...)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (widget.suggestedIds.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '🤖 AI trên máy đã gợi ý món được chọn sẵn - bạn có thể đổi.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF047857)),
                  ),
                ),
              ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final f = shown[i];
                        final on = sel?.classId == f.classId;
                        return ListTile(
                          dense: true,
                          selected: on,
                          selectedTileColor: const Color(0xFFECFDF5),
                          title: Text(
                            f.nameVi,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${f.calories.round()} kcal · ${f.portionG} g/phần',
                          ),
                          trailing: on
                              ? const Icon(Icons.check_circle_rounded,
                                  color: primary)
                              : null,
                          onTap: () => setState(() {
                            _selected = f;
                            _scale = 1.0;
                          }),
                        );
                      },
                    ),
            ),
            if (sel != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Column(
                  children: [
                    Text(
                      '${sel.nameVi}: ${(sel.calories * _scale).round()} kcal · '
                      '${(sel.portionG * _scale).round()} g',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Slider(
                      value: _scale,
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      label: '${(_scale * 100).round()}%',
                      onChanged: (v) => setState(() => _scale = v),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Thêm vào bữa'),
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

