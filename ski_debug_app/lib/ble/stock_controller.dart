import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_client.dart';
import 'env.dart';
import 'heartbeat_controller.dart';
import 'package:ski_debug_app/ble/led_controller.dart';
import 'led_ui_state.dart';
import 'models.dart';

enum ResyncStatus { idle, running, success, failed }

class StockSideState {
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
    String? message,
    ResyncStatus? resyncStatus,
    String? resyncNote,
  }) {
    return StockSideState(
      device: device ?? this.device,
      status: status ?? this.status,
      pairNumber: pairNumber ?? this.pairNumber,
      role: role ?? this.role,
      message: message,
      resyncStatus: resyncStatus ?? this.resyncStatus,
      resyncNote: resyncNote ?? this.resyncNote,
    );
  }
}

class StockState {
  final StockSideState a;
  final StockSideState b;
  final bool loaded;
  final bool registered;
  final bool connecting;
  final String? message;

  const StockState({
    required this.a,
    required this.b,
    this.loaded = false,
    this.registered = false,
    this.connecting = false,
    this.message,
  });

  factory StockState.initial() {
    return const StockState(a: StockSideState(), b: StockSideState());
  }

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
    bool? registered,
    bool? connecting,
    String? message,
  }) {
    return StockState(
      a: a ?? this.a,
      b: b ?? this.b,
      loaded: loaded ?? this.loaded,
      registered: registered ?? this.registered,
      connecting: connecting ?? this.connecting,
      message: message,
    );
  }
}

final stockProvider =
    StateNotifierProvider<StockController, StockState>(
  (ref) => StockController(ref),
);

class StockController extends StateNotifier<StockState> {
  static const _prefsKeyAId = 'ski_stock_a_id';
  static const _prefsKeyAName = 'ski_stock_a_name';
  static const _prefsKeyBId = 'ski_stock_b_id';
  static const _prefsKeyBName = 'ski_stock_b_name';

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  StreamSubscription<ConnectionStateUpdate>? _connA;
  StreamSubscription<ConnectionStateUpdate>? _connB;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  bool _loading = false;
  final Map<StockSide, Timer> _batteryTimers = {};
  final Map<StockSide, Timer> _reconnectTimers = {};
  final Map<StockSide, bool> _manualDisconnect = {
    StockSide.a: false,
    StockSide.b: false,
  };
  bool _settingsRoundTripPending = false;
  bool _scanConnectBusy = false;
  Future<void> _connectQueue = Future.value();
  final Map<StockSide, DateTime> _lastConnectAttempt = {};
  final Map<StockSide, DateTime> _connectBackoffUntil = {};
  static const Duration _connectCooldown = Duration(seconds: 3);
  static const Duration _connectGap = Duration(milliseconds: 600);
  static const Duration _postConnectDelay = Duration(milliseconds: 800);
  static const Duration _authBackoff = Duration(seconds: 3);
  final Map<StockSide, StreamSubscription<List<int>>> _voltageNotifySubs = {};
  static const Duration _reconnectDelay = Duration(seconds: 2);

  StockController(this._ref) : super(StockState.initial());

  BleClient get _client => _ref.read(bleClientProvider);

  Future<void> ensureLoaded() async {
    if (state.loaded || _loading) {
      return;
    }
    _loading = true;
    await _loadStored();
    _loading = false;
  }

  Future<void> scanAndConnect() async {
    if (_scanConnectBusy) {
      _setMessage('Scan/connect already running.');
      return;
    }
    _scanConnectBusy = true;
    try {
      final granted = await _ensurePermissions();
      if (!granted) {
        _setMessage('BLE permissions not granted');
        return;
      }
      state = state.copyWith(connecting: true, message: null);
      await ensureLoaded();

      // Prefer registered IDs first. Some Android builds do not always expose
      // stable advertisement names during scan, but direct reconnect can still work.
      if (state.registered && state.a.device != null && state.b.device != null) {
        await connectBoth();
        final connected = await _waitForConnections(const Duration(seconds: 8));
        if (connected) {
          state = state.copyWith(connecting: false, message: null);
          return;
        }
      }

      final pair = await _scanForPair();
      if (pair == null) {
        state = state.copyWith(connecting: false);
        _setMessage('No A/B pair found');
        return;
      }
      _setSideFromDevice(StockSide.a, pair.item1);
      _setSideFromDevice(StockSide.b, pair.item2);
      await connectBoth();
      state = state.copyWith(connecting: false);
    } finally {
      _scanConnectBusy = false;
    }
  }

