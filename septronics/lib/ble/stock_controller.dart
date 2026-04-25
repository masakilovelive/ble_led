import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;

import '../app/product_ui_state.dart';
import '../env.dart';
import '../storage/local_store.dart';
import 'ble_permissions.dart';
import 'ble_client.dart';
import 'heartbeat_controller.dart';
import 'led_controller.dart';
import 'led_ui_state.dart';
import 'models.dart';

enum ResyncStatus { idle, running, success, failed }

class StockSideState {
  static const Object _sentinel = Object();

  final BleDevice? device;
  final DeviceConnectionState status;
  final int? pairNumber;
  final String? role;
  final String? message;
  final ResyncStatus resyncStatus;
  final String? resyncNote;

  const StockSideState({
    this.device,
    this.status = DeviceConnectionState.disconnected,
    this.pairNumber,
    this.role,
    this.message,
    this.resyncStatus = ResyncStatus.idle,
    this.resyncNote,
  });

  StockSideState copyWith({
    BleDevice? device,
    DeviceConnectionState? status,
    int? pairNumber,
    String? role,
    Object? message = _sentinel,
    ResyncStatus? resyncStatus,
    Object? resyncNote = _sentinel,
  }) {
    return StockSideState(
      device: device ?? this.device,
      status: status ?? this.status,
      pairNumber: pairNumber ?? this.pairNumber,
      role: role ?? this.role,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      resyncStatus: resyncStatus ?? this.resyncStatus,
      resyncNote: identical(resyncNote, _sentinel)
          ? this.resyncNote
          : resyncNote as String?,
    );
  }
}

class StockState {
  final StockSideState a;
  final StockSideState b;
  final bool loaded;
  final bool autoReconnect;
  final String? message;

  const StockState({
    required this.a,
    required this.b,
    this.loaded = false,
    this.autoReconnect = true,
    this.message,
  });

  factory StockState.initial() {
    return const StockState(a: StockSideState(), b: StockSideState());
  }

  bool get registered => a.device != null && b.device != null;

  bool get hasPairMismatch {
    if (a.pairNumber == null || b.pairNumber == null) {
      return false;
    }
    return a.pairNumber != b.pairNumber;
  }

  bool get roleMismatchA => a.role != null && a.role != 'A';
  bool get roleMismatchB => b.role != null && b.role != 'B';

  StockState copyWith({
    StockSideState? a,
    StockSideState? b,
    bool? loaded,
    bool? autoReconnect,
    String? message,
  }) {
    return StockState(
      a: a ?? this.a,
      b: b ?? this.b,
      loaded: loaded ?? this.loaded,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      message: message,
    );
  }
}

final stockProvider = StateNotifierProvider<StockController, StockState>(
  (ref) => StockController(ref),
);

class StockController extends StateNotifier<StockState> {
  static const _prefsKeyAId = 'dual_color_a_id';
  static const _prefsKeyAName = 'dual_color_a_name';
  static const _prefsKeyBId = 'dual_color_b_id';
  static const _prefsKeyBName = 'dual_color_b_name';
  static const _prefsKeyAutoReconnect = 'dual_color_auto_reconnect';

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  StreamSubscription<ConnectionStateUpdate>? _connA;
  StreamSubscription<ConnectionStateUpdate>? _connB;
  final Map<StockSide, Timer> _reconnectTimers = {};
  final Map<StockSide, Timer> _batteryTimers = {};
  final Map<StockSide, bool> _manualDisconnect = {
    StockSide.a: false,
    StockSide.b: false,
  };
  final Map<StockSide, DateTime> _lastConnectAttempt = {};
  final Map<StockSide, DateTime> _connectBackoffUntil = {};
  Future<void> _connectQueue = Future.value();

