// ============================================================
// MAM COM GIA DINH
// ============================================================
// Chup 1 mam nhieu mon -> AI tach tung mon (ban co the sua / them / xoa) ->
// khai bao ai dang an (he so phan, mon khong an) -> chia phan cho tung nguoi
// -> luu phan cua minh vao nhat ky. Xem backend/family_meal.py.
//
// Mo bang FamilyMealScreen.open(context).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth_http.dart' as http;
import '../../core/app_config.dart';
import '../../widgets/meal_slot_picker.dart';

const Color _primary = Color(0xFF10B981);
const Color _primaryDark = Color(0xFF059669);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _line = Color(0xFFE2E8F0);
const Color _danger = Color(0xFFDC2626);

const int _maxDishes = 12;
const int _maxMembers = 8;

// He so phan an: (gia tri, nhan hien thi)
const List<MapEntry<double, String>> _weightOptions = [
  MapEntry(0.5, 'Bé nhỏ · 0.5'),
  MapEntry(0.75, 'Trẻ em · 0.75'),
  MapEntry(1.0, 'Người lớn · 1'),
  MapEntry(1.25, 'Ăn khá nhiều · 1.25'),
  MapEntry(1.5, 'Ăn nhiều · 1.5'),
];

class _Dish {
  String name;
  double grams;
  double calories;
  double? protein;
  double? fat;
  double? carbs;

  _Dish({
    required this.name,
    required this.grams,
    required this.calories,
    this.protein,
    this.fat,
    this.carbs,
  });

  factory _Dish.fromJson(Map<String, dynamic> j) => _Dish(
    name: '${j['name_vi'] ?? ''}',
    grams: (j['grams'] as num?)?.toDouble() ?? 0,
    calories: (j['calories'] as num?)?.toDouble() ?? 0,
    protein: (j['protein_g'] as num?)?.toDouble(),
    fat: (j['fat_g'] as num?)?.toDouble(),
    carbs: (j['carbs_g'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'name_vi': name,
    'grams': grams,
    'calories': calories,
    'protein_g': protein,
    'fat_g': fat,
    'carbs_g': carbs,
  };
}

class _Member {
  final TextEditingController name;
  final TextEditingController goal = TextEditingController();
  double weight = 1.0;
  Set<int> skip = {};

  _Member(String initialName) : name = TextEditingController(text: initialName);

  void dispose() {
    name.dispose();
    goal.dispose();
  }

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'weight': weight,
    'skip': skip.toList(),
    'goal_kcal': goal.text.trim().replaceAll(',', '.'),
  };
}

class FamilyMealScreen extends StatefulWidget {
  const FamilyMealScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FamilyMealScreen()),
    );
  }

  @override
  State<FamilyMealScreen> createState() => _FamilyMealScreenState();
}

