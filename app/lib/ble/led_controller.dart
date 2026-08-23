import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;

import '../env.dart';
import 'ble_client.dart';
import 'models.dart';

final ledControllerProvider = Provider<LedController>((ref) {
  return LedController(ref.read(bleClientProvider));
});

const int _cmdSetBrightness = 0x01;
const int _cmdStartRainbow = 0x03;
const int _cmdStopRainbow = 0x04;
const int _cmdAccelMode = 0x06;
const int _cmdSetFrontColor = 0x07;
const int _cmdSetRearColor = 0x08;
const int _cmdSetOutputEnable = 0x09;
const int _cmdHeartbeatMode = 0x0A;

class LedController {
  final BleClient _client;
  final app_logger.Logger _log = app_logger.Logger();

  LedController(this._client);

  Future<void> writeLevel(String deviceId, int level) async {
    _log.i('write AlertLevel level=$level');
    await _client.writeByte(
      deviceId: deviceId,
      serviceUuid: Env.serviceUuid,
      charUuid: Env.alertLevelUuid,
      value: level,
    );
  }

  Future<void> setOutputEnabled(String deviceId, bool enable) async {
    _log.i('set output -> ${enable ? 'ON' : 'OFF'}');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [_cmdSetOutputEnable, enable ? 0x01 : 0x00],
    );
  }

  Future<void> setBrightness(String deviceId, int brightness) async {
    final value = brightness.clamp(0, 255);
    _log.i('set brightness -> $value');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [_cmdSetBrightness, value],
    );
  }

  Future<void> setFrontColor(String deviceId, int r, int g, int b) async {
    final rr = r.clamp(0, 255);
    final gg = g.clamp(0, 255);
    final bb = b.clamp(0, 255);
    _log.i('set front color -> ($rr, $gg, $bb)');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [_cmdSetFrontColor, rr, gg, bb],
    );
  }

  Future<void> setRearColor(String deviceId, int r, int g, int b) async {
    final rr = r.clamp(0, 255);
    final gg = g.clamp(0, 255);
    final bb = b.clamp(0, 255);
    _log.i('set rear color -> ($rr, $gg, $bb)');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [_cmdSetRearColor, rr, gg, bb],
    );
  }

  Future<void> setTopColor({
    required String deviceId,
    required StockSide side,
    required Color color,
  }) async {
    // ignore: deprecated_member_use
    await setFrontColor(deviceId, color.red, color.green, color.blue);
  }

  Future<void> setBottomColor({
    required String deviceId,
    required StockSide side,
    required Color color,
  }) async {
    // ignore: deprecated_member_use
    await setRearColor(deviceId, color.red, color.green, color.blue);
  }

  Future<void> startRainbow(String deviceId, {int intervalMs = 40}) async {
    final clamped = intervalMs.clamp(1, 65535);
    _log.i('start rainbow interval=$clamped');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [
        _cmdStartRainbow,
        clamped & 0xFF,
        (clamped >> 8) & 0xFF,
      ],
    );
  }

  Future<void> stopRainbow(String deviceId) async {
    _log.i('stop rainbow');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: const [_cmdStopRainbow],
    );
  }

  Future<void> setHeartbeatMode(
    String deviceId, {
    required bool enable,
    required int bpm,
    required int colorIndex,
  }) async {
    final clampedBpm = bpm.clamp(30, 255);
    final clampedColorIndex = colorIndex.clamp(0, 4);
    _log.i(
      'set heartbeat -> ${enable ? 'ON' : 'OFF'} bpm=$clampedBpm colorIndex=$clampedColorIndex',
    );
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [
        _cmdHeartbeatMode,
        enable ? 0x01 : 0x00,
        clampedBpm,
        clampedColorIndex,
      ],
    );
  }

  Future<void> stopHeartbeatMode(String deviceId) async {
    await setHeartbeatMode(
      deviceId,
      enable: false,
      bpm: 60,
      colorIndex: 0,
    );
  }

  Future<void> setAccelMode(String deviceId, bool enable) async {
    _log.i('set accel mode -> ${enable ? 'ON' : 'OFF'}');
    await _client.writePayload(
      deviceId: deviceId,
      serviceUuid: Env.advServiceUuid,
      charUuid: Env.advCharUuid,
      value: [_cmdAccelMode, enable ? 0x01 : 0x00],
    );
  }

  Future<void> applyIdleState(String deviceId) async {
    await _safeIdle('heartbeat off', () => stopHeartbeatMode(deviceId));
    await _safeIdle('output disable', () => setOutputEnabled(deviceId, false));
    await _safeIdle('rainbow stop', () => stopRainbow(deviceId));
    await _safeIdle('accel off', () => setAccelMode(deviceId, false));
    await _safeIdle('front off', () => setFrontColor(deviceId, 0, 0, 0));
    await _safeIdle('rear off', () => setRearColor(deviceId, 0, 0, 0));
  }

  Future<void> _safeIdle(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      _log.w('idle $label failed', error: e, stackTrace: st);
    }
  }
}
