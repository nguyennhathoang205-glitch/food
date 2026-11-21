class LiveMotionTracker {
  void start({
    required void Function(double lat, double lng, double accuracyMeters)
    onGpsFix,
    required void Function(
      double deltaMeters,
      double lat,
      double lng,
      double accuracyMeters,
      double? speedMps,
    )
    onGpsMove,
    required void Function(String message) onGpsError,
    required void Function() onStepDetected,
  }) {
    onGpsError('Thiết bị chỉ hỗ trợ cảm biến khi chạy trên trình duyệt/điện thoại.');
  }

  void stop() {}
}

class VoiceSpeechRecognizer {
  void startListening({
    required void Function(String text) onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  }) {
    onError('Nhận diện giọng nói trực tiếp hoạt động trên trình duyệt Chrome/Edge.');
    onDone();
  }

  void stopListening() {}
}


