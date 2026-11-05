import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/services/offline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isNetworkError nhan dien loi mang', () {
    expect(isNetworkError(Exception('SocketException: failed')), isTrue);
    expect(isNetworkError(Exception('Failed to fetch')), isTrue);
    expect(isNetworkError(Exception('Khong luu duoc')), isFalse);
  });

  test('OfflineMealQueue: luu offline roi dong bo, loi thi giu lai', () async {
    await OfflineMealQueue.enqueue({'food_name': 'Com tam', 'calories': 750});
    await OfflineMealQueue.enqueue({'food_name': 'Pho', 'calories': 450});
    expect(await OfflineMealQueue.count(), 2);

    // Mon dau gui thanh cong, mon sau van loi -> con lai 1.
    final synced = await OfflineMealQueue.flush(
      (m) async => m['food_name'] == 'Com tam',
    );
    expect(synced, 1);
    expect(await OfflineMealQueue.count(), 1);

    final synced2 = await OfflineMealQueue.flush((m) async => true);
    expect(synced2, 1);
    expect(await OfflineMealQueue.count(), 0);
  });

  test('foods_offline.json nap duoc 88 mon', () async {
    final foods = await OfflineFoods.load();
    expect(foods.length, greaterThan(50));
    expect(foods.every((f) => f.calories > 0), isTrue);
  });
}