class _FamilyMealScreenState extends State<FamilyMealScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<_Dish> _dishes = [];
  final List<_Member> _members = [_Member('Tôi'), _Member('Người 2')];

  bool _analyzing = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  String _api(String path) => '${AppConfig.baseUrl}/api/family$path';

  String _messageOf(http.Response res, String fallback) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _changed() => setState(() => _result = null);

  // ---------------- Anh -> mon ----------------

  Future<void> _analyze(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final req = http.MultipartRequest('POST', Uri.parse(_api('/analyze')));
      req.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'mam.jpg'),
      );
      final res = await http.Response.fromStream(await req.send());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (body['dishes'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(_Dish.fromJson)
            .toList();
        setState(() {
          _dishes
            ..clear()
            ..addAll(list);
          for (final m in _members) {
            m.skip = {};
          }
          _result = null;
        });
      } else {
        setState(() => _error = _messageOf(res, 'Không phân tích được ảnh.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ---------------- Sua / them / xoa mon ----------------

  Future<void> _editDish(int? index) async {
    final old = index == null ? null : _dishes[index];
    final nameCtrl = TextEditingController(text: old?.name ?? '');
    final gramsCtrl = TextEditingController(
      text: old == null ? '' : old.grams.round().toString(),
    );
    final kcalCtrl = TextEditingController(
      text: old == null ? '' : old.calories.round().toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'Thêm món' : 'Sửa món'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên món'),
            ),
            TextField(
              controller: gramsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Khối lượng (g)'),
            ),
            TextField(
              controller: kcalCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Calo cả phần (kcal)',
                helperText: old == null
                    ? null
                    : 'Đổi khối lượng mà giữ nguyên calo thì app tự tính lại',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final grams = double.tryParse(gramsCtrl.text.trim().replaceAll(',', '.'));
    final kcalText = kcalCtrl.text.trim().replaceAll(',', '.');
    final kcal = double.tryParse(kcalText);
    nameCtrl.dispose();
    gramsCtrl.dispose();
    kcalCtrl.dispose();

    if (ok != true || !mounted) return;
    if (name.length < 2 || grams == null || grams <= 0 || kcal == null) {
      _toast('Hãy nhập đủ tên món, khối lượng và calo.');
      return;
    }

    setState(() {
      if (old == null) {
        if (_dishes.length >= _maxDishes) return;
        _dishes.add(_Dish(name: name, grams: grams, calories: kcal));
      } else {
        final ratio = old.grams > 0 ? grams / old.grams : 1.0;
        final kcalEdited = kcal.round() != old.calories.round();
        old.name = name;
        old.calories = kcalEdited ? kcal : old.calories * ratio;
        if (old.protein != null) old.protein = old.protein! * ratio;
        if (old.fat != null) old.fat = old.fat! * ratio;
        if (old.carbs != null) old.carbs = old.carbs! * ratio;
        old.grams = grams;
      }
      _result = null;
    });
  }

  void _removeDish(int index) {
    setState(() {
      _dishes.removeAt(index);
      // Dich chi so "khong an" cua moi nguoi sau khi xoa 1 mon.
      for (final m in _members) {
        m.skip = m.skip
            .where((i) => i != index)
            .map((i) => i > index ? i - 1 : i)
            .toSet();
      }
      _result = null;
    });
  }

  // ---------------- Chia phan / luu ----------------

  Map<String, dynamic> _payload() => {
    'dishes': [for (final d in _dishes) d.toJson()],
    'members': [for (final m in _members) m.toJson()],
    'me_index': 0,
  };

  Future<void> _split() async {
    if (_dishes.isEmpty) {
      _toast('Hãy chụp mâm cơm hoặc thêm ít nhất 1 món.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse(_api('/split')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_payload()),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          _result = jsonDecode(utf8.decode(res.bodyBytes))
              as Map<String, dynamic>;
        });
      } else {
        setState(() => _error = _messageOf(res, 'Không chia được phần.'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không kết nối được máy chủ.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logMine() async {
    final slot = await pickMealSlot(context);
    if (slot == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await http.post(
        Uri.parse(_api('/log')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({..._payload(), 'meal_type': slot}),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        _toast(
          'Đã thêm phần của bạn (${(body['calories'] as num?)?.round() ?? 0} kcal) vào nhật ký ($slot).',
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

  // ---------------- Giao dien ----------------

  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: _line, width: 1.2),
  );

  Widget _title(String text, {String? sub}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
      if (sub != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sub, style: const TextStyle(color: _muted, fontSize: 12)),
        ),
    ],
  );

  Widget _buildPhotoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            '1. Chụp mâm cơm',
            sub: 'AI tách từng món và ước tính khối lượng, calo. Bạn có thể sửa lại.',
          ),
          const SizedBox(height: 12),
          if (_analyzing)
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('AI đang nhìn mâm cơm...'),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _analyze(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Chụp'),
                    style: FilledButton.styleFrom(backgroundColor: _primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _analyze(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Thư viện'),
                  ),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: _danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDishesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('2. Các món trên mâm (${_dishes.length})'),
          const SizedBox(height: 6),
          if (_dishes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Chưa có món nào. Chụp ảnh hoặc thêm bằng tay.',
                style: TextStyle(color: _muted),
              ),
            ),
          for (var i = 0; i < _dishes.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _dishes[i].name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_dishes[i].grams.round()} g · ${_dishes[i].calories.round()} kcal',
              ),
              onTap: () => _editDish(i),
              trailing: IconButton(
                tooltip: 'Xóa món',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => _removeDish(i),
              ),
            ),
          TextButton.icon(
            onPressed: _dishes.length >= _maxDishes ? null : () => _editDish(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm món bằng tay'),
          ),
        ],
      ),
    );
  }

  Widget _buildMember(int index) {
    final m = _members[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: m.name,
                  onChanged: (_) => _changed(),
                  decoration: InputDecoration(
                    labelText: index == 0 ? 'Bạn' : 'Tên người ăn',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (index > 0)
                IconButton(
                  tooltip: 'Xóa người này',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: () => setState(() {
                    _members.removeAt(index).dispose();
                    _result = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<double>(
                  initialValue: m.weight,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Hệ số phần',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    for (final o in _weightOptions)
                      DropdownMenuItem(value: o.key, child: Text(o.value)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    m.weight = v;
                    _changed();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: m.goal,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _changed(),
                  decoration: InputDecoration(
                    labelText: 'Mục tiêu kcal/ngày',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_dishes.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Món người này KHÔNG ăn:',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (var i = 0; i < _dishes.length; i++)
                  FilterChip(
                    label: Text(
                      _dishes[i].name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: m.skip.contains(i),
                    visualDensity: VisualDensity.compact,
                    selectedColor: const Color(0xFFFEE2E2),
                    onSelected: (v) {
                      if (v) {
                        m.skip.add(i);
                      } else {
                        m.skip.remove(i);
                      }
                      _changed();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            '3. Ai đang ăn?',
            sub: 'Hệ số càng lớn thì ăn càng nhiều. Món ai không ăn sẽ chia cho những người còn lại.',
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _members.length; i++) _buildMember(i),
          TextButton.icon(
            onPressed: _members.length >= _maxMembers
                ? null
                : () => setState(() {
                    _members.add(_Member('Người ${_members.length + 1}'));
                    _result = null;
                  }),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Thêm người'),
          ),
        ],
      ),
    );
  }

  String _warningText(dynamic w) {
    if (w is String) return w;
    if (w is Map) {
      for (final key in ['message', 'warning', 'text', 'title']) {
        if (w[key] != null) return '${w[key]}';
      }
    }
    return '$w';
  }

  Widget _buildResult() {
    final r = _result;
    if (r == null) return const SizedBox.shrink();

    final members = (r['members'] as List? ?? []).whereType<Map>().toList();
    final total = r['total'] as Map? ?? const {};
    final complete = r['macros_complete'] != false;
    final warnings = (r['warnings'] as List? ?? []);
    final uneaten = (r['dishes'] as List? ?? [])
        .whereType<Map>()
        .where((d) => d['uneaten'] == true)
        .map((d) => '${d['name_vi']}')
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Kết quả chia phần',
            sub: 'Cả mâm: ${(total['calories'] as num?)?.round() ?? 0} kcal · ${(total['grams'] as num?)?.round() ?? 0} g. Số liệu là ước tính.',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < members.length; i++)
            _buildMemberResult(i, members[i], complete),
          if (uneaten.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Không ai ăn: ${uneaten.join(', ')} (không tính vào phần của ai).',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Lưu ý cho phần của bạn:',
              style: TextStyle(color: _danger, fontWeight: FontWeight.w800),
            ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• ${_warningText(w)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _logMine,
              icon: const Icon(Icons.bookmark_add_rounded, size: 18),
              label: const Text('Lưu phần của tôi vào nhật ký'),
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberResult(int index, Map m, bool complete) {
    final dishes = (m['dishes'] as List? ?? []).whereType<Map>().toList();
    final goalPercent = m['goal_percent'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            '${m['name']}${index == 0 ? ' (bạn)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${(m['calories'] as num?)?.round() ?? 0} kcal · ${(m['grams'] as num?)?.round() ?? 0} g'
            '${goalPercent != null ? ' · $goalPercent% mục tiêu ngày' : ''}'
            '${complete ? '\nĐạm ${m['protein_g']} g · Béo ${m['fat_g']} g · Bột ${m['carbs_g']} g' : ''}',
          ),
          children: [
            for (final d in dishes)
              ListTile(
                dense: true,
                title: Text('${d['name_vi']}'),
                trailing: Text(
                  '${(d['grams'] as num?)?.round() ?? 0} g · ${(d['calories'] as num?)?.round() ?? 0} kcal',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            if (dishes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Không ăn món nào.'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Mâm cơm gia đình',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildPhotoCard(),
          const SizedBox(height: 12),
          _buildDishesCard(),
          const SizedBox(height: 12),
          _buildMembersCard(),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _split,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryDark,
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
                  : const Text('Chia phần'),
            ),
          ),
          _buildResult(),
        ],
      ),
    );
  }
}