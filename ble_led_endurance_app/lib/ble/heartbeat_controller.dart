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
  final Map<StockSide, Timer> _timers = {};
  final Map<StockSide, bool> _phase = {
    StockSide.a: false,
    StockSide.b: false,
  };

  HeartbeatController(this._ref);

  void start(
    StockSide side,
    String deviceId, {
    required Duration interval,
  }) {
    stop(side, deviceId: deviceId, sendOff: false, resetMode: false);
    _ref.read(ledUiProvider.notifier).setSegmentMode(
          side,
          ColorZone.both,
          LedMode.heartbeat,
        );
    _phase[side] = false;
    final tickMs = (interval.inMilliseconds / 2).round().clamp(150, 10000);
    _timers[side] = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      _tick(side, deviceId);
    });
    _log.i('heartbeat start $side ${tickMs * 2}ms');
  }

  void stop(
    StockSide side, {
    String? deviceId,
    bool sendOff = true,
    bool resetMode = true,
  }) {
    _timers.remove(side)?.cancel();
    _phase[side] = false;
    if (resetMode) {
      _ref.read(ledUiProvider.notifier).setSegmentMode(
            side,
            ColorZone.both,
            LedMode.off,
          );
    }
    if (sendOff && deviceId != null && deviceId.isNotEmpty) {
      final led = _ref.read(ledControllerProvider);
      unawaited(
        led.setTopColor(deviceId: deviceId, side: side, color: Colors.black),
      );
      unawaited(
        led.setBottomColor(deviceId: deviceId, side: side, color: Colors.black),
      );
    }
    _log.i('heartbeat stop $side');
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _tick(StockSide side, String deviceId) {
    if (deviceId.isEmpty) {
      return;
    }
    final sideUi = _ref.read(ledUiProvider).sideState(side);
    final nextOn = !(_phase[side] ?? false);
    _phase[side] = nextOn;
    final color = nextOn ? sideUi.heartbeatColor : Colors.black;
    final led = _ref.read(ledControllerProvider);
    unawaited(led.setTopColor(deviceId: deviceId, side: side, color: color));
    unawaited(led.setBottomColor(deviceId: deviceId, side: side, color: color));
  }
}
