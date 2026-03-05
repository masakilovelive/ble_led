import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;

import 'ble_client.dart';
import 'env.dart';
import 'models.dart';

final ledControllerProvider = Provider<LedController>((ref) {
  return LedController(ref.read(bleClientProvider));
});

const int _cmdSetBrightness = 0x01;
const int _cmdStartRainbow = 0x03;
const int _cmdStopRainbow = 0x04;
const int _cmdSetFrontColor = 0x07;
const int _cmdSetRearColor = 0x08;
const int _cmdSetOutputEnable = 0x09;
const bool _swapTopBottomForB = true;

const int _protoMagic = 0xA5;
const int _protoVersion = 0x01;
const int _flagAckReq = 0x01;
const int _flagAck = 0x80;

const int _ackOk = 0x00;

class LedController {
  final BleClient _client;
  final app_logger.Logger _log = app_logger.Logger();
  final Map<String, int> _seq = {};
  final Map<String, Stream<List<int>>> _ackStreams = {};

  LedController(this._client);

  int _nextSeq(String deviceId) {
    final current = _seq[deviceId] ?? 0;
    final next = (current + 1) & 0xFF;
    _seq[deviceId] = next;
    return next;
  }

  int _crc8(List<int> data) {
    var crc = 0x00;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ 0x07) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
    }
    return crc & 0xFF;
  }

  Stream<List<int>> _ackStream(String deviceId) {
    return _ackStreams.putIfAbsent(
      deviceId,
      () => _client.subscribe(
        deviceId: deviceId,
        serviceUuid: Env.advServiceUuid,
        charUuid: Env.ackCharUuid,
      ),
    );
  }

  bool _isAckForSeq(List<int> data, int seq) {
    if (data.length < 6) return false;
    if (data[0] != _protoMagic) return false;
    if (data[1] != _protoVersion) return false;
    if (data[2] != seq) return false;
    if ((data[3] & _flagAck) == 0) return false;
    final crc = data.last;
    final calc = _crc8(data.sublist(0, data.length - 1));
    return crc == calc;
  }

  int _ackStatus(List<int> data) {
    if (data.length < 6) return 0xFF;
    return data[4];
  }

  Future<void> _sendCommand({
    required String deviceId,
    required int cmd,
    required List<int> payload,
    bool requireAck = true,
    int retries = 3,
    Duration ackTimeout = const Duration(milliseconds: 800),
    Duration retryBackoff = const Duration(milliseconds: 150),
  }) async {
    final seq = _nextSeq(deviceId);
    final flags = requireAck ? _flagAckReq : 0x00;
    final frame = <int>[_protoMagic, _protoVersion, seq, flags, cmd, ...payload];
    frame.add(_crc8(frame));

    final ackStream = _ackStream(deviceId);
    for (var attempt = 0; attempt <= retries; attempt++) {
      await _client.writePayload(
        deviceId: deviceId,
        serviceUuid: Env.advServiceUuid,
        charUuid: Env.advCharUuid,
        value: frame,
      );
      if (!requireAck) {
        return;
      }
      try {
        final ack = await ackStream
            .firstWhere((data) => _isAckForSeq(data, seq))
            .timeout(ackTimeout);
        final status = _ackStatus(ack);
        if (status == _ackOk) {
          return;
        }
        _log.w('ACK status $status for seq=$seq (attempt ${attempt + 1})');
      } on TimeoutException {
        _log.w('ACK timeout seq=$seq (attempt ${attempt + 1})');
      }
      if (attempt < retries) {
        await Future<void>.delayed(
          retryBackoff * (attempt + 1),
        );
      }
    }
    throw TimeoutException('ACK not received for cmd=0x${cmd.toRadixString(16)}');
  }

  Future<void> setOutputEnabled(String deviceId, bool enable) async {
    _log.i('set output -> ${enable ? 'ON' : 'OFF'}');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdSetOutputEnable,
      payload: [enable ? 0x01 : 0x00],
    );
  }

  Future<void> setBrightness(String deviceId, int brightness) async {
    final value = brightness.clamp(0, 255);
    _log.i('set brightness -> $value');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdSetBrightness,
      payload: [value],
    );
  }

  Future<void> setFrontColor(String deviceId, int r, int g, int b) async {
    final rr = r.clamp(0, 255);
    final gg = g.clamp(0, 255);
    final bb = b.clamp(0, 255);
    _log.i('set front color -> ($rr, $gg, $bb)');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdSetFrontColor,
      payload: [rr, gg, bb],
    );
  }

  Future<void> setRearColor(String deviceId, int r, int g, int b) async {
    final rr = r.clamp(0, 255);
    final gg = g.clamp(0, 255);
    final bb = b.clamp(0, 255);
    _log.i('set rear color -> ($rr, $gg, $bb)');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdSetRearColor,
      payload: [rr, gg, bb],
    );
  }

  Future<void> setTopColor({
    required String deviceId,
    required StockSide side,
    required Color color,
  }) async {
    if (_swapTopBottomForB && side == StockSide.b) {
      await setRearColor(deviceId, color.red, color.green, color.blue);
    } else {
      await setFrontColor(deviceId, color.red, color.green, color.blue);
    }
  }

  Future<void> setBottomColor({
    required String deviceId,
    required StockSide side,
    required Color color,
  }) async {
    if (_swapTopBottomForB && side == StockSide.b) {
      await setFrontColor(deviceId, color.red, color.green, color.blue);
    } else {
      await setRearColor(deviceId, color.red, color.green, color.blue);
    }
  }

  Future<void> startRainbow(String deviceId, {int intervalMs = 40}) async {
    final clamped = intervalMs.clamp(1, 65535);
    _log.i('start rainbow interval=$clamped');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdStartRainbow,
      payload: [clamped & 0xFF, (clamped >> 8) & 0xFF],
    );
  }

  Future<void> stopRainbow(String deviceId) async {
    _log.i('stop rainbow');
    await _sendCommand(
      deviceId: deviceId,
      cmd: _cmdStopRainbow,
      payload: const [],
    );
  }
}
