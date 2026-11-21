// ============================================================
// CONG DONG DAY AI MON MOI
// ============================================================
// Nguoi dung chup 1-5 anh mot mon AI chua biet, dat ten -> server luu vector
// dac trung (CLIP) vao Supabase pgvector. Lan sau chup lai la nhan ra ngay,
// khong can train lai model. Xem backend/community_foods.py.
//
// Man hinh doc lap: mo bang TeachFoodScreen.open(context).

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

const int _maxImages = 5;

class TeachFoodScreen extends StatefulWidget {
  final Uint8List? initialImage;
  final String? initialName;

  const TeachFoodScreen({
    super.key,
    this.initialImage,
    this.initialName,
  });

  static Future<void> open(
    BuildContext context, {
    Uint8List? initialImage,
    String? initialName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeachFoodScreen(
          initialImage: initialImage,
          initialName: initialName,
        ),
      ),
    );
  }

  @override
  State<TeachFoodScreen> createState() => _TeachFoodScreenState();
}

class _TeachFoodScreenState extends State<TeachFoodScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _kcalCtrl = TextEditingController();

  final List<Uint8List> _teachImages = [];
  bool _teaching = false;
  String? _teachMessage;
  bool _teachOk = false;

  Uint8List? _testImage;
  bool _testing = false;
  String? _testError;
  Map<String, dynamic>? _best;
  List<dynamic> _candidates = [];
  bool _tested = false;

  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      _teachImages.add(widget.initialImage!);
    }
    if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
      _nameCtrl.text = widget.initialName!.trim();
    }
    _loadStats();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  String _messageOf(http.Response res, String fallback) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['message'] != null) {
        return body['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _loadStats() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/community/foods'),
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map<String, dynamic>) {
          setState(() => _stats = body);
        }
      }
    } catch (_) {}
  }

  Future<void> _addTeachImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;

    final room = _maxImages - _teachImages.length;
    final picked = <Uint8List>[];
    for (final f in files.take(room)) {
      picked.add(await f.readAsBytes());
    }
    if (!mounted) return;

    setState(() {
      _teachImages.addAll(picked);
      _teachMessage = files.length > room
          ? 'Chỉ nhận tối đa $_maxImages ảnh mỗi lần.'
          : null;
      _teachOk = false;
    });
  }

  Future<void> _takeTeachPhoto() async {
    if (_teachImages.length >= _maxImages) return;
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _teachImages.add(bytes);
      _teachMessage = null;
      _teachOk = false;
    });
  }

  Future<void> _teach() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      setState(() {
        _teachOk = false;
        _teachMessage = 'Hãy nhập tên món (ít nhất 2 ký tự).';
      });
      return;
    }
    if (_teachImages.isEmpty) {
      setState(() {
        _teachOk = false;
        _teachMessage = 'Hãy thêm ít nhất 1 ảnh của món.';
      });
      return;
    }

    setState(() {
      _teaching = true;
      _teachMessage = null;
    });

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/community/teach'),
      );
      req.fields['name_vi'] = name;
      final kcal = _kcalCtrl.text.trim();
      if (kcal.isNotEmpty) {
        req.fields['calories_per_100g'] = kcal;
      }
      for (var i = 0; i < _teachImages.length; i++) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'images',
            _teachImages[i],
            filename: 'teach_$i.jpg',
          ),
        );
      }

      final res = await http.Response.fromStream(await req.send());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        final added = body['images_added'] ?? _teachImages.length;
        final isNew = body['is_new'] == true;
        setState(() {
          _teachOk = true;
          _teachMessage = isNew
              ? 'AI đã học món mới "${body['name_vi']}" từ $added ảnh.'
              : 'Đã thêm $added ảnh cho món "${body['name_vi']}" (món này đã có người dạy).';
          _teachImages.clear();
        });
        _loadStats();
      } else {
        setState(() {
          _teachOk = false;
          _teachMessage = _messageOf(res, 'Không lưu được món mới.');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _teachOk = false;
          _teachMessage = 'Không kết nối được máy chủ.';
        });
      }
    } finally {
      if (mounted) setState(() => _teaching = false);
    }
  }

  Future<void> _test(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() {
      _testImage = bytes;
      _testing = true;
      _testError = null;
      _best = null;
      _candidates = [];
      _tested = false;
    });

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/community/recognize'),
      );
      req.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'test.jpg'),
      );
      final res = await http.Response.fromStream(await req.send());
      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _best = body['best'] is Map<String, dynamic>
              ? body['best'] as Map<String, dynamic>
              : null;
          _candidates = (body['candidates'] as List?) ?? [];
          _tested = true;
        });
      } else {
        setState(() => _testError = _messageOf(res, 'Không nhận diện được.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _testError = 'Không kết nối được máy chủ.');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _percent(dynamic similarity) {
    final value = (similarity as num?)?.toDouble() ?? 0;
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
  );

  Widget _thumb(Uint8List bytes, VoidCallback onRemove) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_primary, _primaryDark]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cộng đồng đã dạy AI ${s['total_foods'] ?? 0} món mới',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bạn đã đóng góp ${s['my_foods'] ?? 0} món · ${s['my_images'] ?? 0} ảnh',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeachCard() {
    final full = _teachImages.length >= _maxImages;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1. Dạy AI một món mới',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chụp 3–5 ảnh ở các góc khác nhau thì AI nhận chính xác hơn.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Tên món (vd: Bánh căn)',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _kcalCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Calo trên 100g (không bắt buộc)',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _teachImages.length; i++)
                _thumb(
                  _teachImages[i],
                  () => setState(() => _teachImages.removeAt(i)),
                ),
            ],
          ),
          if (_teachImages.isNotEmpty) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full || _teaching ? null : _takeTeachPhoto,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Chụp ảnh'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full || _teaching ? null : _addTeachImages,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: Text('Thư viện (${_teachImages.length}/$_maxImages)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: _teaching ? null : _teach,
              icon: _teaching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.school_rounded),
              label: Text(_teaching ? 'AI đang học...' : 'Dạy AI món này'),
            ),
          ),
          if (_teachMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _teachMessage!,
              style: TextStyle(
                color: _teachOk ? _primaryDark : const Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2. Thử xem AI đã nhận ra chưa',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chụp lại món đó ở một góc khác (không dùng lại ảnh đã dạy).',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : () => _test(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Chụp ảnh'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : () => _test(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Thư viện'),
                ),
              ),
            ],
          ),
          if (_testImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                _testImage!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_testing) ...[
            const SizedBox(height: 14),
            const Center(child: CircularProgressIndicator(color: _primary)),
          ],
          if (_testError != null) ...[
            const SizedBox(height: 10),
            Text(_testError!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
          if (_tested && !_testing) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _best != null
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _best != null
                    ? 'AI nhận ra: ${_best!['name_vi']} (giống ${_percent(_best!['similarity'])})'
                    : 'AI chưa chắc đây là món nào đã được dạy.',
                style: TextStyle(
                  color: _best != null ? _primaryDark : const Color(0xFF92400E),
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Các món giống nhất:',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              for (final c in _candidates.whereType<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${c['name_vi']}',
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        _percent(c['similarity']),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dạy AI món mới')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildStats(),
                const SizedBox(height: 14),
                _buildTeachCard(),
                const SizedBox(height: 14),
                _buildTestCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}