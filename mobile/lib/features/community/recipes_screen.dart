// ============================================================
// CONG THUC CONG DONG
// ============================================================
// Danh sach cong thuc do nguoi dung dang, xem chi tiet, tha tim va
// "An theo cong thuc nay" (ghi thang vao nhat ky). Xem backend/recipes.py.
//
// Mo bang RecipesScreen.open(context).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../auth_http.dart' as http;
import '../../core/app_config.dart';
import '../../widgets/meal_slot_picker.dart';
import 'recipe_compose_screen.dart';

const Color _primary = Color(0xFF10B981);
const Color _primaryDark = Color(0xFF059669);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);

String _api(String path) => '${AppConfig.baseUrl}/api/community/recipes$path';

String _messageOf(http.Response res, String fallback) {
  try {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map && body['message'] != null) {
      return body['message'].toString();
    }
  } catch (_) {}
  return fallback;
}

Uint8List? _decodeThumb(dynamic thumb) {
  if (thumb is! String || thumb.isEmpty) return null;
  try {
    return base64Decode(thumb);
  } catch (_) {
    return null;
  }
}

Widget _thumbOrPlaceholder(dynamic thumb, double size) {
  final bytes = _decodeThumb(thumb);
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: bytes != null
        ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)
        : Container(
            width: size,
            height: size,
            color: const Color(0xFFD1FAE5),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _primaryDark,
            ),
          ),
  );
}

