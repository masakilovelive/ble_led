import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;

import 'ble_client.dart';
import 'models.dart';

class ConnectionStateModel {
  final String? deviceId;
  final DeviceConnectionState status;
  final List<GattService> services;
  final String? message;
  const ConnectionStateModel({
    this.deviceId,
    this.status = DeviceConnectionState.disconnected,
    this.services = const [],
    this.message,
  });
}

final connectionProvider =
    StateNotifierProvider<ConnectionController, ConnectionStateModel>(
  (ref) => ConnectionController(ref),
);

class ConnectionController extends StateNotifier<ConnectionStateModel> {
  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();
  StreamSubscription<ConnectionStateUpdate>? _conn;
  Timer? _reconnectTimer;
  bool _autoReconnect = false;
  bool _manualDisconnect = false;
  String? _registeredDeviceId;

  ConnectionController(this._ref) : super(const ConnectionStateModel());

  BleClient get _client => _ref.read(bleClientProvider);

  Future<void> connect(String deviceId, {bool autoReconnect = true}) async {
    await _conn?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _manualDisconnect = false;
    _autoReconnect = autoReconnect;
    _registeredDeviceId = deviceId;
    state = ConnectionStateModel(
        deviceId: deviceId, status: DeviceConnectionState.connecting);
    _conn = _client.connect(deviceId).listen((u) async {
      state =
          ConnectionStateModel(deviceId: deviceId, status: u.connectionState);
      if (u.connectionState == DeviceConnectionState.connected) {
        final services = await _client.discoverServices(deviceId);
        state = ConnectionStateModel(
          deviceId: deviceId,
          status: DeviceConnectionState.connected,
          services: services
              .map(
                (s) => GattService(
                  s.serviceId.toString(),
                  s.characteristics
                      .map(
                        (c) => GattCharacteristic(
                          uuid: c.characteristicId.toString(),
                          canRead: c.isReadable,
                          canWrite: c.isWritableWithResponse ||
                              c.isWritableWithoutResponse,
                          canNotify: c.isNotifiable,
                          canIndicate: c.isIndicatable,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        );
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        _scheduleReconnect();
      }
    }, onError: (e, st) {
      _log.e('connect error', error: e, stackTrace: st);
      state = ConnectionStateModel(
        deviceId: deviceId,
        status: DeviceConnectionState.disconnected,
        message: e.toString(),
      );
      _scheduleReconnect();
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _conn?.cancel();
    _conn = null;
    state = const ConnectionStateModel();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    final cancel = _conn?.cancel();
    if (cancel != null) {
      unawaited(cancel);
    }
    super.dispose();
  }

  void _scheduleReconnect() {
    if (!_autoReconnect || _manualDisconnect) {
      return;
    }
    final deviceId = _registeredDeviceId;
    if (deviceId == null) {
      return;
    }
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_manualDisconnect || !_autoReconnect) {
        return;
      }
      unawaited(connect(deviceId, autoReconnect: _autoReconnect));
    });
  }
}
