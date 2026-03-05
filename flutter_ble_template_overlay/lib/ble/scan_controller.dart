
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:logger/logger.dart';
import '../env.dart';
import 'ble_client.dart';
import 'models.dart';
import 'package:permission_handler/permission_handler.dart';


final scanProvider = StateNotifierProvider<ScanController, AsyncValue<List<BleDevice>>>(
  (ref) => ScanController(ref.read),
);

class ScanController extends StateNotifier<AsyncValue<List<BleDevice>>> {
  final Reader _read;
  final _log = Logger();
  StreamSubscription<DiscoveredDevice>? _sub;
  static final Set<String> _serviceHints = {
    Env.serviceUuid.toLowerCase(),
    Env.customServiceUuid.toLowerCase(),
  }..removeWhere((s) => s.isEmpty);

  ScanController(this._read) : super(const AsyncValue.data([]));

  BleClient get _client => _read(bleClientProvider);

  Future<void> start() async {
  final granted = await _ensurePermissions();
  if (!granted) {
    state = const AsyncValue.error('BLE permissions not granted');
    return;
  }

  state = const AsyncValue.loading();
  _sub?.cancel();
  final map = <String, BleDevice>{};
  _sub = _client.scan(nameHint: Env.nameHint).listen((d) {
    final resolvedName = _resolveName(d);
    map[d.id] = BleDevice(
      id: d.id,
      name: resolvedName?.isEmpty ?? true ? null : resolvedName,
      rssi: d.rssi,
    );
    state = AsyncValue.data(map.values.toList());
  }, onError: (e, st) {
    _log.e("scan error", e, st);
    state = AsyncValue.error(e, st);
  });
}


  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
Future<bool> _ensurePermissions() async {
  final permissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  final statuses = await permissions.request();
  return statuses.values.every((status) => status.isGranted || status.isLimited);
}

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String? _resolveName(DiscoveredDevice device) {
    if (device.name.isNotEmpty) {
      return device.name;
    }
    final matchesService = _serviceHints.isNotEmpty &&
        device.serviceUuids.any((uuid) => _serviceHints.contains(uuid.toString().toLowerCase()));
    if (matchesService && Env.nameHint.isNotEmpty) {
      return Env.nameHint;
    }
    return null;
  }
}