  static const Duration _connectCooldown = Duration(seconds: 2);
  static const Duration _connectGap = Duration(milliseconds: 600);
  static const Duration _postConnectDelay = Duration(milliseconds: 800);
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _startupSequenceStep = Duration(milliseconds: 200);
  static const List<Color> _startupSequenceColors = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFF8000),
    Color(0xFFFFFF00),
    Color(0xFF00FFFF),
    Color(0xFF0080FF),
  ];

  StockController(this._ref) : super(StockState.initial());

  BleClient get _client => _ref.read(bleClientProvider);
  bool get _isActive => mounted;

  Future<void> ensureLoaded() async {
    if (!_isActive) {
      return;
    }
    if (state.loaded) {
      return;
    }
    await _loadStored();
  }

  Future<bool> autoConnectStored({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await ensureLoaded();
    if (!_isActive) {
      return false;
    }
    if (!state.registered) {
      return false;
    }
    await connectBoth();
    if (!_isActive) {
      return false;
    }
    final connected = await _waitForConnections(timeout);
    if (!_isActive) {
      return false;
    }
    if (!connected) {
      await disconnectBoth();
      _setMessage(
        'Offline mode: ScepTRONIC UI remains available without connection.',
      );
    }
    return connected;
  }

  Future<void> setAutoReconnect(bool enabled) async {
    _setStateSafely(state.copyWith(autoReconnect: enabled));
    if (!enabled) {
      _reconnectTimers.remove(StockSide.a)?.cancel();
      _reconnectTimers.remove(StockSide.b)?.cancel();
    }
    final store = await LocalStore.instance();
    if (!_isActive) {
      return;
    }
    await store.setBool(_prefsKeyAutoReconnect, enabled);
  }

  Future<void> selectDevice(StockSide side, BleDevice device) async {
    if (!_isActive) {
      return;
    }
    final current = _sideState(side).device;
    final changedDevice = current == null || current.id != device.id;
    if (current != null && current.id != device.id) {
      await disconnect(side);
      if (!_isActive) {
        return;
      }
    }
    final info = DeviceNameInfo.fromName(device.name);
    _setSideState(
      side,
      StockSideState(
        device: device,
        status: DeviceConnectionState.disconnected,
        pairNumber: info.pairNumber,
        role: info.role,
        resyncStatus: ResyncStatus.idle,
      ),
    );
    if (changedDevice) {
      _ref.read(ledUiProvider.notifier).clearBatteryTelemetry(side);
    }
    await _persistSide(side);
  }

  Future<void> clearDevice(StockSide side) async {
    if (!_isActive) {
      return;
    }
    await disconnect(side);
    if (!_isActive) {
      return;
    }
    _setSideState(side, const StockSideState());
    _ref.read(ledUiProvider.notifier).clearBatteryTelemetry(side);
    await _removeSide(side);
  }

  Future<void> connect(StockSide side) async {
    if (!_isActive) {
      return;
    }
    await _runConnectSerial(() async {
      if (!_isActive) {
        return;
      }
      final granted = await _ensurePermissions();
      if (!_isActive) {
        return;
      }
      if (!granted) {
        _setMessage('BLE permissions not granted');
        return;
      }
      final sideState = _sideState(side);
      final device = sideState.device;
      if (device == null) {
        _setMessage('Select ${side.name.toUpperCase()} first.');
        return;
      }
      if (sideState.status == DeviceConnectionState.connected ||
          sideState.status == DeviceConnectionState.connecting) {
        return;
      }
      if (state.hasPairMismatch) {
        _setMessage(
          'N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}',
        );
        return;
      }
      if (side == StockSide.a && state.roleMismatchA) {
        _setMessage('Device number indicates role B. Assign an A device.');
        return;
      }
      if (side == StockSide.b && state.roleMismatchB) {
        _setMessage('Device number indicates role A. Assign a B device.');
        return;
      }

      await _applyConnectDelay(side);
      if (!_isActive) {
        return;
      }
      await _cancelConnection(side);
      if (!_isActive) {
        return;
      }
      _manualDisconnect[side] = false;
      _setSideState(
        side,
        sideState.copyWith(
          status: DeviceConnectionState.connecting,
          message: null,
          resyncStatus: ResyncStatus.idle,
          resyncNote: null,
        ),
      );

      final subscription = _client.connect(device.id).listen(
        (update) {
          if (!_isActive) {
            return;
          }
          _log.i(
            'stock ${side.name.toUpperCase()} ${device.id} -> ${update.connectionState.name}',
          );
          _setSideState(
            side,
            _sideState(side).copyWith(status: update.connectionState),
          );
          if (update.connectionState == DeviceConnectionState.connected) {
            _reconnectTimers.remove(side)?.cancel();
            _ref.read(ledUiProvider.notifier).armBatteryTrendReset(side);
            unawaited(_handlePostConnect(side, device.id));
          } else if (update.connectionState ==
              DeviceConnectionState.disconnected) {
            _stopBatteryPolling(side);
            _setResyncStatus(side, ResyncStatus.idle);
            _scheduleReconnect(side);
          }
        },
        onError: (e, st) {
          if (!_isActive) {
            return;
          }
          _log.e('connect error', error: e, stackTrace: st);
          _stopBatteryPolling(side);
          _setSideState(
            side,
            _sideState(side).copyWith(
              status: DeviceConnectionState.disconnected,
              message: e.toString(),
            ),
          );
          _scheduleReconnect(side);
        },
      );
      _setConnection(side, subscription);
    });
  }

  Future<void> connectBoth() async {
    if (state.a.device == null || state.b.device == null) {
      _setMessage('Select both A and B devices before connecting.');
      return;
    }
    if (state.hasPairMismatch) {
      _setMessage(
        'N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}',
      );
      return;
    }
    if (state.roleMismatchA || state.roleMismatchB) {
      _setMessage('Device roles do not match A/B assignment rules.');
      return;
    }
    await connect(StockSide.a);
    await connect(StockSide.b);
  }

  Future<void> disconnect(StockSide side) async {
    if (!_isActive) {
      return;
    }
    _manualDisconnect[side] = true;
    _reconnectTimers.remove(side)?.cancel();
    _stopBatteryPolling(side);
    await _ref
        .read(heartbeatControllerProvider)
        .stop(side, sendOff: false, resetMode: false);
    if (!_isActive) {
      return;
    }
    await _cancelConnection(side);
    if (!_isActive) {
      return;
    }
    _setSideState(
      side,
      _sideState(side).copyWith(
        status: DeviceConnectionState.disconnected,
        resyncStatus: ResyncStatus.idle,
        resyncNote: null,
      ),
    );
  }

  Future<void> disconnectBoth() async {
    await disconnect(StockSide.a);
    await disconnect(StockSide.b);
  }

  Future<bool> waitForBothConnected(Duration timeout) {
    return _waitForConnections(timeout);
  }

  Future<bool> waitForBothDisconnected(Duration timeout) {
    return _waitForDisconnections(timeout);
  }

  Future<double?> readBattery(StockSide side) {
    // Keep battery polling behind the explicit BLE connect flow so the UI
    // status does not stay DISCONNECTED while GATT traffic is already active.
    if (_sideState(side).status != DeviceConnectionState.connected) {
      return Future<double?>.value(null);
    }
    return _readBatteryOnce(side);
  }

  Future<void> readBatteryAll() async {
    await readBattery(StockSide.a);
    await readBattery(StockSide.b);
  }

  Future<String?> verifyGattProfile(
    StockSide side, {
    bool requireBatteryCharacteristic = true,
    bool requireAckCharacteristic = false,
  }) async {
    final device = _sideState(side).device;
    if (device == null) {
      return 'Device ${side.name.toUpperCase()} not assigned';
    }
    try {
      final services = await _client.discoverServices(device.id);
      final serviceMap = <String, Set<String>>{};
      for (final service in services) {
        serviceMap[service.serviceId.toString().toLowerCase()] =
            service.characteristics
                .map(
                  (characteristic) =>
                      characteristic.characteristicId.toString().toLowerCase(),
                )
                .toSet();
      }

      final advChars = serviceMap[Env.advServiceUuid.toLowerCase()];
      if (advChars == null) {
        return 'Missing ADV service on ${side.name.toUpperCase()}';
      }
      if (!advChars.contains(Env.advCharUuid.toLowerCase())) {
        return 'Missing ADV command characteristic on ${side.name.toUpperCase()}';
      }
      if (requireBatteryCharacteristic &&
          !advChars.contains(Env.voltageCharUuid.toLowerCase())) {
        return 'Missing voltage characteristic on ${side.name.toUpperCase()}';
      }
      if (requireAckCharacteristic &&
          !advChars.contains(Env.ackCharUuid.toLowerCase())) {
        return 'Missing ACK characteristic on ${side.name.toUpperCase()}';
      }
      return null;
    } catch (e, st) {
      _log.w('gatt profile verify failed', error: e, stackTrace: st);
      return e.toString();
    }
  }

  @override
  void dispose() {
    _reconnectTimers.remove(StockSide.a)?.cancel();
    _reconnectTimers.remove(StockSide.b)?.cancel();
    _stopBatteryPolling(StockSide.a);
    _stopBatteryPolling(StockSide.b);
    unawaited(_cancelConnection(StockSide.a));
    unawaited(_cancelConnection(StockSide.b));
    super.dispose();
  }

  StockSideState _sideState(StockSide side) {
    return side == StockSide.a ? state.a : state.b;
  }

  void _setStateSafely(StockState next) {
    if (!_isActive) {
      return;
    }
    state = next;
  }

  void _setSideState(StockSide side, StockSideState next) {
    if (!_isActive) {
      return;
    }
    if (side == StockSide.a) {
      state = state.copyWith(a: next, message: null);
    } else {
      state = state.copyWith(b: next, message: null);
    }
  }

  void _setResyncStatus(StockSide side, ResyncStatus status, {String? note}) {
    final clipped =
        note != null && note.length > 40 ? note.substring(0, 40) : note;
    _setSideState(
      side,
      _sideState(side).copyWith(resyncStatus: status, resyncNote: clipped),
    );
  }

  Future<void> _handlePostConnect(StockSide side, String deviceId) async {
    await Future<void>.delayed(_postConnectDelay);
    if (!_isActive) {
      return;
    }
    if (_sideState(side).status != DeviceConnectionState.connected) {
      return;
    }
    if (!await _verifyConnectedGatt(side, deviceId)) {
      return;
    }
    if (!_isActive) {
      return;
    }
    await _ref.read(ledUiProvider.notifier).ensureLoaded();
    if (!_isActive) {
      return;
    }
    await _readBatteryOnce(side);
    if (!_isActive) {
      return;
    }
    _startBatteryPolling(side);
    await _runStartupSequenceOnConnect(side, deviceId);
    if (!_isActive) {
      return;
    }
    await _resyncAfterReconnect(side, deviceId);
  }

  Future<bool> _verifyConnectedGatt(StockSide side, String deviceId) async {
    final error = await verifyGattProfile(side);
    if (!_isActive) {
      return false;
    }
    if (error == null) {
      return true;
    }
    _log.w(
      'connect verify failed for ${side.name.toUpperCase()} $deviceId: $error',
    );
    _stopBatteryPolling(side);
    await _cancelConnection(side);
    _setSideState(
      side,
      _sideState(side).copyWith(
        status: DeviceConnectionState.disconnected,
        message: error,
        resyncStatus: ResyncStatus.failed,
        resyncNote: 'gatt',
      ),
    );
    _scheduleReconnect(side);
    return false;
  }

  Future<void> _resyncAfterReconnect(StockSide side, String deviceId) async {
    if (!_isActive) {
      return;
    }
    final sideUi = _ref.read(ledUiProvider).sideState(side);
    final led = _ref.read(ledControllerProvider);
    final heartbeat = _ref.read(heartbeatControllerProvider);

    if (!sideUi.outputEnabled) {
      _setResyncStatus(side, ResyncStatus.running, note: 'output off');
      try {
        await led.applyIdleState(deviceId);
      } catch (e, st) {
        _log.w('idle resync failed', error: e, stackTrace: st);
        _setResyncStatus(side, ResyncStatus.failed, note: 'idle');
        return;
      }
      if (!_isActive) {
        return;
      }
      _setResyncStatus(side, ResyncStatus.success, note: 'output off');
      return;
    }

    _setResyncStatus(side, ResyncStatus.running, note: 'resync...');
    try {
      await led.setOutputEnabled(deviceId, true);
      if (!_isActive) {
        return;
      }
      await led.setBrightness(deviceId, sideUi.brightness.round());
      if (!_isActive) {
        return;
      }

      if (sideUi.top.mode == LedMode.rainbow ||
          sideUi.bottom.mode == LedMode.rainbow) {
        await led.startRainbow(deviceId, intervalMs: sideUi.rainbowIntervalMs);
        if (!_isActive) {
          return;
        }
        _ref.read(ledUiProvider.notifier).setSegmentMode(
              side,
              ColorZone.both,
              LedMode.rainbow,
              persist: false,
            );
        _setResyncStatus(side, ResyncStatus.success, note: 'rainbow');
        return;
      }

      if (sideUi.top.mode == LedMode.heartbeat ||
          sideUi.bottom.mode == LedMode.heartbeat) {
        await heartbeat.start(
          side,
          deviceId,
          interval: Duration(milliseconds: sideUi.heartbeatIntervalMs),
          persistUiMode: false,
        );
        if (!_isActive) {
          return;
        }
        _setResyncStatus(side, ResyncStatus.success, note: 'heartbeat');
        return;
      }

      await led.setTopColor(
        deviceId: deviceId,
        side: side,
        color: sideUi.top.mode == LedMode.off ? Colors.black : sideUi.top.color,
      );
      await led.setBottomColor(
        deviceId: deviceId,
        side: side,
        color: sideUi.bottom.mode == LedMode.off
            ? Colors.black
            : sideUi.bottom.color,
      );
      if (!_isActive) {
        return;
      }
      _setResyncStatus(side, ResyncStatus.success, note: 'colors');
    } catch (e, st) {
      _log.w('resync failed', error: e, stackTrace: st);
      _setResyncStatus(side, ResyncStatus.failed, note: e.toString());
    }
  }

  Future<void> _runStartupSequenceOnConnect(
    StockSide side,
    String deviceId,
  ) async {
    if (!_isActive || !_ref.read(productStartupSequenceEnabledProvider)) {
      return;
    }
    if (!_isConnectionCurrent(side, deviceId)) {
      return;
    }

    final led = _ref.read(ledControllerProvider);
    final heartbeat = _ref.read(heartbeatControllerProvider);
    final sideUi = _ref.read(ledUiProvider).sideState(side);

    _setResyncStatus(side, ResyncStatus.running, note: 'startup...');
    try {
      await heartbeat.stop(
        side,
        deviceId: deviceId,
        sendOff: false,
        resetMode: false,
        persistUiMode: false,
      );
      if (!_isConnectionCurrent(side, deviceId)) {
        return;
      }
      try {
        await led.stopRainbow(deviceId);
      } catch (e, st) {
        _log.w('startup rainbow stop failed', error: e, stackTrace: st);
      }
      if (!_isConnectionCurrent(side, deviceId)) {
        return;
      }

      await led.setOutputEnabled(deviceId, true);
      await led.setBrightness(deviceId, sideUi.brightness.round());

      for (final color in _startupSequenceColors) {
        if (!_isConnectionCurrent(side, deviceId)) {
          return;
        }
        await led.setTopColor(deviceId: deviceId, side: side, color: color);
        await led.setBottomColor(deviceId: deviceId, side: side, color: color);
        if (!_isConnectionCurrent(side, deviceId)) {
          return;
        }
        await Future<void>.delayed(_startupSequenceStep);
      }
    } catch (e, st) {
      _log.w('startup sequence failed', error: e, stackTrace: st);
    }
  }

  bool _isConnectionCurrent(StockSide side, String deviceId) {
    if (!_isActive) {
      return false;
    }
    final sideState = _sideState(side);
    return sideState.status == DeviceConnectionState.connected &&
        sideState.device?.id == deviceId;
  }

  void _scheduleReconnect(StockSide side) {
    if (!_isActive) {
      return;
    }
    if (!state.autoReconnect) {
      return;
    }
    if (_manualDisconnect[side] == true) {
      return;
    }
    final device = _sideState(side).device;
    if (device == null) {
      return;
    }
    _reconnectTimers.remove(side)?.cancel();
    _reconnectTimers[side] = Timer(_reconnectDelay, () {
      if (!_isActive) {
        return;
      }
      if (_sideState(side).status == DeviceConnectionState.disconnected) {
        unawaited(connect(side));
      }
    });
  }

  Future<void> _runConnectSerial(Future<void> Function() task) {
    final next = _connectQueue.then((_) => task());
    _connectQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _applyConnectDelay(StockSide side) async {
    final now = DateTime.now();
    final backoffUntil = _connectBackoffUntil[side];
    if (backoffUntil != null && now.isBefore(backoffUntil)) {
      await Future<void>.delayed(backoffUntil.difference(now));
    }
    final last = _lastConnectAttempt[side];
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _connectCooldown) {
        await Future<void>.delayed(_connectCooldown - elapsed);
      }
    }
    _lastConnectAttempt[side] = DateTime.now();
    await Future<void>.delayed(_connectGap);
  }

  Future<void> _cancelConnection(StockSide side) async {
    if (side == StockSide.a) {
      await _connA?.cancel();
      _connA = null;
    } else {
      await _connB?.cancel();
      _connB = null;
    }
  }

  void _setConnection(
    StockSide side,
    StreamSubscription<ConnectionStateUpdate> sub,
  ) {
    if (side == StockSide.a) {
      _connA = sub;
    } else {
      _connB = sub;
    }
  }

  void _startBatteryPolling(StockSide side) {
    _batteryTimers.remove(side)?.cancel();
    _batteryTimers[side] = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (!_isActive) {
          return;
        }
        unawaited(_readBatteryOnce(side));
      },
    );
  }

  void _stopBatteryPolling(StockSide side) {
    _batteryTimers.remove(side)?.cancel();
  }

  Future<double?> _readBatteryOnce(StockSide side) async {
    if (!_isActive) {
      return null;
    }
    final device = _sideState(side).device;
    if (device == null) {
      return null;
    }
    try {
      final data = await _client.readCharacteristic(
        deviceId: device.id,
        serviceUuid: Env.advServiceUuid,
        charUuid: Env.voltageCharUuid,
      );
      if (!_isActive) {
        return null;
      }
      if (data.isEmpty) {
        return null;
      }
      final telemetry = _parseBatteryTelemetry(data);
      final percent = _voltageToPercent(telemetry.voltage);
      _ref.read(ledUiProvider.notifier).setBatteryVoltage(
            side,
            telemetry.voltage,
            percent,
            charging: telemetry.charging,
          );
      return telemetry.voltage;
    } catch (e, st) {
      _log.w('battery read failed', error: e, stackTrace: st);
      return null;
    }
  }

  ({double voltage, bool charging}) _parseBatteryTelemetry(List<int> raw) {
    return (
      voltage: _parseVoltage(raw),
      charging: _parseCharging(raw),
    );
  }

  double _parseVoltage(List<int> raw) {
    if (raw.isEmpty) {
      return 0;
    }
    if (raw.length >= 4) {
      final mv = (raw[2] & 0xFF) | ((raw[3] & 0xFF) << 8);
      if (mv >= 500 && mv <= 7000) {
        return mv / 1000.0;
      }
      final rawAdc = (raw[0] & 0xFF) | ((raw[1] & 0xFF) << 8);
      if (rawAdc > 0 && rawAdc < 4096) {
        return (rawAdc / 1000.0).clamp(0.0, 5.5);
      }
    }
    final ascii = raw.every((b) => b >= 0x20 && b <= 0x7E);
    if (ascii) {
      final text = String.fromCharCodes(raw).trim();
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null) {
          return value;
        }
      }
    }
    int value = 0;
    for (int i = 0; i < raw.length && i < 4; i++) {
      value |= (raw[i] & 0xFF) << (8 * i);
    }
    if (value > 1000) {
      return value / 1000.0;
    }
    if (value > 100) {
      return value / 100.0;
    }
    return value.toDouble();
  }

  bool _parseCharging(List<int> raw) {
    if (!_looksLikeBinaryVoltagePayload(raw) || raw.length < 5) {
      return false;
    }
    return (raw[4] & 0x01) != 0;
  }

  bool _looksLikeBinaryVoltagePayload(List<int> raw) {
    if (raw.length < 4) {
      return false;
    }
    final mv = (raw[2] & 0xFF) | ((raw[3] & 0xFF) << 8);
    if (mv >= 500 && mv <= 7000) {
      return true;
    }
    final rawAdc = (raw[0] & 0xFF) | ((raw[1] & 0xFF) << 8);
    return rawAdc > 0 && rawAdc < 4096;
  }

  double _voltageToPercent(double voltage) {
    if (voltage <= 0) {
      return 0;
    }
    final clamped = voltage.clamp(Env.batteryMinV, Env.batteryMaxV);
    return (clamped - Env.batteryMinV) / (Env.batteryMaxV - Env.batteryMinV);
  }

  Future<void> _loadStored() async {
    try {
      final store = await LocalStore.instance();
      if (!_isActive) {
        return;
      }
      final autoReconnect = store.getBool(_prefsKeyAutoReconnect);
      final aId = store.getString(_prefsKeyAId);
      final aName = store.getString(_prefsKeyAName);
      final bId = store.getString(_prefsKeyBId);
      final bName = store.getString(_prefsKeyBName);

      if (aId != null && aId.isNotEmpty) {
        final info = DeviceNameInfo.fromName(aName);
        _setSideState(
          StockSide.a,
          StockSideState(
            device: BleDevice(id: aId, name: aName),
            pairNumber: info.pairNumber,
            role: info.role,
          ),
        );
      }
      if (bId != null && bId.isNotEmpty) {
        final info = DeviceNameInfo.fromName(bName);
        _setSideState(
          StockSide.b,
          StockSideState(
            device: BleDevice(id: bId, name: bName),
            pairNumber: info.pairNumber,
            role: info.role,
          ),
        );
      }
      _setStateSafely(state.copyWith(
        loaded: true,
        autoReconnect: autoReconnect ?? true,
      ));
    } catch (e, st) {
      _log.e('load stored devices failed', error: e, stackTrace: st);
      _setStateSafely(state.copyWith(loaded: true));
    }
  }

  Future<void> _persistSide(StockSide side) async {
    final store = await LocalStore.instance();
    if (!_isActive) {
      return;
    }
    final device = _sideState(side).device;
    if (device == null) {
      await _removeSide(side);
      return;
    }
    if (side == StockSide.a) {
      await store.setString(_prefsKeyAId, device.id);
      if (device.name != null && device.name!.isNotEmpty) {
        await store.setString(_prefsKeyAName, device.name!);
      } else {
        await store.remove(_prefsKeyAName);
      }
    } else {
      await store.setString(_prefsKeyBId, device.id);
      if (device.name != null && device.name!.isNotEmpty) {
        await store.setString(_prefsKeyBName, device.name!);
      } else {
        await store.remove(_prefsKeyBName);
      }
    }
  }

  Future<void> _removeSide(StockSide side) async {
    final store = await LocalStore.instance();
    if (!_isActive) {
      return;
    }
    if (side == StockSide.a) {
      await store.remove(_prefsKeyAId);
      await store.remove(_prefsKeyAName);
    } else {
      await store.remove(_prefsKeyBId);
      await store.remove(_prefsKeyBName);
    }
  }

  void _setMessage(String message) {
    _setStateSafely(state.copyWith(message: message));
  }

  Future<bool> _waitForConnections(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_isActive) {
        return false;
      }
      if (state.a.status == DeviceConnectionState.connected &&
          state.b.status == DeviceConnectionState.connected) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> _waitForDisconnections(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_isActive) {
        return false;
      }
      if (state.a.status == DeviceConnectionState.disconnected &&
          state.b.status == DeviceConnectionState.disconnected) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> _ensurePermissions() async {
    return ensureBlePermissions(_log);
  }
}