  Future<void> connect(StockSide side) async {
    return _runConnectSerial(() async {
    final granted = await _ensurePermissions();
    if (!granted) {
      _setMessage('BLE permissions not granted');
      return;
    }
    final sideState = _sideState(side);
    final device = sideState.device;
    if (device == null) {
      _setMessage('Select a device first.');
      return;
    }
    if (sideState.status == DeviceConnectionState.connected ||
        sideState.status == DeviceConnectionState.connecting) {
      return;
    }
    if (state.hasPairMismatch) {
      _setMessage('N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}');
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
    await _cancelConnection(side, reason: 'pre_connect_reset');
    _manualDisconnect[side] = false;
    _setSideState(
      side,
      sideState.copyWith(
        status: DeviceConnectionState.connecting,
        message: null,
      ),
    );

    final subscription = _client.connect(device.id).listen(
      (u) async {
        _logConnectionState(side, u);
        final updated = _sideState(side).copyWith(status: u.connectionState);
        _setSideState(side, updated);
        if (u.connectionState == DeviceConnectionState.connected) {
          _reconnectTimers.remove(side)?.cancel();
          unawaited(_handlePostConnect(side, device.id));
        } else if (u.connectionState == DeviceConnectionState.disconnected) {
          _stopBatteryPolling(side);
          _voltageNotifySubs.remove(side)?.cancel();
          _setResyncStatus(side, ResyncStatus.idle);
          _scheduleReconnect(side);
        }
      },
      onError: (e, st) {
        _logConnectionError(side, device.id, e);
        _log.e('connect error', error: e, stackTrace: st);
        final text = e.toString();
        if (_looksLikeAuthBusyError(text)) {
          _connectBackoffUntil[side] = DateTime.now().add(_authBackoff);
          _setMessage('Auth/bond busy on ${side.name.toUpperCase()} (retrying)');
          _scheduleReconnect(side);
        }
        _setSideState(
          side,
          _sideState(side).copyWith(
            status: DeviceConnectionState.disconnected,
            message: text,
          ),
        );
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
      _setMessage('N mismatch: A=${state.a.pairNumber}, B=${state.b.pairNumber}');
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
    _manualDisconnect[side] = true;
    _reconnectTimers.remove(side)?.cancel();
    await _cancelConnection(side, reason: 'manual_disconnect');
    _setSideState(
      side,
      _sideState(side).copyWith(status: DeviceConnectionState.disconnected),
    );
    _stopBatteryPolling(side);
    _setResyncStatus(side, ResyncStatus.idle);
    _voltageNotifySubs.remove(side)?.cancel();
  }

  Future<void> disconnectBoth() async {
    await disconnect(StockSide.a);
    await disconnect(StockSide.b);
  }

  void _scheduleReconnect(StockSide side) {
    if (!state.registered) {
      return;
    }
    if (_scanConnectBusy) {
      return;
    }
    if (_manualDisconnect[side] == true) {
      return;
    }
    _reconnectTimers.remove(side)?.cancel();
    _reconnectTimers[side] = Timer(_reconnectDelay, () {
      if (_sideState(side).status == DeviceConnectionState.disconnected) {
        unawaited(connect(side));
      }
    });
  }

  Future<void> _handlePostConnect(StockSide side, String deviceId) async {
    await Future<void>.delayed(_postConnectDelay);
    final current = _sideState(side);
    if (current.status != DeviceConnectionState.connected) {
      return;
    }
    _startBatteryPolling(side);
    _subscribeVoltage(side);
    await _readBatteryOnce(side);
    await _resyncAfterReconnect(side);
  }

  Future<void> _runConnectSerial(Future<void> Function() task) {
    final next = _connectQueue.then((_) => task());
    _connectQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _applyConnectDelay(StockSide side) async {
    final now0 = DateTime.now();
    final backoffUntil = _connectBackoffUntil[side];
    if (backoffUntil != null && now0.isBefore(backoffUntil)) {
      await Future<void>.delayed(backoffUntil.difference(now0));
    }

    final last = _lastConnectAttempt[side];
    final now = DateTime.now();
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _connectCooldown) {
        await Future<void>.delayed(_connectCooldown - elapsed);
      }
    }
    _lastConnectAttempt[side] = DateTime.now();
    if (_connectGap > Duration.zero) {
      await Future<void>.delayed(_connectGap);
    }
  }

  bool _looksLikeAuthBusyError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('0x0016') ||
        lower.contains('status 22') ||
        lower.contains('reason:22') ||
        lower.contains('insuf') ||
        lower.contains('bond');
  }

  Future<void> registerDevices() async {
    if (state.a.device == null || state.b.device == null) {
      _setMessage('Select both A and B devices before registering.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAId, state.a.device!.id);
    if (state.a.device!.name != null) {
      await prefs.setString(_prefsKeyAName, state.a.device!.name!);
    }
    await prefs.setString(_prefsKeyBId, state.b.device!.id);
    if (state.b.device!.name != null) {
      await prefs.setString(_prefsKeyBName, state.b.device!.name!);
    }
    state = state.copyWith(registered: true);
  }

  Future<void> clearRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyAId);
    await prefs.remove(_prefsKeyAName);
    await prefs.remove(_prefsKeyBId);
    await prefs.remove(_prefsKeyBName);
    state = state.copyWith(registered: false);
  }

  Future<bool> autoConnectStored({Duration timeout = const Duration(seconds: 10)}) async {
    await ensureLoaded();
    if (!state.registered) {
      return false;
    }
    await connectBoth();
    final success = await _waitForConnections(timeout);
    return success;
  }

  void markSettingsRoundTripPending() {
    _settingsRoundTripPending = true;
    _emitAppBleLog('[BLE_SETTINGS] pending=true', error: false);
  }

  Future<void> handleAppResumed() async {
    if (!_settingsRoundTripPending) {
      return;
    }
    _settingsRoundTripPending = false;
    _emitAppBleLog('[BLE_SETTINGS] app_resumed=true', error: false);
    await _reconnectAfterSettingsReturn();
  }

  Future<void> _reconnectAfterSettingsReturn() async {
    await ensureLoaded();
    if (state.a.device == null || state.b.device == null) {
      _emitAppBleLog(
        '[BLE_SETTINGS] reconnect_skip=no_registered_pair',
        error: false,
      );
      return;
    }
    _emitAppBleLog('[BLE_SETTINGS] reconnect_start', error: false);
    await disconnectBoth();
    await Future<void>.delayed(const Duration(seconds: 1));
    await connectBoth();
    final ok = await _waitForConnections(const Duration(seconds: 12));
    _emitAppBleLog(
      '[BLE_SETTINGS] reconnect_result=${ok ? 'success' : 'timeout'}',
      error: !ok,
    );
    if (!ok) {
      _setMessage('Reconnect timeout after Bluetooth settings.');
    }
  }

  Future<void> selectDevice(StockSide side, BleDevice device) async {
    final info = DeviceNameInfo.fromName(device.name);
    _setSideState(
      side,
      _sideState(side).copyWith(
        device: device,
        pairNumber: info.pairNumber,
        role: info.role,
        message: null,
      ),
    );
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    unawaited(_cancelConnection(StockSide.a, reason: 'controller_dispose'));
    unawaited(_cancelConnection(StockSide.b, reason: 'controller_dispose'));
    _stopBatteryPolling(StockSide.a);
    _stopBatteryPolling(StockSide.b);
    super.dispose();
  }

  StockSideState _sideState(StockSide side) =>
      side == StockSide.a ? state.a : state.b;

  void _setSideState(StockSide side, StockSideState next) {
    if (side == StockSide.a) {
      state = state.copyWith(a: next, message: null);
    } else {
      state = state.copyWith(b: next, message: null);
    }
  }

  void _setResyncStatus(
    StockSide side,
    ResyncStatus status, {
    String? note,
  }) {
    String? trimmed = note;
    if (trimmed != null && trimmed.length > 40) {
      trimmed = trimmed.substring(0, 40);
    }
    final current = _sideState(side);
    _setSideState(
      side,
      current.copyWith(resyncStatus: status, resyncNote: trimmed),
    );
  }

  void _setSideFromDevice(StockSide side, BleDevice device) {
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
  }

  Future<void> _cancelConnection(
    StockSide side, {
    String reason = 'unknown',
  }) async {
    final hasConn = side == StockSide.a ? _connA != null : _connB != null;
    if (hasConn) {
      _logAppClose(side, reason);
    }
    if (side == StockSide.a) {
      await _connA?.cancel();
      _connA = null;
    } else {
      await _connB?.cancel();
      _connB = null;
    }
  }

  void _logAppClose(StockSide side, String reason) {
    final sideState = _sideState(side);
    final sideTag = side == StockSide.a ? 'A' : 'B';
    final id = sideState.device?.id ?? '';
    final name = sideState.device?.name ?? '';
    final message =
        '[BLE_APP_CLOSE] side=$sideTag id=$id name=$name reason=$reason';
    _emitAppBleLog(message, error: false);
  }

  void _logConnectionState(StockSide side, ConnectionStateUpdate update) {
    final sideTag = side == StockSide.a ? 'A' : 'B';
    final failure = update.failure?.toString() ?? '-';
    final message =
        '[BLE_CONN_STATE] side=$sideTag id=${update.deviceId} state=${update.connectionState.name} failure=$failure';
    _emitAppBleLog(message, error: false);
  }

  void _logConnectionError(StockSide side, String deviceId, Object error) {
    final sideTag = side == StockSide.a ? 'A' : 'B';
    final message =
        '[BLE_CONN_ERROR] side=$sideTag id=$deviceId error=${error.toString()}';
    _emitAppBleLog(message, error: true);
  }

  void _emitAppBleLog(String message, {required bool error}) {
    if (error) {
      _log.e(message);
    } else {
      _log.i(message);
    }
    // Emit to multiple sinks so logcat capture is stable across OS versions.
    debugPrint(message);
    // ignore: avoid_print
    print(message);
    dev.log(message, name: 'SKI_BLE');
  }

  void _startBatteryPolling(StockSide side) {
    _batteryTimers[side]?.cancel();
    _batteryTimers[side] = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _readBatteryOnce(side),
    );
  }

  void _stopBatteryPolling(StockSide side) {
    _batteryTimers.remove(side)?.cancel();
  }

  void _subscribeVoltage(StockSide side) {
    final device = _sideState(side).device;
    if (device == null) return;
    _voltageNotifySubs.remove(side)?.cancel();
    _voltageNotifySubs[side] = _client
        .subscribe(
          deviceId: device.id,
          serviceUuid: Env.advServiceUuid,
          charUuid: Env.voltageCharUuid,
        )
        .listen(
      (data) {
        if (data.isEmpty) return;
        final voltage = _parseVoltage(data);
        final percent = _voltageToPercent(voltage);
        _ref.read(ledUiProvider.notifier).setBatteryVoltage(
              side,
              voltage,
              percent,
            );
      },
      onError: (e, st) {
        _log.w('voltage notify failed', error: e, stackTrace: st);
      },
    );
  }

  Future<void> _resyncAfterReconnect(StockSide side) async {
    final device = _sideState(side).device;
    if (device == null) return;
    final uiState = _ref.read(ledUiProvider);
    final sideUi = side == StockSide.a ? uiState.a : uiState.b;
    final led = _ref.read(ledControllerProvider);
    final heartbeat = _ref.read(heartbeatControllerProvider);

    if (!sideUi.outputEnabled) {
      _setResyncStatus(side, ResyncStatus.idle, note: "output off");
      return;
    }
    _setResyncStatus(side, ResyncStatus.running, note: "resync...");
    try {
      await led.setOutputEnabled(device.id, true);
      await led.setBrightness(device.id, sideUi.brightness.round());

      if (sideUi.top.mode == LedMode.rainbow ||
          sideUi.bottom.mode == LedMode.rainbow) {
        await led.startRainbow(device.id, intervalMs: 40);
        _setResyncStatus(side, ResyncStatus.success, note: "rainbow");
        return;
      }
      if (sideUi.top.mode == LedMode.heartbeat ||
          sideUi.bottom.mode == LedMode.heartbeat) {
        heartbeat.start(side, device.id);
        _setResyncStatus(side, ResyncStatus.success, note: "heartbeat");
        return;
      }

      if (sideUi.top.mode == LedMode.color) {
        await led.setTopColor(
          deviceId: device.id,
          side: side,
          color: sideUi.top.color,
        );
      } else {
        await led.setTopColor(
          deviceId: device.id,
          side: side,
          color: const Color(0xFF000000),
        );
      }

      if (sideUi.bottom.mode == LedMode.color) {
        await led.setBottomColor(
          deviceId: device.id,
          side: side,
          color: sideUi.bottom.color,
        );
      } else {
        await led.setBottomColor(
          deviceId: device.id,
          side: side,
          color: const Color(0xFF000000),
        );
      }
      _setResyncStatus(side, ResyncStatus.success, note: "colors");
    } catch (e, st) {
      _log.w('resync failed', error: e, stackTrace: st);
      _setResyncStatus(side, ResyncStatus.failed, note: e.toString());
    }
  }

  Future<void> _readBatteryOnce(StockSide side) async {
    final device = _sideState(side).device;
    if (device == null) return;
    try {
      final data = await _client.readCharacteristic(
        deviceId: device.id,
        serviceUuid: Env.advServiceUuid,
        charUuid: Env.voltageCharUuid,
      );
      if (data.isEmpty) return;
      final voltage = _parseVoltage(data);
      final percent = _voltageToPercent(voltage);
      _ref.read(ledUiProvider.notifier).setBatteryVoltage(
            side,
            voltage,
            percent,
          );
    } catch (e, st) {
      _log.w('battery read failed', error: e, stackTrace: st);
    }
  }

  double _parseVoltage(List<int> raw) {
    if (raw.isEmpty) return 0.0;
    if (raw.length >= 4) {
      final rawAdc = (raw[0] & 0xFF) | ((raw[1] & 0xFF) << 8);
      final mv = (raw[2] & 0xFF) | ((raw[3] & 0xFF) << 8);
      if (mv >= 500 && mv <= 7000) {
        return _normalizeVoltage(mv / 1000.0);
      }
      if (rawAdc > 0 && rawAdc < 4096) {
        final approx = rawAdc / 1000.0;
        return _normalizeVoltage(approx);
      }
    }
    final ascii = raw.every((b) => b >= 0x20 && b <= 0x7E);
    if (ascii) {
      final text = String.fromCharCodes(raw).trim();
      final match = RegExp(r'([0-9]+(?:\\.[0-9]+)?)').firstMatch(text);
      if (match != null) {
        final parsed = double.tryParse(match.group(1)!);
        if (parsed != null) {
          return _normalizeVoltage(parsed);
        }
      }
    }
    int value = 0;
    for (int i = 0; i < raw.length && i < 4; i++) {
      value |= (raw[i] & 0xFF) << (8 * i);
    }
    double voltage;
    if (raw.length == 1) {
      voltage = value.toDouble();
    } else if (raw.length == 2 || raw.length == 4) {
      if (value > 1000) {
        voltage = value / 1000.0;
      } else {
        voltage = value / 100.0;
      }
    } else {
      voltage = value.toDouble();
    }
    return _normalizeVoltage(voltage);
  }

  double _voltageToPercent(double voltage) {
    if (voltage <= 0) return 0.0;
    final minV = Env.batteryMinV;
    final maxV = Env.batteryMaxV;
    if (maxV <= minV) return 0.0;
    final clamped = voltage.clamp(minV, maxV);
    return (clamped - minV) / (maxV - minV);
  }

  double _normalizeVoltage(double value) {
    double voltage = value;
    if (voltage > 20) {
      if (voltage > 100000) {
        voltage = voltage / 1000.0;
      }
      if (voltage > 1000) {
        voltage = voltage / 1000.0;
      }
      if (voltage > 20) {
        voltage = voltage / 100.0;
      }
    }
    return voltage;
  }

  void _setConnection(StockSide side, StreamSubscription<ConnectionStateUpdate> sub) {
    if (side == StockSide.a) {
      _connA = sub;
    } else {
      _connB = sub;
    }
  }

  void _setMessage(String message) {
    state = state.copyWith(message: message);
  }

  Future<void> _loadStored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final aId = prefs.getString(_prefsKeyAId);
      final aName = prefs.getString(_prefsKeyAName);
      final bId = prefs.getString(_prefsKeyBId);
      final bName = prefs.getString(_prefsKeyBName);

      if (aId != null && aId.isNotEmpty) {
        _setSideFromDevice(StockSide.a, BleDevice(id: aId, name: aName));
      }
      if (bId != null && bId.isNotEmpty) {
        _setSideFromDevice(StockSide.b, BleDevice(id: bId, name: bName));
      }
      final registered = aId != null &&
          aId.isNotEmpty &&
          bId != null &&
          bId.isNotEmpty;
      state = state.copyWith(loaded: true, registered: registered);
    } catch (e, st) {
      _log.e('load stored devices failed', error: e, stackTrace: st);
      state = state.copyWith(loaded: true);
    }
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await permissions.request();
    final granted =
        statuses.values.every((status) => status.isGranted || status.isLimited);
    if (!granted) {
      _log.w('BLE permission denied: $statuses');
    }
    return granted;
  }

