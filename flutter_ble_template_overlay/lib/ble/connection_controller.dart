
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:logger/logger.dart';
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

final connectionProvider = StateNotifierProvider<ConnectionController, ConnectionStateModel>(
  (ref) => ConnectionController(ref.read),
);

class ConnectionController extends StateNotifier<ConnectionStateModel> {
  final Reader _read;
  final _log = Logger();
  StreamSubscription<ConnectionStateUpdate>? _conn;

  ConnectionController(this._read) : super(const ConnectionStateModel());

  BleClient get _client => _read(bleClientProvider);

  Future<void> connect(String deviceId) async {
    await _conn?.cancel();
    state = ConnectionStateModel(deviceId: deviceId, status: DeviceConnectionState.connecting);
    _conn = _client.connect(deviceId).listen((u) async {
      state = ConnectionStateModel(deviceId: deviceId, status: u.connectionState);
      if (u.connectionState == DeviceConnectionState.connected) {
        final services = await _client.discoverServices(deviceId);
        state = ConnectionStateModel(
          deviceId: deviceId,
          status: DeviceConnectionState.connected,
          services: services.map((s) => GattService(
            s.serviceId.toString(),
            s.characteristics.map((c) => GattCharacteristic(
              c.characteristicId.toString(),
              canRead: c.isReadable,
              canWrite: c.isWritableWithResponse || c.isWritableWithoutResponse,
              canNotify: c.isNotifiable,
              canIndicate: c.isIndicatable,
            )).toList(),
          )).toList(),
        );
      }
    }, onError: (e, st) {
      _log.e("connect error", e, st);
      state = ConnectionStateModel(deviceId: deviceId, status: DeviceConnectionState.disconnected, message: e.toString());
    });
  }

  Future<void> disconnect() async {
    await _conn?.cancel();
    _conn = null;
    state = const ConnectionStateModel();
  }

  @override
  void dispose() {
    _conn?.cancel();
    super.dispose();
  }
}
