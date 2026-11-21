import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

@JS('window')
external JSObject get _window;

class LiveMotionTracker {
  int? _watchId;
  JSFunction? _motionListener;
  double? _lastLat;
  double? _lastLng;
  DateTime? _lastFixTime;
  DateTime? _lastStepTime;
  DateTime? _prevCandidateStepTime;

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
    stop();
    _lastLat = null;
    _lastLng = null;
    _lastFixTime = null;
    _lastStepTime = null;
    _prevCandidateStepTime = null;

    _startGeolocation(
      onGpsFix: onGpsFix,
      onGpsMove: onGpsMove,
      onGpsError: onGpsError,
    );
    _startDeviceMotion(onStepDetected: onStepDetected);
  }

  void _startGeolocation({
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
  }) {
    try {
      final nav = _window.getProperty<JSAny?>('navigator'.toJS);
      if (nav == null || nav.isUndefinedOrNull) {
        onGpsError('Trình duyệt không hỗ trợ định vị GPS.');
        return;
      }
      final navObj = nav as JSObject;
      final geo = navObj.getProperty<JSAny?>('geolocation'.toJS);
      if (geo == null || geo.isUndefinedOrNull) {
        onGpsError('Thiết bị không có GPS.');
        return;
      }
      final geoObj = geo as JSObject;

      final onSuccess = ((JSAny? posAny) {
        if (posAny == null || posAny.isUndefinedOrNull) return;
        final posObj = posAny as JSObject;
        final coordsAny = posObj.getProperty<JSAny?>('coords'.toJS);
        if (coordsAny == null || coordsAny.isUndefinedOrNull) return;
        final coords = coordsAny as JSObject;

        final lat = _numProp(coords, 'latitude');
        final lng = _numProp(coords, 'longitude');
        final acc = _numProp(coords, 'accuracy') ?? 15.0;
        final spd = _numProp(coords, 'speed');

        if (lat == null || lng == null) return;
        final now = DateTime.now();

        if (_lastLat == null || _lastLng == null || _lastFixTime == null) {
          _lastLat = lat;
          _lastLng = lng;
          _lastFixTime = now;
          onGpsFix(lat, lng, acc);
          return;
        }

        onGpsFix(lat, lng, acc);

        final distM = _haversineMeters(_lastLat!, _lastLng!, lat, lng);
        final dtSec =
            math.max(1, now.difference(_lastFixTime!).inMilliseconds) / 1000.0;
        final calcSpeedMps = distM / dtSec;

        // Bo loc chong nhieu GPS khi dung yen (Anti-drift filter):
        // Chi ghi nhan khi quang duong dich chuyen vuot qua sai so nhieu GPS
        // (toi thieu 4.5m) VA van toc nam trong nguong di bo / chay / dap xe
        // thuc te (0.4 m/s -> 15 m/s).
        final minMoveThreshold = math.max(4.5, (acc * 0.45).clamp(4.5, 22.0));
        final hardwareStationary = spd != null && spd >= 0 && spd < 0.35;

        if (!hardwareStationary &&
            distM >= minMoveThreshold &&
            calcSpeedMps >= 0.40 &&
            calcSpeedMps <= 15.0) {
          _lastLat = lat;
          _lastLng = lng;
          _lastFixTime = now;
          onGpsMove(distM, lat, lng, acc, spd ?? calcSpeedMps);
        }
      }).toJS;

      final onError = ((JSAny? errAny) {
        String msg = 'Chưa cấp quyền GPS hoặc đang ở trong nhà.';
        if (errAny != null && !errAny.isUndefinedOrNull) {
          final errObj = errAny as JSObject;
          final code = _numProp(errObj, 'code')?.toInt();
          if (code == 1) {
            msg = 'Bạn đã từ chối quyền Vị trí (GPS). Hãy bật quyền GPS.';
          } else if (code == 2) {
            msg = 'Không bắt được vệ tinh GPS.';
          } else if (code == 3) {
            msg = 'Đang chờ tín hiệu GPS...';
          }
        }
        onGpsError(msg);
      }).toJS;

      final options = JSObject();
      options.setProperty('enableHighAccuracy'.toJS, true.toJS);
      options.setProperty('maximumAge'.toJS, 1000.toJS);
      options.setProperty('timeout'.toJS, 12000.toJS);

      final idAny = geoObj.callMethodVarArgs<JSAny?>('watchPosition'.toJS, [
        onSuccess,
        onError,
        options,
      ]);
      if (idAny != null && !idAny.isUndefinedOrNull) {
        _watchId = (idAny as JSNumber).toDartInt;
      }
    } catch (_) {
      onGpsError('Không khởi tạo được GPS trên trình duyệt này.');
    }
  }

  void _startDeviceMotion({required void Function() onStepDetected}) {
    try {
      final listener = ((JSAny? evAny) {
        if (evAny == null || evAny.isUndefinedOrNull) return;
        final ev = evAny as JSObject;
        final accAny = ev.getProperty<JSAny?>(
          'accelerationIncludingGravity'.toJS,
        );
        if (accAny == null || accAny.isUndefinedOrNull) return;
        final acc = accAny as JSObject;

        final x = _numProp(acc, 'x');
        final y = _numProp(acc, 'y');
        final z = _numProp(acc, 'z');
        if (x == null || y == null || z == null) return;

        final mag = math.sqrt(x * x + y * y + z * z);
        final deltaG = (mag - 9.81).abs();

        // Phat hien nhip buoc chan thuc te (Step Peak Detection):
        // Can it nhat 2 nhip dao dong lien tiep (> 2.3 m/s^2) cach nhau 300ms - 1400ms
        // de tranh rung tay nhe khi cam dien thoai.
        if (deltaG > 2.35) {
          final now = DateTime.now();
          if (_lastStepTime != null &&
              now.difference(_lastStepTime!).inMilliseconds < 320) {
            return;
          }
          if (_prevCandidateStepTime != null &&
              now.difference(_prevCandidateStepTime!).inMilliseconds <= 1400) {
            _lastStepTime = now;
            _prevCandidateStepTime = now;
            onStepDetected();
          } else {
            _prevCandidateStepTime = now;
          }
        }
      }).toJS;

      _motionListener = listener;
      _window.callMethodVarArgs<JSAny?>('addEventListener'.toJS, [
        'devicemotion'.toJS,
        listener,
      ]);
    } catch (_) {}
  }

  double? _numProp(JSObject obj, String key) {
    try {
      final v = obj.getProperty<JSAny?>(key.toJS);
      if (v == null || v.isUndefinedOrNull) return null;
      if (v.typeofEquals('number')) {
        final d = (v as JSNumber).toDartDouble;
        if (d.isNaN || d.isInfinite) return null;
        return d;
      }
    } catch (_) {}
    return null;
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  void stop() {
    try {
      if (_watchId != null) {
        final nav = _window.getProperty<JSAny?>('navigator'.toJS);
        if (nav != null && !nav.isUndefinedOrNull) {
          final geo = (nav as JSObject).getProperty<JSAny?>('geolocation'.toJS);
          if (geo != null && !geo.isUndefinedOrNull) {
            (geo as JSObject).callMethodVarArgs<JSAny?>('clearWatch'.toJS, [
              _watchId!.toJS,
            ]);
          }
        }
        _watchId = null;
      }
      if (_motionListener != null) {
        _window.callMethodVarArgs<JSAny?>('removeEventListener'.toJS, [
          'devicemotion'.toJS,
          _motionListener!,
        ]);
        _motionListener = null;
      }
    } catch (_) {}
  }
}

