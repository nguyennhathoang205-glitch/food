// ============================================================
// DANG CONG THUC
// ============================================================
// Nhap ten, so phan, nguyen lieu (ten + gram) va cac buoc. Server tu tinh
// kcal / dam / beo / tinh bot. Nguyen lieu la (chua co trong bang tham khao)
// thi nguoi dung tu nhap so lieu /100g - app khong doan bua.
// Co anh thi dung de lam anh dai dien va (tuy chon) day AI nhan ra mon do.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth_http.dart' as http;
import '../../core/app_config.dart';

const Color _primary = Color(0xFF10B981);
const Color _primaryDark = Color(0xFF059669);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);
const Color _danger = Color(0xFFDC2626);

const int _maxImages = 3;

class _IngredientRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController grams = TextEditingController();
  final TextEditingController kcal = TextEditingController();
  final TextEditingController protein = TextEditingController();
  final TextEditingController fat = TextEditingController();
  final TextEditingController carbs = TextEditingController();
  bool showCustom = false;
  bool unknown = false;

  void dispose() {
    for (final c in [name, grams, kcal, protein, fat, carbs]) {
      c.dispose();
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'grams': grams.text.trim().replaceAll(',', '.'),
    'kcal_per_100g': kcal.text.trim().replaceAll(',', '.'),
    'protein_per_100g': protein.text.trim().replaceAll(',', '.'),
    'fat_per_100g': fat.text.trim().replaceAll(',', '.'),
    'carbs_per_100g': carbs.text.trim().replaceAll(',', '.'),
  };
}

class RecipeComposeScreen extends StatefulWidget {
  const RecipeComposeScreen({super.key});

  @override
  State<RecipeComposeScreen> createState() => _RecipeComposeScreenState();
}

