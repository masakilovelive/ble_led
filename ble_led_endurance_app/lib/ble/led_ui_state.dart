import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import '../storage/local_store.dart';

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode.name,
      'color_argb': color.toARGB32(),
    };
  }

  static LedUiSegmentState fromJson(
    Map<String, dynamic> json, {
    required LedUiSegmentState fallback,
  }) {
    return LedUiSegmentState(
      mode: _parseLedMode(json['mode']?.toString()) ?? fallback.mode,
      color: _parseColor(json['color_argb'], fallback.color),
    );
  }
}

class LedUiSideState {
  final LedUiSegmentState top;
  final LedUiSegmentState bottom;
  final Color heartbeatColor;
  final int heartbeatIntervalMs;
  final int rainbowIntervalMs;
  final double brightness;
  final bool outputEnabled;
  final double batteryPercent;
  final double? batteryVoltage;
  final bool charging;

  const LedUiSideState({
    required this.top,
    required this.bottom,
    required this.heartbeatColor,
    required this.heartbeatIntervalMs,
    required this.rainbowIntervalMs,
    required this.brightness,
    required this.outputEnabled,
    required this.batteryPercent,
    this.batteryVoltage,
    required this.charging,
  });

  LedUiSideState copyWith({
    LedUiSegmentState? top,
    LedUiSegmentState? bottom,
    Color? heartbeatColor,
    int? heartbeatIntervalMs,
    int? rainbowIntervalMs,
    double? brightness,
    bool? outputEnabled,
    double? batteryPercent,
    double? batteryVoltage,
    bool? charging,
  }) {
    return LedUiSideState(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      heartbeatColor: heartbeatColor ?? this.heartbeatColor,
      heartbeatIntervalMs: heartbeatIntervalMs ?? this.heartbeatIntervalMs,
      rainbowIntervalMs: rainbowIntervalMs ?? this.rainbowIntervalMs,
      brightness: brightness ?? this.brightness,
      outputEnabled: outputEnabled ?? this.outputEnabled,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      charging: charging ?? this.charging,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'top': top.toJson(),
      'bottom': bottom.toJson(),
      'heartbeat_color_argb': heartbeatColor.toARGB32(),
      'heartbeat_interval_ms': heartbeatIntervalMs,
      'rainbow_interval_ms': rainbowIntervalMs,
      'brightness': brightness,
      'output_enabled': outputEnabled,
    };
  }

  static LedUiSideState fromJson(
    Map<String, dynamic> json, {
    required LedUiSideState fallback,
  }) {
    return LedUiSideState(
      top: json['top'] is Map<String, dynamic>
          ? LedUiSegmentState.fromJson(
              json['top'] as Map<String, dynamic>,
              fallback: fallback.top,
            )
          : json['top'] is Map
              ? LedUiSegmentState.fromJson(
                  Map<String, dynamic>.from(json['top'] as Map),
                  fallback: fallback.top,
                )
              : fallback.top,
      bottom: json['bottom'] is Map<String, dynamic>
          ? LedUiSegmentState.fromJson(
              json['bottom'] as Map<String, dynamic>,
              fallback: fallback.bottom,
            )
          : json['bottom'] is Map
              ? LedUiSegmentState.fromJson(
                  Map<String, dynamic>.from(json['bottom'] as Map),
                  fallback: fallback.bottom,
                )
              : fallback.bottom,
      heartbeatColor: _parseColor(
        json['heartbeat_color_argb'],
        fallback.heartbeatColor,
      ),
      heartbeatIntervalMs: _parseInt(
        json['heartbeat_interval_ms'],
        fallback.heartbeatIntervalMs,
      ).clamp(150, 10000),
      rainbowIntervalMs: _parseInt(
        json['rainbow_interval_ms'],
        fallback.rainbowIntervalMs,
      ).clamp(1, 65535),
      brightness: _parseDouble(json['brightness'], fallback.brightness).clamp(
        0.0,
        255.0,
      ),
      outputEnabled: json['output_enabled'] is bool
          ? json['output_enabled'] as bool
          : fallback.outputEnabled,
      batteryPercent: fallback.batteryPercent,
      batteryVoltage: fallback.batteryVoltage,
      charging: fallback.charging,
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
      rainbowIntervalMs: 40,
      brightness: 200,
      outputEnabled: false,
      batteryPercent: 0,
      batteryVoltage: null,
      charging: false,
    );
    return const LedUiState(a: defaultSide, b: defaultSide);
  }