class VoiceSpeechRecognizer {
  JSObject? _rec;

  void startListening({
    required void Function(String text) onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  }) {
    stopListening();
    try {
      JSAny? ctor = _window.getProperty<JSAny?>('SpeechRecognition'.toJS);
      if (ctor == null || ctor.isUndefinedOrNull) {
        ctor = _window.getProperty<JSAny?>('webkitSpeechRecognition'.toJS);
      }
      if (ctor == null || ctor.isUndefinedOrNull) {
        onError('Trình duyệt chưa hỗ trợ Web Speech API (Hãy dùng Chrome/Edge).');
        onDone();
        return;
      }

      final rec = (ctor as JSFunction).callAsConstructor<JSObject>();
      _rec = rec;
      rec.setProperty('lang'.toJS, 'vi-VN'.toJS);
      rec.setProperty('interimResults'.toJS, false.toJS);
      rec.setProperty('maxAlternatives'.toJS, 1.toJS);

      rec.setProperty(
        'onresult'.toJS,
        ((JSAny? evAny) {
          try {
            if (evAny == null || evAny.isUndefinedOrNull) return;
            final ev = evAny as JSObject;
            final results = ev.getProperty<JSObject>('results'.toJS);
            final firstList = results.getProperty<JSObject>('0'.toJS);
            final firstAlt = firstList.getProperty<JSObject>('0'.toJS);
            final transcriptAny = firstAlt.getProperty<JSAny?>('transcript'.toJS);
            if (transcriptAny != null && !transcriptAny.isUndefinedOrNull) {
              final text = (transcriptAny as JSString).toDart.trim();
              if (text.isNotEmpty) {
                onResult(text);
              }
            }
          } catch (_) {}
        }).toJS,
      );

      rec.setProperty(
        'onerror'.toJS,
        ((JSAny? errAny) {
          onError('Không nghe rõ giọng nói hoặc chưa cấp quyền Micro.');
          onDone();
        }).toJS,
      );

      rec.setProperty(
        'onend'.toJS,
        ((JSAny? _) {
          onDone();
        }).toJS,
      );

      rec.callMethodVarArgs<JSAny?>('start'.toJS, []);
    } catch (_) {
      onError('Không khởi động được Micro nhận diện tiếng Việt.');
      onDone();
    }
  }

  void stopListening() {
    try {
      if (_rec != null) {
        _rec!.callMethodVarArgs<JSAny?>('stop'.toJS, []);
        _rec = null;
      }
    } catch (_) {}
  }
}


