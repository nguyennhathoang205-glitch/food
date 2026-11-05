import 'dart:typed_data';

class OnDeviceDetection {
  final int classId;
  final double score;

  const OnDeviceDetection(this.classId, this.score);
}

class OnDeviceDetector {
  /// Web khong chay duoc TFLite.
  static bool get isSupported => false;

  static Future<List<OnDeviceDetection>> detect(Uint8List imageBytes) async =>
      const [];
}

