import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

enum LedMode { off, color, rainbow, heartbeat }

enum ColorZone { top, bottom, both }

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
  final int heartbeatIntervalMs;
  final double brightness;
  final bool outputEnabled;
  final double batteryPercent;
  final double? batteryVoltage;

  const LedUiSideState({
    required this.top,
    required this.bottom,
    required this.heartbeatColor,
    required this.heartbeatIntervalMs,
    required this.brightness,
    required this.outputEnabled,
    required this.batteryPercent,
    this.batteryVoltage,
  });

  LedUiSideState copyWith({
    LedUiSegmentState? top,
    LedUiSegmentState? bottom,
    Color? heartbeatColor,
    int? heartbeatIntervalMs,
    double? brightness,
    bool? outputEnabled,
    double? batteryPercent,
    double? batteryVoltage,
  }) {
    return LedUiSideState(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      heartbeatColor: heartbeatColor ?? this.heartbeatColor,
      heartbeatIntervalMs: heartbeatIntervalMs ?? this.heartbeatIntervalMs,
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
    const defaultSide = LedUiSideState(
      top: LedUiSegmentState(
        mode: LedMode.off,
        color: Color(0xFFFFFFFF),
      ),
      bottom: LedUiSegmentState(
        mode: LedMode.off,
        color: Color(0xFFFFFFFF),
      ),
      heartbeatColor: Color(0xFFFF3B30),
      heartbeatIntervalMs: 600,
      brightness: 200,
      outputEnabled: false,
      batteryPercent: 0,
      batteryVoltage: null,
    );
    return const LedUiState(a: defaultSide, b: defaultSide);
  }

  LedUiSideState sideState(StockSide side) {
    return side == StockSide.a ? a : b;
  }
}

final ledUiProvider = StateNotifierProvider<LedUiController, LedUiState>(
  (ref) => LedUiController(),
);

class LedUiController extends StateNotifier<LedUiState> {
  LedUiController() : super(LedUiState.initial());

  LedUiSideState sideState(StockSide side) {
    return side == StockSide.a ? state.a : state.b;
  }

  void setSegmentColor(StockSide side, ColorZone zone, Color color) {
    _updateSide(side, (sideState) {
      switch (zone) {
        case ColorZone.top:
          return sideState.copyWith(
            top: sideState.top.copyWith(color: color),
          );
        case ColorZone.bottom:
          return sideState.copyWith(
            bottom: sideState.bottom.copyWith(color: color),
          );
        case ColorZone.both:
          return sideState.copyWith(
            top: sideState.top.copyWith(color: color),
            bottom: sideState.bottom.copyWith(color: color),
          );
      }
    });
  }

  void setSegmentMode(StockSide side, ColorZone zone, LedMode mode) {
    _updateSide(side, (sideState) {
      switch (zone) {
        case ColorZone.top:
          return sideState.copyWith(
            top: sideState.top.copyWith(mode: mode),
          );
        case ColorZone.bottom:
          return sideState.copyWith(
            bottom: sideState.bottom.copyWith(mode: mode),
          );
        case ColorZone.both:
          return sideState.copyWith(
            top: sideState.top.copyWith(mode: mode),
            bottom: sideState.bottom.copyWith(mode: mode),
          );
      }
    });
  }

  void setHeartbeatColor(StockSide side, Color color) {
    _updateSide(side, (sideState) {
      return sideState.copyWith(heartbeatColor: color);
    });
  }

  void setHeartbeatInterval(StockSide side, int intervalMs) {
    _updateSide(side, (sideState) {
      return sideState.copyWith(heartbeatIntervalMs: intervalMs);
    });
  }

  void setBrightness(StockSide side, double brightness) {
    final clamped = brightness.clamp(0.0, 255.0);
    _updateSide(side, (sideState) {
      return sideState.copyWith(brightness: clamped);
    });
  }

  void setOutputEnabled(StockSide side, bool enabled) {
    _updateSide(side, (sideState) {
      return sideState.copyWith(outputEnabled: enabled);
    });
  }

  void setBatteryVoltage(StockSide side, double voltage, double percent) {
    final clamped = percent.clamp(0.0, 1.0);
    _updateSide(side, (sideState) {
      return sideState.copyWith(
        batteryVoltage: voltage,
        batteryPercent: clamped,
      );
    });
  }

  void _updateSide(
    StockSide side,
    LedUiSideState Function(LedUiSideState sideState) update,
  ) {
    if (side == StockSide.a) {
      state = LedUiState(a: update(state.a), b: state.b);
    } else {
      state = LedUiState(a: state.a, b: update(state.b));
    }
  }
}
