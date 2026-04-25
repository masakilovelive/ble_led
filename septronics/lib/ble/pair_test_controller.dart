import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;

import 'ble_permissions.dart';
import 'ble_client.dart';
import 'led_controller.dart';
import 'models.dart';
import 'scan_controller.dart';
import '../storage/local_store.dart';

enum PairSide { a, b }

class DeviceNameInfo {
  final int? deviceNumber;
  final int? pairNumber;
  final String? role;

  const DeviceNameInfo({
    this.deviceNumber,
    this.pairNumber,
    this.role,
  });

  static DeviceNameInfo fromName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return const DeviceNameInfo();
    }
    final match = RegExp(r'(?:-|_)(\d+)$').firstMatch(name.trim());
    if (match == null) {
      return const DeviceNameInfo();
    }
    final number = int.tryParse(match.group(1)!);
    if (number == null || number <= 0) {
      return const DeviceNameInfo();
    }
    final pairNumber = ((number - 1) ~/ 2) + 1;
    final role = number.isOdd ? 'A' : 'B';
    return DeviceNameInfo(
      deviceNumber: number,
      pairNumber: pairNumber,
      role: role,
    );
  }
}

class PairSideState {
  final BleDevice? device;
  final DeviceConnectionState status;
  final String? message;
  final int? deviceNumber;
  final int? pairNumber;
  final String? role;

  const PairSideState({
    this.device,
    this.status = DeviceConnectionState.disconnected,
    this.message,
    this.deviceNumber,
    this.pairNumber,
    this.role,
  });

  PairSideState copyWith({
    BleDevice? device,
    DeviceConnectionState? status,
    String? message,
    int? deviceNumber,
    int? pairNumber,
    String? role,
  }) {
    return PairSideState(
      device: device ?? this.device,
      status: status ?? this.status,
      message: message,
      deviceNumber: deviceNumber ?? this.deviceNumber,
      pairNumber: pairNumber ?? this.pairNumber,
      role: role ?? this.role,
    );
  }
}

class PairTestState {
  final PairSideState a;
  final PairSideState b;
  final bool autoReconnect;
  final bool isTesting;
  final String? message;
  final List<String> logs;

  const PairTestState({
    required this.a,
    required this.b,
    this.autoReconnect = true,
    this.isTesting = false,
    this.message,
    this.logs = const [],
  });

  factory PairTestState.initial() {
    return const PairTestState(
      a: PairSideState(),
      b: PairSideState(),
    );
  }

  bool get hasPairMismatch {
    if (a.pairNumber == null || b.pairNumber == null) {
      return false;
    }
    return a.pairNumber != b.pairNumber;
  }

  bool get roleMismatchA => a.role != null && a.role != 'A';
  bool get roleMismatchB => b.role != null && b.role != 'B';

  PairTestState copyWith({
    PairSideState? a,
    PairSideState? b,
    bool? autoReconnect,
    bool? isTesting,
    String? message,
    List<String>? logs,
  }) {
    return PairTestState(
      a: a ?? this.a,
      b: b ?? this.b,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      isTesting: isTesting ?? this.isTesting,
      message: message,
      logs: logs ?? this.logs,
    );
  }
}

final pairTestProvider =
    StateNotifierProvider<PairTestController, PairTestState>(
  (ref) => PairTestController(ref),
);

class PairTestController extends StateNotifier<PairTestState> {
  static const _prefsKeyAId = 'pair_test_a_id';
  static const _prefsKeyAName = 'pair_test_a_name';
  static const _prefsKeyBId = 'pair_test_b_id';
  static const _prefsKeyBName = 'pair_test_b_name';
  static const _prefsKeyAutoReconnect = 'pair_test_auto_reconnect';

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  StreamSubscription<ConnectionStateUpdate>? _connA;
  StreamSubscription<ConnectionStateUpdate>? _connB;
  Timer? _reconnectA;
  Timer? _reconnectB;
  bool _manualDisconnectA = false;
  bool _manualDisconnectB = false;

