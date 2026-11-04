import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;

class BleClient {
  final FlutterReactiveBle _ble;
  final app_logger.Logger _log = app_logger.Logger();

  BleClient(this._ble);

  Stream<DiscoveredDevice> scan({Iterable<String> nameHints = const []}) {
    return _ble.scanForDevices(withServices: []).where((d) {
      return matchesDeviceName(d.name, nameHints);
    });
  }

  Future<Set<String>> discoverDeviceIds(
    Iterable<String> deviceIds, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final targets = deviceIds.toSet();
    final found = <String>{};
    if (targets.isEmpty) {
      return found;
    }

    final allFound = Completer<void>();
    final subscription = scan().listen(
      (device) {
        if (targets.contains(device.id)) {
          found.add(device.id);
          if (found.length == targets.length && !allFound.isCompleted) {
            allFound.complete();
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!allFound.isCompleted) {
          allFound.complete();
        }
      },
    );

    try {
      await Future.any<void>([
        allFound.future,
        Future<void>.delayed(timeout),
      ]);
    } finally {
      await subscription.cancel();
    }
    return found;
  }

  static bool matchesDeviceName(String name, Iterable<String> nameHints) {
    if (nameHints.isEmpty) return true;
    if (name.isEmpty) return false;
    final normalizedName = name.toLowerCase();
    return nameHints.any(
      (hint) => hint.isNotEmpty && normalizedName.contains(hint.toLowerCase()),
    );
  }

  Stream<ConnectionStateUpdate> connect(String deviceId) {
    return _ble.connectToDevice(
        id: deviceId, connectionTimeout: const Duration(seconds: 15));
  }

  Stream<ConnectionStateUpdate> connectAfterDiscovery(String deviceId) {
    return _ble.connectToAdvertisingDevice(
      id: deviceId,
      withServices: const [],
      prescanDuration: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 15),
    );
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
    // ignore: deprecated_member_use
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
