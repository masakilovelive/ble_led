import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;

class BleClient {
  final FlutterReactiveBle _ble;
  final app_logger.Logger _log = app_logger.Logger();

  BleClient(this._ble);

  Stream<DiscoveredDevice> scan({String? nameHint}) {
    return _ble.scanForDevices(withServices: []).where((d) {
      if (nameHint == null || nameHint.isEmpty) return true;
      return d.name.isNotEmpty && d.name.contains(nameHint);
    });
  }

  Stream<ConnectionStateUpdate> connect(String deviceId) {
    return _ble.connectToDevice(
        id: deviceId, connectionTimeout: const Duration(seconds: 15));
  }

  Future<List<int>> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
  }) async {
    final ch = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(charUuid),
    );
    return _ble.readCharacteristic(ch);
  }

  Future<List<DiscoveredService>> discoverServices(String deviceId) async {
    return _ble.discoverServices(deviceId);
  }

  Future<void> writeByte({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
    required int value,
  }) async {
    await writePayload(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      charUuid: charUuid,
      value: [value & 0xFF],
    );
  }

  Future<void> writePayload({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
    required List<int> value,
    bool withResponse = true,
  }) async {
    final ch = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(charUuid),
    );
    _log.i(
        "Write ${value.map((v) => '0x${v.toRadixString(16).padLeft(2, '0')}').join(' ')} to $charUuid");
    if (withResponse) {
      await _ble.writeCharacteristicWithResponse(ch, value: value);
    } else {
      await _ble.writeCharacteristicWithoutResponse(ch, value: value);
    }
  }

  Stream<List<int>> subscribe({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
  }) {
    final ch = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(charUuid),
    );
    return _ble.subscribeToCharacteristic(ch);
  }
}

final bleClientProvider = Provider<BleClient>((ref) {
  return BleClient(FlutterReactiveBle());
});
