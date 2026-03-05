import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../env.dart';
import 'ble_client.dart';

class VoltageSample {
  final int raw;
  final int millivolts;
  final DateTime timestamp;

  const VoltageSample({
    required this.raw,
    required this.millivolts,
    required this.timestamp,
  });

  double get volts => millivolts / 1000.0;
}

final voltageControllerProvider = Provider<VoltageController>((ref) {
  return VoltageController(ref.read(bleClientProvider));
});

class VoltageController {
  final BleClient _client;
  final _log = Logger();

  VoltageController(this._client);

  VoltageSample _decode(List<int> data) {
    if (data.length < 4) {
      throw StateError("Voltage characteristic expects 4 bytes but got ${data.length}");
    }
    final raw = data[0] | (data[1] << 8);
    final mv = data[2] | (data[3] << 8);
    return VoltageSample(raw: raw, millivolts: mv, timestamp: DateTime.now());
  }

  Future<VoltageSample> readSample(String deviceId) async {
    final data = await _client.read(
      deviceId: deviceId,
      serviceUuid: Env.customServiceUuid,
      charUuid: Env.voltageUuid,
    );
    final sample = _decode(data);
    _log.i("Voltage read: ${sample.millivolts} mV (raw ${sample.raw})");
    return sample;
  }

  Stream<VoltageSample> monitor(String deviceId) {
    return _client
        .subscribe(
          deviceId: deviceId,
          serviceUuid: Env.customServiceUuid,
          charUuid: Env.voltageUuid,
        )
        .map(_decode);
  }
}
