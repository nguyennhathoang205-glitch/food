// AI nhan dien mon an ngay tren dien thoai (TFLite). Tren web tu dong dung
// ban stub (khong ho tro) de van build/chay duoc tren Chrome.
export 'on_device_detector_stub.dart'
    if (dart.library.io) 'on_device_detector_io.dart';