  LedUiSideState sideState(StockSide side) {
    return side == StockSide.a ? a : b;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'a': a.toJson(),
      'b': b.toJson(),
    };
  }

  static LedUiState fromJson(Map<String, dynamic> json) {
    final defaults = LedUiState.initial();
    return LedUiState(
      a: json['a'] is Map<String, dynamic>
          ? LedUiSideState.fromJson(
              json['a'] as Map<String, dynamic>,
              fallback: defaults.a,
            )
          : json['a'] is Map
              ? LedUiSideState.fromJson(
                  Map<String, dynamic>.from(json['a'] as Map),
                  fallback: defaults.a,
                )
              : defaults.a,
      b: json['b'] is Map<String, dynamic>
          ? LedUiSideState.fromJson(
              json['b'] as Map<String, dynamic>,
              fallback: defaults.b,
            )
          : json['b'] is Map
              ? LedUiSideState.fromJson(
                  Map<String, dynamic>.from(json['b'] as Map),
                  fallback: defaults.b,
                )
              : defaults.b,
    );
  }
}

final ledUiProvider = StateNotifierProvider<LedUiController, LedUiState>(
  (ref) => LedUiController(),
);

class LedUiController extends StateNotifier<LedUiState> {
  static const String _prefsKeyLedUiState = 'led_ui_state_v1';

  Future<void>? _loadFuture;
  Timer? _persistTimer;
  bool _hydrating = false;

  LedUiController() : super(LedUiState.initial()) {
    _loadFuture = _restoreFromStore();
  }

  Future<void> ensureLoaded() => _loadFuture ?? Future<void>.value();

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

  void setRainbowInterval(StockSide side, int intervalMs) {
    final clamped = intervalMs.clamp(1, 65535);
    _updateSide(side, (sideState) {
      return sideState.copyWith(rainbowIntervalMs: clamped);
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

  void setBatteryVoltage(
    StockSide side,
    double voltage,
    double percent, {
    bool charging = false,
  }) {
    final clamped = percent.clamp(0.0, 1.0);
    _updateSide(
      side,
      (sideState) {
        return sideState.copyWith(
          batteryVoltage: voltage,
          batteryPercent: clamped,
          charging: charging,
        );
      },
      persist: false,
    );
  }

  void _updateSide(
    StockSide side,
    LedUiSideState Function(LedUiSideState sideState) update, {
    bool persist = true,
  }) {
    if (side == StockSide.a) {
      state = LedUiState(a: update(state.a), b: state.b);
    } else {
      state = LedUiState(a: state.a, b: update(state.b));
    }
    if (persist) {
      _schedulePersist();
    }
  }

  Future<void> _restoreFromStore() async {
    try {
      final store = await LocalStore.instance();
      final raw = store.getString(_prefsKeyLedUiState);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      _hydrating = true;
      state = LedUiState.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Ignore broken persisted UI state and continue with defaults.
    } finally {
      _hydrating = false;
    }
  }

  void _schedulePersist() {
    if (_hydrating) {
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_persistState());
    });
  }

  Future<void> _persistState() async {
    try {
      final store = await LocalStore.instance();
      await store.setString(_prefsKeyLedUiState, jsonEncode(state.toJson()));
    } catch (_) {
      // Persistence failure should not break manual control.
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}

LedMode? _parseLedMode(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'off':
      return LedMode.off;
    case 'color':
      return LedMode.color;
    case 'rainbow':
      return LedMode.rainbow;
    case 'heartbeat':
      return LedMode.heartbeat;
    default:
      return null;
  }
}

Color _parseColor(Object? raw, Color fallback) {
  final value = _parseInt(raw, fallback.toARGB32());
  return Color(value);
}

int _parseInt(Object? raw, int fallback) {
  if (raw is int) {
    return raw;
  }
  return int.tryParse('${raw ?? ''}') ?? fallback;
}

double _parseDouble(Object? raw, double fallback) {
  if (raw is num) {
    return raw.toDouble();
  }
  return double.tryParse('${raw ?? ''}') ?? fallback;
}
