import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

enum LedMode { off, color, rainbow, heartbeat }

class LedUiSegmentState {
  final LedMode mode;
  final Color color;

  const LedUiSegmentState({
    required this.mode,
    required this.color,
  });

  LedUiSegmentState copyWith({
    LedMode? mode,
    Color? color,
  }) {
    return LedUiSegmentState(
      mode: mode ?? this.mode,
      color: color ?? this.color,
    );
  }
}

class LedUiSideState {
  final LedUiSegmentState top;
  final LedUiSegmentState bottom;
  final Color heartbeatColor;
  final double brightness;
  final bool outputEnabled;
  final double batteryPercent;
  final double? batteryVoltage;

  const LedUiSideState({
    required this.top,
    required this.bottom,
    required this.heartbeatColor,
    required this.brightness,
    required this.outputEnabled,
    required this.batteryPercent,
    this.batteryVoltage,
  });

  LedUiSideState copyWith({
    LedUiSegmentState? top,
    LedUiSegmentState? bottom,
    Color? heartbeatColor,
    double? brightness,
    bool? outputEnabled,
    double? batteryPercent,
    double? batteryVoltage,
  }) {
    return LedUiSideState(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      heartbeatColor: heartbeatColor ?? this.heartbeatColor,
      brightness: brightness ?? this.brightness,
      outputEnabled: outputEnabled ?? this.outputEnabled,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
    );
  }
}

class LedUiState {
  final LedUiSideState a;
  final LedUiSideState b;

  const LedUiState({
    required this.a,
    required this.b,
  });

  factory LedUiState.initial() {
    const defaultTop = LedUiSegmentState(
      mode: LedMode.off,
      color: Color(0xFFE53935),
    );
    const defaultBottom = LedUiSegmentState(
      mode: LedMode.off,
      color: Color(0xFF4DD0E1),
    );
    const defaultSide = LedUiSideState(
      top: defaultTop,
      bottom: defaultBottom,
      heartbeatColor: Colors.red,
      brightness: 200,
      outputEnabled: false,
      batteryPercent: 0.8,
      batteryVoltage: null,
    );
    return const LedUiState(a: defaultSide, b: defaultSide);
  }
}

final ledUiProvider = StateNotifierProvider<LedUiController, LedUiState>(
  (ref) => LedUiController(),
);

class LedUiController extends StateNotifier<LedUiState> {
  LedUiController() : super(LedUiState.initial());

  void setSegmentColor(StockSide side, bool isTop, Color color) {
    _updateSide(side, (sideState) {
      final updated = isTop
          ? sideState.top.copyWith(color: color)
          : sideState.bottom.copyWith(color: color);
      return isTop
          ? sideState.copyWith(top: updated)
          : sideState.copyWith(bottom: updated);
    });
  }

  void setSegmentMode(StockSide side, bool isTop, LedMode mode) {
    _updateSide(side, (sideState) {
      final updated = isTop
          ? sideState.top.copyWith(mode: mode)
          : sideState.bottom.copyWith(mode: mode);
      return isTop
          ? sideState.copyWith(top: updated)
          : sideState.copyWith(bottom: updated);
    });
  }

  void setBothMode(StockSide side, LedMode mode) {
    _updateSide(side, (sideState) {
      return sideState.copyWith(
        top: sideState.top.copyWith(mode: mode),
        bottom: sideState.bottom.copyWith(mode: mode),
      );
    });
  }

  void setHeartbeatColor(StockSide side, Color color) {
    _updateSide(side, (sideState) => sideState.copyWith(heartbeatColor: color));
  }

  void setBrightness(StockSide side, double brightness) {
    final clamped = brightness.clamp(0.0, 255.0);
    _updateSide(side, (sideState) => sideState.copyWith(brightness: clamped));
  }

  void setOutputEnabled(StockSide side, bool enabled) {
    _updateSide(side, (sideState) => sideState.copyWith(outputEnabled: enabled));
  }

  void setBatteryPercent(StockSide side, double percent) {
    final clamped = percent.clamp(0.0, 1.0);
    _updateSide(side, (sideState) => sideState.copyWith(batteryPercent: clamped));
  }

  void setBatteryVoltage(StockSide side, double voltage, double percent) {
    final clamped = percent.clamp(0.0, 1.0);
    _updateSide(
      side,
      (sideState) => sideState.copyWith(
        batteryVoltage: voltage,
        batteryPercent: clamped,
      ),
    );
  }

  void _updateSide(
    StockSide side,
    LedUiSideState Function(LedUiSideState) update,
  ) {
    if (side == StockSide.a) {
      state = LedUiState(a: update(state.a), b: state.b);
    } else {
      state = LedUiState(a: state.a, b: update(state.b));
    }
  }
}
