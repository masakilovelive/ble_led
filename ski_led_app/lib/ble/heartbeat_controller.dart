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
  final Map<StockSide, bool> _on = {
    StockSide.a: false,
    StockSide.b: false,
  };

  HeartbeatController(this._ref);

  void start(StockSide side, String deviceId) {
    stop(side, sendOff: false, resetMode: false);
    _ref.read(ledUiProvider.notifier).setBothMode(side, LedMode.heartbeat);
    _on[side] = false;
    _timers[side] = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _tick(side, deviceId);
    });
    _log.i('heartbeat start $side');
  }

  void stop(
    StockSide side, {
    String? deviceId,
    bool sendOff = true,
    bool resetMode = true,
  }) {
    _timers.remove(side)?.cancel();
    _on[side] = false;
    if (resetMode) {
      _ref.read(ledUiProvider.notifier).setBothMode(side, LedMode.off);
    }
    if (sendOff && deviceId != null && deviceId.isNotEmpty) {
      final led = _ref.read(ledControllerProvider);
      unawaited(led.setTopColor(deviceId: deviceId, side: side, color: Colors.black));
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
    final uiState = _ref.read(ledUiProvider);
    final color = side == StockSide.a
        ? uiState.a.heartbeatColor
        : uiState.b.heartbeatColor;
    final active = _on[side]! ? color : Colors.black;
    _on[side] = !_on[side]!;
    final led = _ref.read(ledControllerProvider);
    unawaited(led.setTopColor(deviceId: deviceId, side: side, color: active));
    unawaited(led.setBottomColor(deviceId: deviceId, side: side, color: active));
  }
}