  Future<_DevicePair?> _scanForPair() async {
    await _scanSub?.cancel();
    _scanSub = null;
    final aByN = <int, BleDevice>{};
    final bByN = <int, BleDevice>{};
    final seenIds = <String>{};
    final seenNames = <String>{};
    final completer = Completer<_DevicePair?>();

    _scanSub = _client.scan(nameHint: Env.nameHint).listen(
      (d) {
        final info = DeviceNameInfo.fromName(d.name);
        final key = '${d.id}|${d.name}';
        final firstSeen = seenIds.add(d.id) || seenNames.add(key);

        if (firstSeen) {
          final decision =
              info.pairNumber == null || info.role == null ? 'ignored' : 'candidate';
          unawaited(_appendScanParseCsv(
            deviceId: d.id,
            name: d.name,
            info: info,
            decision: decision,
          ));
        }

        if (info.pairNumber == null || info.role == null) {
          return;
        }
        final bleDevice = BleDevice(id: d.id, name: d.name);
        if (info.role == 'A') {
          aByN[info.pairNumber!] = bleDevice;
        } else {
          bByN[info.pairNumber!] = bleDevice;
        }
        for (final n in aByN.keys) {
          if (bByN.containsKey(n)) {
            unawaited(_appendScanParseCsv(
              deviceId: d.id,
              name: d.name,
              info: info,
              decision: 'pair_found_n$n',
            ));
            completer.complete(_DevicePair(aByN[n]!, bByN[n]!));
            break;
          }
        }
      },
      onError: (e, st) {
        _log.e('scan error', error: e, stackTrace: st);
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    final timer = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) {
        unawaited(_appendScanParseCsv(
          deviceId: '-',
          name: null,
          info: const DeviceNameInfo(),
          decision: 'scan_timeout_no_pair',
        ));
        completer.complete(null);
      }
    });

    final result = await completer.future;
    timer.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    return result;
  }

  Future<void> _appendScanParseCsv({
    required String deviceId,
    required String? name,
    required DeviceNameInfo info,
    required String decision,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/scan_parse_log.csv');
      final exists = await file.exists();
      if (!exists) {
        await file.writeAsString(
          'timestamp,device_id,name,device_number,pair_number,role,decision\n',
        );
      }
      final escapedName = _csvEscape(name ?? '');
      final row = [
        DateTime.now().toIso8601String(),
        _csvEscape(deviceId),
        escapedName,
        info.deviceNumber?.toString() ?? '',
        info.pairNumber?.toString() ?? '',
        info.role ?? '',
        _csvEscape(decision),
      ].join(',');
      await file.writeAsString('$row\n', mode: FileMode.append);
    } catch (e, st) {
      _log.w('scan parse csv write failed', error: e, stackTrace: st);
    }
  }

  String _csvEscape(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<bool> _waitForConnections(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final connectedA = state.a.status == DeviceConnectionState.connected;
      final connectedB = state.b.status == DeviceConnectionState.connected;
      if (connectedA && connectedB) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}

class _DevicePair {
  final BleDevice item1;
  final BleDevice item2;

  _DevicePair(this.item1, this.item2);
}
