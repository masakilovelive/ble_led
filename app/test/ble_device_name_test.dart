import 'package:flutter_test/flutter_test.dart';
import 'package:septronics/ble/ble_client.dart';
import 'package:septronics/env.dart';

void main() {
  test('accepts Noxel device names without case sensitivity', () {
    expect(
      BleClient.matchesDeviceName('Noxel-1', Env.deviceNameHints),
      isTrue,
    );
    expect(
      BleClient.matchesDeviceName('NOXEL-2', Env.deviceNameHints),
      isTrue,
    );
  });

  test('keeps compatibility with legacy XIAO device names', () {
    expect(
      BleClient.matchesDeviceName(
        'XIAO-ESP32C6-LED-1',
        Env.deviceNameHints,
      ),
      isTrue,
    );
  });

  test('rejects unrelated and unnamed BLE devices', () {
    expect(
      BleClient.matchesDeviceName('Other-1', Env.deviceNameHints),
      isFalse,
    );
    expect(BleClient.matchesDeviceName('', Env.deviceNameHints), isFalse);
  });
}
