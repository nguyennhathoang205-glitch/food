import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class OnDeviceDetection {
  final int classId;
  final double score;

  const OnDeviceDetection(this.classId, this.score);
}

/// Chay model YOLO (da xuat sang TFLite) truc tiep tren iOS/Android.
/// File model: assets/models/food_detector.tflite (duoc Codemagic xuat tu
/// backend/models/food_detector_yolo26.pt). Neu thieu file -> tra ve [].
class OnDeviceDetector {
  static const _modelAsset = 'assets/models/food_detector.tflite';
  static const _scoreThreshold = 0.40;
  static const _iouThreshold = 0.50;

  static Interpreter? _interpreter;
  static bool _failed = false;

  static bool get isSupported => true;

  static Future<Interpreter?> _load() async {
    if (_interpreter != null) return _interpreter;
    if (_failed) return null;
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
    } catch (_) {
      _failed = true;
    }
    return _interpreter;
  }

  static Future<List<OnDeviceDetection>> detect(Uint8List imageBytes) async {
    final interp = await _load();
    if (interp == null) return const [];

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return const [];

    final inShape = interp.getInputTensor(0).shape; // [1, H, W, 3]
    final h = inShape[1];
    final w = inShape[2];
    final resized = img.copyResize(decoded, width: w, height: h);

    final input = List.generate(
      1,
      (_) => List.generate(h, (y) {
        return List.generate(w, (x) {
          final p = resized.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        });
      }),
    );

    final outShape = interp.getOutputTensor(0).shape; // [1, C, N] hoac [1, N, C]
    final output = List.generate(
      1,
      (_) => List.generate(outShape[1], (_) => List.filled(outShape[2], 0.0)),
    );
    interp.run(input, output);

    final channelFirst = outShape[1] < outShape[2];
    final channels = channelFirst ? outShape[1] : outShape[2];
    final anchors = channelFirst ? outShape[2] : outShape[1];
    final numClasses = channels - 4;
    if (numClasses <= 0) return const [];

    double at(int c, int n) => channelFirst ? output[0][c][n] : output[0][n][c];

    final cands = <_Cand>[];
    for (var n = 0; n < anchors; n++) {
      var best = -1;
      var bestScore = 0.0;
      for (var c = 0; c < numClasses; c++) {
        final s = at(4 + c, n);
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (best < 0 || bestScore < _scoreThreshold) continue;
      final cx = at(0, n), cy = at(1, n), bw = at(2, n), bh = at(3, n);
      cands.add(_Cand(best, bestScore, cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2));
    }

    cands.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Cand>[];
    for (final c in cands) {
      if (kept.every((k) => k.classId != c.classId || _iou(k, c) < _iouThreshold)) {
        kept.add(c);
      }
    }
    return kept.map((k) => OnDeviceDetection(k.classId, k.score)).toList();
  }

  static double _iou(_Cand a, _Cand b) {
    final ix = math.max(0.0, math.min(a.x2, b.x2) - math.max(a.x1, b.x1));
    final iy = math.max(0.0, math.min(a.y2, b.y2) - math.max(a.y1, b.y1));
    final inter = ix * iy;
    final ua = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter;
    return ua <= 0 ? 0 : inter / ua;
  }
}

class _Cand {
  final int classId;
  final double score;
  final double x1, y1, x2, y2;

  _Cand(this.classId, this.score, this.x1, this.y1, this.x2, this.y2);
}

