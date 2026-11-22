import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Native iOS / Android implementation using CoreLocation (geolocator)
/// and CoreMotion accelerometer (sensors_plus) for real step & GPS tracking.
class LiveMotionTracker {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;
  StreamSubscription<AccelerometerEvent>? _rawAccelSub;

  double? _lastLat;
  double? _lastLng;
  DateTime? _lastFixTime;
  DateTime? _lastStepTime;

  // Bo loc trung binh truot de phat hien nhip buoc chan tu gia toc ke 3 truc
  double _emaMag = 0.0;

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
    _emaMag = 0.0;

    _startNativeAccelerometer(onStepDetected: onStepDetected);
    _startNativeGps(
      onGpsFix: onGpsFix,
      onGpsMove: onGpsMove,
      onGpsError: onGpsError,
    );
  }

  void _startNativeAccelerometer({
    required void Function() onStepDetected,
  }) {
    try {
      // Uu tien UserAccelerometer (da tru gia toc trong truong 9.81 m/s^2 tren iOS CoreMotion)
      _userAccelSub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (event) {
          final mag = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          _processLinearAcceleration(mag, onStepDetected);
        },
        onError: (_) {
          _startRawAccelerometerFallback(onStepDetected: onStepDetected);
        },
      );
    } catch (_) {
      _startRawAccelerometerFallback(onStepDetected: onStepDetected);
    }
  }

  void _startRawAccelerometerFallback({
    required void Function() onStepDetected,
  }) {
    try {
      _rawAccelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen((event) {
        final totalMag = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        final linearMag = (totalMag - 9.80665).abs();
        _processLinearAcceleration(linearMag, onStepDetected);
      }, onError: (_) {});
    } catch (_) {}
  }

  void _processLinearAcceleration(
    double linearMag,
    void Function() onStepDetected,
  ) {
    // Lam muot nhe va bat dinh nhip buoc chan khi di bo / chay bo (nguong 1.15 m/s^2)
    _emaMag = _emaMag * 0.55 + linearMag * 0.45;
    if (_emaMag >= 1.15 && linearMag >= 1.25) {
      final now = DateTime.now();
      // Khoang cach giua 2 buoc chan: 260ms (~230 buoc/phut) den 2000ms
      if (_lastStepTime == null ||
          now.difference(_lastStepTime!).inMilliseconds >= 280) {
        _lastStepTime = now;
        onStepDetected();
      }
    }
  }

  Future<void> _startNativeGps({
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
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onGpsError('Đang đếm bước bằng Cảm biến chuyển động (Bật GPS để đo bản đồ).');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        onGpsError('Đang đo bằng Cảm biến bước chân (Chưa cấp quyền GPS).');
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      );

      _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          final lat = pos.latitude;
          final lng = pos.longitude;
          final acc = pos.accuracy > 0 ? pos.accuracy : 10.0;
          final spd = pos.speed >= 0 ? pos.speed : null;
          final now = DateTime.now();

          onGpsFix(lat, lng, acc);

          if (_lastLat == null || _lastLng == null || _lastFixTime == null) {
            _lastLat = lat;
            _lastLng = lng;
            _lastFixTime = now;
            return;
          }

          final distM = Geolocator.distanceBetween(
            _lastLat!,
            _lastLng!,
            lat,
            lng,
          );
          final dtSec =
              math.max(1, now.difference(_lastFixTime!).inMilliseconds) /
              1000.0;
          final impliedSpeedMps = distM / dtSec;

          // Loc nhieu GPS khi dung yen va loai bo nhay toa do bat thuong (> 16 m/s)
          final minMoveThreshold = math.max(1.8, math.min(acc * 0.25, 4.5));
          if (distM >= minMoveThreshold && impliedSpeedMps <= 16.0) {
            _lastLat = lat;
            _lastLng = lng;
            _lastFixTime = now;
            onGpsMove(distM, lat, lng, acc, spd ?? impliedSpeedMps);
          }
        },
        onError: (_) {
          onGpsError('Đang đo bước chân trực tiếp bằng cảm biến chuyển động.');
        },
      );
    } catch (_) {
      onGpsError('Đang đo bước chân trực tiếp bằng cảm biến chuyển động.');
    }
  }

  void stop() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _userAccelSub?.cancel();
    _userAccelSub = null;
    _rawAccelSub?.cancel();
    _rawAccelSub = null;
  }
}

class VoiceSpeechRecognizer {
  void startListening({
    required void Function(String text) onResult,
    required void Function(String error) onError,
    required void Function() onDone,
  }) {
    onError('Hãy dùng biểu tượng Micro (🎙️) trên bàn phím iPhone để đọc tiếng Việt.');
    onDone();
  }

  void stopListening() {}
}