Widget _labelChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFA7F3D0)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: _primaryDark,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ------------------------------------------------------------
// Danh sach
// ------------------------------------------------------------

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecipesScreen()),
    );
  }

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  // 0 = moi nhat, 1 = noi bat (nhieu tim), 2 = cua toi
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final query = _tab == 1 ? '?sort=top' : (_tab == 2 ? '?mine=1' : '');

    try {
      final res = await http.get(Uri.parse(_api(query)));
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (body['recipes'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        setState(() => _items = list);
      } else {
        setState(() => _error = _messageOf(res, 'Không tải được công thức.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecipeDetailScreen(recipeId: id)),
    );
    if (mounted) _load();
  }

  Future<void> _openCompose() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecipeComposeScreen()),
    );
    if (posted == true && mounted) {
      setState(() => _tab = 2);
      _load();
    }
  }

  Widget _buildTabs() {
    const names = ['Mới nhất', 'Nổi bật', 'Của tôi'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < names.length; i++) ...[
            ChoiceChip(
              label: Text(names[i]),
              selected: _tab == i,
              selectedColor: const Color(0xFFD1FAE5),
              onSelected: (_) {
                if (_tab == i) return;
                setState(() => _tab = i);
                _load();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final per = r['per_serving'] is Map ? r['per_serving'] as Map : const {};
    final labels = (r['labels'] as List? ?? []).take(2).toList();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openDetail((r['id'] as num).toInt()),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _thumbOrPlaceholder(r['thumb'], 84),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'bởi ${r['author'] ?? ''} · ${per['kcal'] ?? '?'} kcal/phần',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [for (final l in labels) _labelChip('$l')],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Icon(
                  r['liked_by_me'] == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: r['liked_by_me'] == true
                      ? const Color(0xFFEF4444)
                      : _muted,
                  size: 20,
                ),
                Text(
                  '${r['like_count'] ?? 0}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _tab == 2
                ? 'Bạn chưa đăng công thức nào.\nBấm "Đăng công thức" để bắt đầu.'
                : 'Chưa có công thức nào. Hãy là người đầu tiên!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_items[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Công thức cộng đồng',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCompose,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Đăng công thức'),
      ),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Chi tiet
// ------------------------------------------------------------

class RecipeDetailScreen extends StatefulWidget {
  final int recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Map<String, dynamic>? _recipe;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse(_api('/${widget.recipeId}')));
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _recipe = body['recipe'] as Map<String, dynamic>);
      } else {
        setState(() => _error = _messageOf(res, 'Không tải được công thức.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không kết nối được máy chủ.');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse(_api('/${widget.recipeId}/like')),
        headers: {'Content-Type': 'application/json'},
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _recipe!['liked_by_me'] = body['liked'] == true;
          _recipe!['like_count'] = body['like_count'];
        });
      } else {
        _toast(_messageOf(res, 'Không thả tim được.'));
      }
    } catch (_) {
      if (mounted) _toast('Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<double?> _pickPortions() {
    return showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bạn ăn bao nhiêu phần?'),
        children: [
          for (final p in const [0.5, 1.0, 1.5, 2.0])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(
                p == 1.0 ? '1 phần (theo công thức)' : '$p phần',
                style: const TextStyle(fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _eat() async {
    final slot = await pickMealSlot(context);
    if (slot == null || !mounted) return;
    final portions = await _pickPortions();
    if (portions == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse(_api('/${widget.recipeId}/eat')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'meal_type': slot, 'portions': portions}),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final partial = body['macros_complete'] == false;
        _toast(
          partial
              ? 'Đã thêm vào nhật ký ($slot). Công thức này thiếu số liệu đạm/béo/tinh bột nên chỉ tính chắc phần kcal.'
              : 'Đã thêm vào nhật ký ($slot).',
        );
      } else {
        _toast(_messageOf(res, 'Không ghi được vào nhật ký.'));
      }
    } catch (_) {
      if (mounted) _toast('Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa công thức này?'),
        content: const Text('Công thức sẽ biến mất khỏi cộng đồng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final res = await http.delete(Uri.parse(_api('/${widget.recipeId}')));
      if (!mounted) return;

      if (res.statusCode == 200) {
        Navigator.of(context).pop();
      } else {
        _toast(_messageOf(res, 'Không xóa được.'));
      }
    } catch (_) {
      if (mounted) _toast('Không kết nối được máy chủ.');
    }
  }

  Widget _macroBox(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(color: _muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink,
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    ),
  );

  Widget _buildContent(Map<String, dynamic> r) {
    final per = r['per_serving'] is Map ? r['per_serving'] as Map : const {};
    final nutrition = r['nutrition'] is Map ? r['nutrition'] as Map : const {};
    final ingredients = (r['ingredients'] as List? ?? []).whereType<Map>();
    final steps = (r['steps'] as List? ?? []).map((e) => '$e').toList();
    final labels = (r['labels'] as List? ?? []).map((e) => '$e').toList();
    final bytes = _decodeThumb(r['thumb']);
    final complete = nutrition['macros_complete'] != false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              bytes,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          r['title']?.toString() ?? '',
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'bởi ${r['author'] ?? ''} · ${r['servings'] ?? 1} phần ăn',
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        if ((r['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r['description'].toString()),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dinh dưỡng mỗi phần (~${nutrition['grams_per_serving'] ?? '?'} g)',
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _macroBox('kcal', '${per['kcal'] ?? '?'}'),
                  const SizedBox(width: 8),
                  _macroBox('đạm (g)', complete ? '${per['protein_g']}' : '?'),
                  const SizedBox(width: 8),
                  _macroBox('béo (g)', complete ? '${per['fat_g']}' : '?'),
                  const SizedBox(width: 8),
                  _macroBox('bột (g)', complete ? '${per['carbs_g']}' : '?'),
                ],
              ),
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final l in labels) _labelChip(l)],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                complete
                    ? 'Số liệu ước tính từ khối lượng nguyên liệu, chỉ mang tính tham khảo.'
                    : 'Người đăng chưa nhập đủ đạm/béo/tinh bột cho một số nguyên liệu nên chỉ có kcal.',
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        _sectionTitle('Nguyên liệu'),
        for (final ing in ingredients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 6, color: _primary),
                const SizedBox(width: 10),
                Expanded(child: Text('${ing['name']}')),
                Text(
                  '${(ing['grams'] as num?)?.round() ?? ''} g',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        if (steps.isNotEmpty) ...[
          _sectionTitle('Cách làm'),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: const Color(0xFFD1FAE5),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: _primaryDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(steps[i])),
                ],
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _recipe;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        actions: [
          if (r != null) ...[
            if (r['is_mine'] == true)
              IconButton(
                tooltip: 'Xóa',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            TextButton.icon(
              onPressed: _busy ? null : _toggleLike,
              icon: Icon(
                r['liked_by_me'] == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: const Color(0xFFEF4444),
              ),
              label: Text(
                '${r['like_count'] ?? 0}',
                style: const TextStyle(color: _ink),
              ),
            ),
          ],
        ],
      ),
      body: r != null
          ? _buildContent(r)
          : Center(
              child: _error != null
                  ? Text(_error!)
                  : const CircularProgressIndicator(),
            ),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _eat,
                    icon: const Icon(Icons.restaurant_rounded, size: 18),
                    label: const Text('Ăn theo công thức này'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}