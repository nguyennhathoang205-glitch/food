import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/meal_slot.dart';

/// Hop chon bua an. Bua dung voi gio hien tai duoc dua len dau va danh dau
/// "Theo giờ hiện tại" de nguoi dung khong chon nham (vd 9h ma chon Bua trua).
/// Tra ve null neu nguoi dung dong hop (khi do KHONG luu mon).
Future<String?> pickMealSlot(BuildContext context) {
  final suggested = MealSlot.forTime(DateTime.now());
  final ordered = [
    suggested,
    ...MealSlot.all.where((s) => s != suggested),
  ];

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Thêm vào bữa nào?',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          ...ordered.map((slot) {
            final isSuggested = slot == suggested;
            return ListTile(
              title: Text(
                slot,
                style: TextStyle(
                  fontWeight: isSuggested ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              subtitle: isSuggested ? const Text('Theo giờ hiện tại') : null,
              leading: Icon(
                isSuggested
                    ? Icons.schedule_rounded
                    : Icons.restaurant_outlined,
                color: isSuggested ? primaryDark : null,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(ctx, slot),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