class _RecipeComposeScreenState extends State<RecipeComposeScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _steps = TextEditingController();
  final List<_IngredientRow> _rows = [_IngredientRow()];
  final List<Uint8List> _images = [];

  int _servings = 1;
  bool _teachAi = true;
  bool _busy = false;

  String? _message;
  bool _messageIsError = true;
  Map<String, dynamic>? _preview;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _steps.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
    'title': _title.text.trim(),
    'description': _desc.text.trim(),
    'servings': _servings,
    'ingredients': [for (final r in _rows) r.toJson()],
    'steps': _steps.text.split('\n'),
  };

  String _messageOf(http.Response res, String fallback) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  void _say(String text, {bool error = true}) {
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  // Danh dau cac dong "chua co so lieu" de nguoi dung nhap tay.
  void _markUnknown(List<dynamic> names) {
    final set = names.map((e) => e.toString()).toSet();
    for (final r in _rows) {
      r.unknown = set.contains(r.name.text.trim());
      if (r.unknown) r.showCustom = true;
    }
  }

  Future<void> _calculate() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/community/recipes/preview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_payload()),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _preview = body as Map<String, dynamic>;
          _markUnknown(body['unknown'] as List? ?? []);
        });

        final unknown = body['unknown'] as List? ?? [];
        if (unknown.isNotEmpty) {
          _say(
            'Chưa có số liệu cho: ${unknown.join(', ')}. Hãy nhập kcal/100g ở dòng đó.',
          );
        }
      } else {
        _say(_messageOf(res, 'Không tính được.'));
      }
    } catch (_) {
      if (mounted) _say('Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/community/recipes'),
      );
      req.fields['data'] = jsonEncode(_payload());
      req.fields['teach_ai'] = _teachAi ? '1' : '0';
      for (var i = 0; i < _images.length; i++) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'images',
            _images[i],
            filename: 'recipe_$i.jpg',
          ),
        );
      }

      final res = await http.Response.fromStream(await req.send());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final learned = body['ai_learned'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              learned
                  ? 'Đã đăng công thức. AI cũng đã học món này từ ảnh của bạn.'
                  : 'Đã đăng công thức.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        // Loi thieu so lieu nguyen lieu: mo san o nhap tay cho dong do.
        final text = _messageOf(res, 'Không đăng được công thức.');
        final match = RegExp(r'cho: (.+)\. Hãy').firstMatch(text);
        if (match != null) {
          setState(() => _markUnknown(match.group(1)!.split(', ')));
        }
        _say(text);
      }
    } catch (_) {
      if (mounted) _say('Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImages() async {
    final room = _maxImages - _images.length;
    if (room <= 0) return;
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;

    final picked = <Uint8List>[];
    for (final f in files.take(room)) {
      picked.add(await f.readAsBytes());
    }
    if (!mounted) return;
    setState(() => _images.addAll(picked));
  }

  Future<void> _takePhoto() async {
    if (_images.length >= _maxImages) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _images.add(bytes));
  }

  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: _line, width: 1.2),
  );

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _buildIngredient(int index) {
    final row = _rows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: row.name,
                  decoration: _dec('Nguyên liệu', hint: 'vd: ức gà').copyWith(
                    enabledBorder: row.unknown
                        ? OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _danger),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() => _preview = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: row.grams,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _dec('Gram'),
                  onChanged: (_) => setState(() => _preview = null),
                ),
              ),
              IconButton(
                tooltip: 'Xóa dòng',
                onPressed: _rows.length <= 1
                    ? null
                    : () => setState(() {
                        _rows.removeAt(index).dispose();
                        _preview = null;
                      }),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => row.showCustom = !row.showCustom),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                foregroundColor: row.unknown ? _danger : _primaryDark,
              ),
              child: Text(
                row.showCustom
                    ? 'Ẩn phần tự nhập dinh dưỡng'
                    : (row.unknown
                          ? 'Chưa có số liệu - bấm để nhập /100g'
                          : 'Tự nhập dinh dưỡng /100g (nếu cần)'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (row.showCustom)
            Row(
              children: [
                for (final entry in <MapEntry<String, TextEditingController>>[
                  MapEntry('kcal', row.kcal),
                  MapEntry('Đạm', row.protein),
                  MapEntry('Béo', row.fat),
                  MapEntry('Bột', row.carbs),
                ]) ...[
                  Expanded(
                    child: TextField(
                      controller: entry.value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _dec(entry.key),
                      onChanged: (_) => setState(() => _preview = null),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final p = _preview;
    if (p == null || p['ok'] != true) return const SizedBox.shrink();

    final per = p['per_serving'] as Map? ?? const {};
    final labels = (p['labels'] as List? ?? []).map((e) => '$e').toList();
    final complete = p['macros_complete'] != false;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mỗi phần (~${p['grams_per_serving']} g): ${per['kcal']} kcal'
            '${complete ? ' · đạm ${per['protein_g']} g · béo ${per['fat_g']} g · bột ${per['carbs_g']} g' : ''}',
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          if (!complete)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Một số nguyên liệu tự nhập thiếu đạm/béo/bột nên chỉ tính chắc phần kcal.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in labels)
                  Chip(
                    label: Text(l, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Đăng công thức',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  decoration: _dec('Tên món', hint: 'vd: Cơm ức gà luộc'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  maxLines: 2,
                  decoration: _dec('Mô tả ngắn (không bắt buộc)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Số phần ăn',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _servings > 1
                          ? () => setState(() {
                              _servings--;
                              _preview = null;
                            })
                          : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Text(
                      '$_servings',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      onPressed: _servings < 20
                          ? () => setState(() {
                              _servings++;
                              _preview = null;
                            })
                          : null,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nguyên liệu',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Thịt/cá/rau tính theo khối lượng sống; cơm, bún, khoai luộc tính theo khối lượng đã nấu.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _rows.length; i++) _buildIngredient(i),
                TextButton.icon(
                  onPressed: _rows.length >= 30
                      ? null
                      : () => setState(() {
                          _rows.add(_IngredientRow());
                          _preview = null;
                        }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Thêm nguyên liệu'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: TextField(
              controller: _steps,
              minLines: 3,
              maxLines: 8,
              decoration: _dec(
                'Cách làm (mỗi dòng là một bước)',
                hint: 'Luộc gà 15 phút\nXé nhỏ\nBày ra đĩa',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ảnh món ăn',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _images[i],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => setState(() => _images.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_images.length < _maxImages) ...[
                      OutlinedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.photo_camera_rounded, size: 18),
                        label: const Text('Chụp'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addImages,
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('Thư viện'),
                      ),
                    ],
                  ],
                ),
                if (_images.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _teachAi,
                    activeThumbColor: _primary,
                    onChanged: (v) => setState(() => _teachAi = v),
                    title: const Text('Cho AI học món này từ ảnh'),
                    subtitle: const Text(
                      'Lần sau quét món giống vậy, AI sẽ nhận ra tên món.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          _buildPreview(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? _danger : _primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _calculate,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Tính thử'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _busy ? null : _post,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Đăng công thức'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}