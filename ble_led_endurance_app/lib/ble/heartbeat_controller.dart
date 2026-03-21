import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;

import 'led_controller.dart';
import 'led_ui_state.dart';
import 'models.dart';

final heartbeatControllerProvider = Provider<HeartbeatController>((ref) {
  final controller = HeartbeatController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class HeartbeatController {
  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  HeartbeatController(this._ref);

  Future<void> start(
    StockSide side,
    String deviceId, {
    required Duration interval,
  }) async {
    final led = _ref.read(ledControllerProvider);
    final sideUi = _ref.read(ledUiProvider).sideState(side);
    final bpm = _intervalToBpm(interval.inMilliseconds);
    final colorIndex = _nearestHeartbeatColorIndex(sideUi.heartbeatColor);

    await stop(side, deviceId: deviceId, sendOff: false, resetMode: false);
    _ref.read(ledUiProvider.notifier).setSegmentMode(
          side,
          ColorZone.both,
          LedMode.heartbeat,
        );
    await led.setHeartbeatMode(
      deviceId,
      enable: true,
      bpm: bpm,
      colorIndex: colorIndex,
    );
    _log.i('heartbeat start $side ${interval.inMilliseconds}ms -> bpm=$bpm');
  }

  Future<void> stop(
    StockSide side, {
    String? deviceId,
    bool sendOff = true,
    bool resetMode = true,
  }) async {
    final led = _ref.read(ledControllerProvider);
    if (resetMode) {
      _ref.read(ledUiProvider.notifier).setSegmentMode(
            side,
            ColorZone.both,
            LedMode.off,
          );
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        await led.stopHeartbeatMode(deviceId);
      } catch (e, st) {
        _log.w('heartbeat stop mode failed', error: e, stackTrace: st);
      }
      if (sendOff) {
        try {
          await led.setTopColor(
            deviceId: deviceId,
            side: side,
            color: Colors.black,
          );
          await led.setBottomColor(
            deviceId: deviceId,
            side: side,
            color: Colors.black,
          );
        } catch (e, st) {
          _log.w('heartbeat stop color off failed', error: e, stackTrace: st);
        }
      }
    }
    _log.i('heartbeat stop $side');
  }

  void dispose() {}

  int _intervalToBpm(int intervalMs) {
    final clamped = intervalMs.clamp(250, 2000);
    return (60000 / clamped).round().clamp(30, 240);
  }

  int _nearestHeartbeatColorIndex(Color color) {
    final argb = color.toARGB32();
    final red = (argb >> 16) & 0xFF;
    final green = (argb >> 8) & 0xFF;
    final blue = argb & 0xFF;

    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _heartbeatPalette.length; i++) {
      final candidate = _heartbeatPalette[i];
      final distance = _colorDistanceSquared(red, green, blue, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}

double _colorDistanceSquared(int red, int green, int blue, Color candidate) {
  final argb = candidate.toARGB32();
  final dr = red - ((argb >> 16) & 0xFF);
  final dg = green - ((argb >> 8) & 0xFF);
  final db = blue - (argb & 0xFF);
  return (dr * dr + dg * dg + db * db).toDouble();
}

const List<Color> _heartbeatPalette = <Color>[
  Color(0xFFFF0000),
  Color(0xFF1976D2),
  Color(0xFF7B1FA2),
  Color(0xFFFFC107),
  Color(0xFF4CAF50),
];
