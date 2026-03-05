
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../env.dart';
import 'ble_client.dart';

final ledControllerProvider = Provider<LedController>((ref) {
  return LedController(ref.read(bleClientProvider));
});

class LedController {
  final BleClient _client;
  final _log = Logger();
  LedController(this._client);

  Future<void> writeLevel(String deviceId, int level) async {
    _log.i("write AlertLevel level=$level");
    await _client.writeByte(
      deviceId: deviceId,
      serviceUuid: Env.serviceUuid,
      charUuid: Env.alertLevelUuid,
      value: level,
    );
  }
}
