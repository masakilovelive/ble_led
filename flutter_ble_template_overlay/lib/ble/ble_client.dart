
import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../env.dart';

class BleClient {
  final FlutterReactiveBle _ble;
  final _log = Logger();

  BleClient(this._ble);

  static final Set<String> _serviceHints = {
    Env.serviceUuid.toLowerCase(),
    Env.customServiceUuid.toLowerCase(),
  }..removeWhere((s) => s.isEmpty);

  Stream<DiscoveredDevice> scan({String? nameHint}) {
    final normalizedHint = nameHint?.toLowerCase();
    return _ble.scanForDevices(withServices: []).where((d) {
      final hasName = d.name.isNotEmpty;
      final matchesName = normalizedHint == null || normalizedHint.isEmpty
          ? hasName
          : (hasName && d.name.toLowerCase().contains(normalizedHint));
      final matchesService = _serviceHints.isNotEmpty &&
          d.serviceUuids.any((uuid) => _serviceHints.contains(uuid.toString().toLowerCase()));
      if (normalizedHint == null || normalizedHint.isEmpty) {
        return matchesName || matchesService;
      }
      return matchesName || matchesService;
    });
  }

  Stream<ConnectionStateUpdate> connect(String deviceId) {
    return _ble.connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 15));
  }

  Future<List<DiscoveredService>> discoverServices(String deviceId) async {
    return _ble.discoverServices(deviceId);
  }

  Future<List<int>> read({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
  }) async {
    final ch = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(charUuid),
    );
    final value = await _ble.readCharacteristic(ch);
    _log.i("Read ${value.length} bytes from $charUuid");
    return value;
  }

  Future<void> writeByte({
    required String deviceId,
    required String serviceUuid,
    required String charUuid,
    required int value,
  }) async {
    final ch = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(charUuid),
    );
    _log.i("Write 0x\${value.toRadixString(16).padLeft(2,'0')} to \$charUuid");
    await _ble.writeCharacteristicWithResponse(ch, value: [value & 0xFF]);
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
