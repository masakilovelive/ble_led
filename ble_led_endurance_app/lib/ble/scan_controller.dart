import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;

import '../env.dart';
import 'ble_permissions.dart';
import 'ble_client.dart';
import 'models.dart';

final scanProvider =
    StateNotifierProvider<ScanController, AsyncValue<List<BleDevice>>>(
  (ref) => ScanController(ref),
);

class ScanController extends StateNotifier<AsyncValue<List<BleDevice>>> {
  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();
  StreamSubscription<DiscoveredDevice>? _sub;

  ScanController(this._ref) : super(const AsyncValue.data([]));

  BleClient get _client => _ref.read(bleClientProvider);

  Future<void> start() async {
    final granted = await _ensurePermissions();
    if (!granted) {
      state =
          AsyncValue.error('BLE permissions not granted', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    await _sub?.cancel();
    final map = <String, BleDevice>{};
    _sub = _client.scan(nameHint: Env.nameHint).listen(
      (d) {
        map[d.id] = BleDevice(
            id: d.id, name: d.name.isEmpty ? null : d.name, rssi: d.rssi);
        state = AsyncValue.data(map.values.toList());
      },
      onError: (e, st) {
        _log.e('scan error', error: e, stackTrace: st);
        state = AsyncValue.error(e, st);
      },
    );
  }

  Future<bool> _ensurePermissions() async {
    return ensureBlePermissions(_log);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
