import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;

import '../env.dart';
import 'ble_permissions.dart';
import 'ble_client.dart';
import 'models.dart';

final scanProvider = StateNotifierProvider.autoDispose<ScanController,
    AsyncValue<List<BleDevice>>>(
  (ref) => ScanController(ref),
);

class ScanController extends StateNotifier<AsyncValue<List<BleDevice>>> {
  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();
  StreamSubscription<DiscoveredDevice>? _sub;
  int _session = 0;

  ScanController(this._ref) : super(const AsyncValue.data([]));

  BleClient get _client => _ref.read(bleClientProvider);

  Future<void> start() async {
    final session = ++_session;
    final granted = await _ensurePermissions();
    if (session != _session) {
      return;
    }
    if (!granted) {
      state =
          AsyncValue.error('BLE permissions not granted', StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    await _sub?.cancel();
    if (session != _session) {
      return;
    }
    final map = <String, BleDevice>{};
    _sub = _client.scan(nameHint: Env.nameHint).listen(
      (d) {
        if (session != _session) {
          return;
        }
        map[d.id] = BleDevice(
            id: d.id, name: d.name.isEmpty ? null : d.name, rssi: d.rssi);
        state = AsyncValue.data(map.values.toList());
      },
      onError: (e, st) {
        if (session != _session) {
          return;
        }
        _log.e('scan error', error: e, stackTrace: st);
        state = AsyncValue.error(e, st);
      },
    );
  }

  Future<bool> _ensurePermissions() async {
    return ensureBlePermissions(_log);
  }

  Future<void> stop() async {
    _session++;
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _session++;
    _sub?.cancel();
    super.dispose();
  }
}