  PairTestController(this._ref) : super(PairTestState.initial()) {
    Future.microtask(_loadStored);
  }

  BleClient get _client => _ref.read(bleClientProvider);
  LedController get _led => _ref.read(ledControllerProvider);
  ScanController get _scanner => _ref.read(scanProvider.notifier);

  void selectDevice(PairSide side, BleDevice device) {
    final prev = _sideState(side).device;
    if (prev != null && prev.id != device.id) {
      unawaited(disconnect(side));
    }
    final info = DeviceNameInfo.fromName(device.name);
    final nextSide = _sideState(side).copyWith(
      device: device,
      deviceNumber: info.deviceNumber,
      pairNumber: info.pairNumber,
      role: info.role,
      message: null,
      status: DeviceConnectionState.disconnected,
    );
    _setSideState(side, nextSide);
    _appendLog(
      'Assigned ${side.name.toUpperCase()} -> ${device.name ?? device.id}',
    );
    unawaited(_persistSide(side));
  }

  Future<void> connect(PairSide side) async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _setMessage('BLE permissions not granted');
      return;
    }
    await _scanner.stop();
    final sideState = _sideState(side);
    final device = sideState.device;
    if (device == null) {
      _setMessage('Select a device for ${side.name.toUpperCase()} first.');
      return;
    }
    if (_hasMismatchFor(side)) {
      _setMessage(
          'N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}');
      return;
    }
    if (side == PairSide.a && state.roleMismatchA) {
      _setMessage('Device number indicates role B. Assign an A device.');
      return;
    }
    if (side == PairSide.b && state.roleMismatchB) {
      _setMessage('Device number indicates role A. Assign a B device.');
      return;
    }

    _setManualDisconnect(side, false);
    await _cancelConnection(side);
    _setSideState(
      side,
      sideState.copyWith(
        status: DeviceConnectionState.connecting,
        message: null,
      ),
    );
    _appendLog(
        'Connecting ${side.name.toUpperCase()} -> ${device.name ?? device.id}');

    final subscription = _client.connect(device.id).listen(
      (u) async {
        final updated = _sideState(side).copyWith(status: u.connectionState);
        _setSideState(side, updated);
        if (u.connectionState == DeviceConnectionState.connected) {
          _appendLog('${side.name.toUpperCase()} connected');
        } else if (u.connectionState == DeviceConnectionState.disconnected) {
          _appendLog('${side.name.toUpperCase()} disconnected');
          _scheduleReconnect(side);
        }
      },
      onError: (e, st) {
        _log.e('pair connect error', error: e, stackTrace: st);
        _setSideState(
          side,
          _sideState(side).copyWith(
            status: DeviceConnectionState.disconnected,
            message: e.toString(),
          ),
        );
        _appendLog('${side.name.toUpperCase()} error: $e');
        _scheduleReconnect(side);
      },
    );

    _setConnection(side, subscription);
  }

  Future<void> connectBoth() async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _setMessage('BLE permissions not granted');
      return;
    }
    if (state.a.device == null || state.b.device == null) {
      _setMessage('Select both A and B devices before connecting.');
      return;
    }
    if (state.hasPairMismatch) {
      _setMessage(
          'N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}');
      return;
    }
    if (state.roleMismatchA || state.roleMismatchB) {
      _setMessage('Device roles do not match A/B assignment rules.');
      return;
    }
    await _scanner.stop();
    await connect(PairSide.a);
    await connect(PairSide.b);
  }

  Future<void> disconnect(PairSide side) async {
    _setManualDisconnect(side, true);
    _cancelReconnect(side);
    await _cancelConnection(side);
    _setSideState(
      side,
      _sideState(side).copyWith(status: DeviceConnectionState.disconnected),
    );
    _appendLog('${side.name.toUpperCase()} manual disconnect');
  }

  Future<void> disconnectBoth() async {
    await disconnect(PairSide.a);
    await disconnect(PairSide.b);
  }

  Future<void> clearDevice(PairSide side) async {
    await disconnect(side);
    _setSideState(
      side,
      const PairSideState(),
    );
    await _removeSide(side);
    _appendLog('${side.name.toUpperCase()} cleared');
  }

  Future<void> runCollisionTest() async {
    if (state.isTesting) {
      return;
    }
    if (state.a.device == null || state.b.device == null) {
      _setMessage('Select both A and B devices before running the test.');
      return;
    }
    if (state.hasPairMismatch) {
      _setMessage(
          'N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}');
      return;
    }
    if (state.roleMismatchA || state.roleMismatchB) {
      _setMessage('Device roles do not match A/B assignment rules.');
      return;
    }
    if (state.a.status != DeviceConnectionState.connected ||
        state.b.status != DeviceConnectionState.connected) {
      _setMessage('Connect both A and B before running the test.');
      return;
    }

    state = state.copyWith(isTesting: true, message: null);
    _appendLog('Collision test start');
    try {
      final aId = state.a.device!.id;
      final bId = state.b.device!.id;
      await _led.setOutputEnabled(aId, true);
      await _led.setBrightness(aId, 255);
      await _led.setFrontColor(aId, 255, 255, 255);
      await _led.setRearColor(aId, 255, 255, 255);
      await Future.delayed(const Duration(milliseconds: 250));
      await _led.setOutputEnabled(bId, true);
      await _led.setBrightness(bId, 255);
      await _led.setFrontColor(bId, 255, 255, 255);
      await _led.setRearColor(bId, 255, 255, 255);
      await Future.delayed(const Duration(milliseconds: 250));
      await _led.applyIdleState(aId);
      await Future.delayed(const Duration(milliseconds: 200));
      await _led.applyIdleState(bId);
      _appendLog('Collision test complete');
    } catch (e, st) {
      _log.e('collision test failed', error: e, stackTrace: st);
      _appendLog('Collision test failed: $e');
      _setMessage('Collision test failed: $e');
    } finally {
      state = state.copyWith(isTesting: false);
    }
  }

  void setAutoReconnect(bool enabled) {
    state = state.copyWith(autoReconnect: enabled);
    if (!enabled) {
      _cancelReconnect(PairSide.a);
      _cancelReconnect(PairSide.b);
    }
    unawaited(_persistAutoReconnect());
  }

  void clearLogs() {
    state = state.copyWith(logs: []);
  }

  @override
  void dispose() {
    _cancelReconnect(PairSide.a);
    _cancelReconnect(PairSide.b);
    unawaited(_cancelConnection(PairSide.a));
    unawaited(_cancelConnection(PairSide.b));
    super.dispose();
  }

  PairSideState _sideState(PairSide side) =>
      side == PairSide.a ? state.a : state.b;

  void _setSideState(PairSide side, PairSideState next) {
    if (side == PairSide.a) {
      state = state.copyWith(a: next, message: null);
    } else {
      state = state.copyWith(b: next, message: null);
    }
  }

  Future<void> _cancelConnection(PairSide side) async {
    if (side == PairSide.a) {
      await _connA?.cancel();
      _connA = null;
    } else {
      await _connB?.cancel();
      _connB = null;
    }
  }

  void _setConnection(
      PairSide side, StreamSubscription<ConnectionStateUpdate> sub) {
    if (side == PairSide.a) {
      _connA = sub;
    } else {
      _connB = sub;
    }
  }

  void _setManualDisconnect(PairSide side, bool value) {
    if (side == PairSide.a) {
      _manualDisconnectA = value;
    } else {
      _manualDisconnectB = value;
    }
  }

  bool _manualDisconnect(PairSide side) =>
      side == PairSide.a ? _manualDisconnectA : _manualDisconnectB;

  void _scheduleReconnect(PairSide side) {
    if (!state.autoReconnect) {
      return;
    }
    if (_manualDisconnect(side)) {
      return;
    }
    if (_hasMismatchFor(side)) {
      return;
    }
    final timer = side == PairSide.a ? _reconnectA : _reconnectB;
    if (timer != null && timer.isActive) {
      return;
    }
    final next = Timer(const Duration(seconds: 2), () {
      if (_manualDisconnect(side)) {
        return;
      }
      final device = _sideState(side).device;
      if (device == null) {
        return;
      }
      unawaited(connect(side));
    });
    if (side == PairSide.a) {
      _reconnectA = next;
    } else {
      _reconnectB = next;
    }
  }

  void _cancelReconnect(PairSide side) {
    if (side == PairSide.a) {
      _reconnectA?.cancel();
      _reconnectA = null;
    } else {
      _reconnectB?.cancel();
      _reconnectB = null;
    }
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final line = '[$hh:$mm:$ss] $message';
    final nextLogs = List<String>.from(state.logs)..add(line);
    state = state.copyWith(logs: nextLogs);
  }

  bool _hasMismatchFor(PairSide side) {
    final other = side == PairSide.a ? state.b : state.a;
    if (other.device == null) {
      return false;
    }
    return state.hasPairMismatch;
  }

  void _setMessage(String message) {
    state = state.copyWith(message: message);
  }

  Future<bool> _ensurePermissions() async {
    return ensureBlePermissions(_log);
  }

  Future<void> _loadStored() async {
    try {
      final store = await LocalStore.instance();
      final autoReconnect = store.getBool(_prefsKeyAutoReconnect);
      if (autoReconnect != null) {
        state = state.copyWith(autoReconnect: autoReconnect);
      }

      final aId = store.getString(_prefsKeyAId);
      final aName = store.getString(_prefsKeyAName);
      final bId = store.getString(_prefsKeyBId);
      final bName = store.getString(_prefsKeyBName);

      if (aId != null && aId.isNotEmpty) {
        _restoreSide(PairSide.a, aId, aName);
      }
      if (bId != null && bId.isNotEmpty) {
        _restoreSide(PairSide.b, bId, bName);
      }

      if (state.autoReconnect) {
        _autoConnectIfReady();
      }
    } catch (e, st) {
      _log.e('load stored devices failed', error: e, stackTrace: st);
    }
  }

  void _restoreSide(PairSide side, String id, String? name) {
    final info = DeviceNameInfo.fromName(name);
    _setSideState(
      side,
      PairSideState(
        device: BleDevice(id: id, name: name),
        status: DeviceConnectionState.disconnected,
        deviceNumber: info.deviceNumber,
        pairNumber: info.pairNumber,
        role: info.role,
      ),
    );
  }

  void _autoConnectIfReady() {
    if (state.hasPairMismatch || state.roleMismatchA || state.roleMismatchB) {
      return;
    }
    if (state.a.device != null) {
      unawaited(connect(PairSide.a));
    }
    if (state.b.device != null) {
      unawaited(connect(PairSide.b));
    }
  }

  Future<void> _persistSide(PairSide side) async {
    final store = await LocalStore.instance();
    final device = _sideState(side).device;
    if (device == null) {
      await _removeSide(side);
      return;
    }
    if (side == PairSide.a) {
      await store.setString(_prefsKeyAId, device.id);
      if (device.name != null) {
        await store.setString(_prefsKeyAName, device.name!);
      } else {
        await store.remove(_prefsKeyAName);
      }
    } else {
      await store.setString(_prefsKeyBId, device.id);
      if (device.name != null) {
        await store.setString(_prefsKeyBName, device.name!);
      } else {
        await store.remove(_prefsKeyBName);
      }
    }
  }

  Future<void> _persistAutoReconnect() async {
    final store = await LocalStore.instance();
    await store.setBool(_prefsKeyAutoReconnect, state.autoReconnect);
  }

  Future<void> _removeSide(PairSide side) async {
    final store = await LocalStore.instance();
    if (side == PairSide.a) {
      await store.remove(_prefsKeyAId);
      await store.remove(_prefsKeyAName);
    } else {
      await store.remove(_prefsKeyBId);
      await store.remove(_prefsKeyBName);
    }
  }
}
