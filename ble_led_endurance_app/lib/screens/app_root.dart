import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:path_provider/path_provider.dart';

import '../ble/heartbeat_controller.dart';
import '../ble/led_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/restart_probe_profile.dart';
import '../ble/stock_controller.dart';
import 'splash_screen.dart';
import 'stress_lab_screen.dart';

enum AppStage { splash, stress }

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> with WidgetsBindingObserver {
  static const double _probeStartupCycleMs = 1000;
  static const Duration _startupConnectTimeout = Duration(seconds: 6);
  static const Duration _startupRetryDelay = Duration(milliseconds: 1200);
  static const int _startupConnectMaxAttempts = 2;
  static const List<Color> _probeStartupPalette = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFF8000),
    Color(0xFFFFFF00),
    Color(0xFF00FFFF),
    Color(0xFF0080FF),
  ];

  AppStage _stage = AppStage.splash;
  Future<void>? _resumeReconnect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleSplashComplete() {
    if (!mounted) {
      return;
    }
    setState(() => _stage = AppStage.stress);
    Future<void>.microtask(() async {
      final controller = ref.read(stockProvider.notifier);
      await controller.ensureLoaded();
      if (!mounted) {
        return;
      }
      bool? autoConnectOk;
      String? errorText;
      int autoConnectAttempts = 0;
      _RestartProbeOutcome probeOutcome = const _RestartProbeOutcome();
      try {
        final connectOutcome = await _attemptAutoConnectStored(controller);
        autoConnectOk = connectOutcome.ok;
        errorText = connectOutcome.errorText;
        autoConnectAttempts = connectOutcome.attempts;
        probeOutcome = await _runRestartProbeReplay(autoConnectOk);
      } catch (e) {
        // Keep UI alive even if BLE stack throws during startup.
        errorText = e.toString();
      }
      await _writeRestartProbeStatus(
        phase: 'startup',
        autoConnectOk: autoConnectOk,
        errorText: errorText,
        probeOutcome: probeOutcome,
        autoConnectAttempts: autoConnectAttempts,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _stage != AppStage.stress) {
      return;
    }
    _resumeReconnect ??= _restoreConnections().whenComplete(() {
      _resumeReconnect = null;
    });
  }

  Future<void> _restoreConnections() async {
    final controller = ref.read(stockProvider.notifier);
    await controller.ensureLoaded();
    if (!mounted) {
      return;
    }
    final stock = ref.read(stockProvider);
    if (!stock.registered) {
      return;
    }
    final needsReconnect = stock.a.status != DeviceConnectionState.connected ||
        stock.b.status != DeviceConnectionState.connected;
    bool? autoConnectOk;
    String? errorText;
    int autoConnectAttempts = 0;
    _RestartProbeOutcome probeOutcome = const _RestartProbeOutcome();
    if (needsReconnect) {
      try {
        final connectOutcome = await _attemptAutoConnectStored(controller);
        autoConnectOk = connectOutcome.ok;
        errorText = connectOutcome.errorText;
        autoConnectAttempts = connectOutcome.attempts;
        if (autoConnectOk != true) {
          await controller.disconnectBoth();
        } else {
          probeOutcome = await _runRestartProbeReplay(autoConnectOk);
        }
      } catch (e) {
        await controller.disconnectBoth();
        errorText = e.toString();
      }
    }
    await _writeRestartProbeStatus(
      phase: 'resume',
      autoConnectOk: autoConnectOk,
      errorText: errorText,
      probeOutcome: probeOutcome,
      autoConnectAttempts: autoConnectAttempts,
    );
  }

  Future<void> _writeRestartProbeStatus({
    required String phase,
    required bool? autoConnectOk,
    required String? errorText,
    required _RestartProbeOutcome probeOutcome,
    required int autoConnectAttempts,
  }) async {
    try {
      final stock = ref.read(stockProvider);
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}restart_probe_status.json',
      );
      final payload = <String, Object?>{
        'timestamp': DateTime.now().toIso8601String(),
        'phase': phase,
        'auto_connect_ok': autoConnectOk,
        'auto_connect_attempts': autoConnectAttempts,
        'auto_connect_timeout_ms': _startupConnectTimeout.inMilliseconds,
        'registered': stock.registered,
        'a_status': stock.a.status.name,
        'b_status': stock.b.status.name,
        'a_device': stock.a.device?.name,
        'b_device': stock.b.device?.name,
        'a_pair': stock.a.pairNumber,
        'b_pair': stock.b.pairNumber,
        'error': errorText,
        'replay_profile_enabled': probeOutcome.profile?.enabled ?? false,
        'replay_feature': probeOutcome.profile?.featureName,
        'replay_syncro': probeOutcome.profile?.syncro,
        'replay_color_hex': probeOutcome.profile?.colorHex,
        'replay_brightness': probeOutcome.profile?.brightness,
        'replay_heartbeat_interval_ms':
            probeOutcome.profile?.heartbeatIntervalMs,
        'replay_rainbow_interval_ms': probeOutcome.profile?.rainbowIntervalMs,
        'replay_scenario_label': probeOutcome.profile?.scenarioLabel,
        'startup_wave_ok': probeOutcome.startupWaveOk,
        'startup_wave_error': probeOutcome.startupWaveError,
        'replay_apply_ok': probeOutcome.replayApplyOk,
        'replay_apply_error': probeOutcome.replayApplyError,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {
      // Restart probe logging must not break the app lifecycle.
    }
  }

  Future<_AutoConnectOutcome> _attemptAutoConnectStored(
    StockController controller,
  ) async {
    String? lastErrorText;
    bool? ok;
    var attempts = 0;
    for (var attempt = 1; attempt <= _startupConnectMaxAttempts; attempt++) {
      attempts = attempt;
      try {
        ok =
            await controller.autoConnectStored(timeout: _startupConnectTimeout);
        if (ok == true) {
          return _AutoConnectOutcome(ok: true, attempts: attempt);
        }
      } catch (e) {
        lastErrorText = e.toString();
      }
      if (attempt < _startupConnectMaxAttempts) {
        await Future<void>.delayed(_startupRetryDelay);
      }
    }
    return _AutoConnectOutcome(
      ok: ok,
      errorText: lastErrorText,
      attempts: attempts,
    );
  }

  Future<_RestartProbeOutcome> _runRestartProbeReplay(
      bool? autoConnectOk) async {
    final profile = await RestartProbeProfile.load();
    if (profile == null || !profile.enabled) {
      return _RestartProbeOutcome(profile: profile);
    }
    if (autoConnectOk != true) {
      return _RestartProbeOutcome(
        profile: profile,
        startupWaveOk: false,
        replayApplyOk: false,
        replayApplyError: 'Auto connect did not complete before replay.',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final startupError = await _runProbeStartupWave(profile);
    if (startupError != null) {
      return _RestartProbeOutcome(
        profile: profile,
        startupWaveOk: false,
        startupWaveError: startupError,
        replayApplyOk: false,
        replayApplyError: 'Startup wave failed before replay.',
      );
    }

    final replayError = await _applyRestartProbeProfile(profile);
    return _RestartProbeOutcome(
      profile: profile,
      startupWaveOk: true,
      replayApplyOk: replayError == null,
      replayApplyError: replayError,
    );
  }

  Future<String?> _runProbeStartupWave(RestartProbeProfile profile) async {
    final targets = _connectedTargets(syncro: profile.syncro);
    if (targets.isEmpty) {
      return 'No connected devices available for startup wave.';
    }
    if (profile.syncro && targets.length < 2) {
      return 'SYNCRO startup wave requires both A and B connected.';
    }

    final led = ref.read(ledControllerProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final ledUi = ref.read(ledUiProvider.notifier);
    final stepMs =
        (_probeStartupCycleMs / _probeStartupPalette.length).round().clamp(
              60,
              5000,
            );

    try {
      for (final target in targets) {
        heartbeat.stop(
          target.side,
          deviceId: target.deviceId,
          sendOff: false,
          resetMode: false,
        );
      }
      await Future.wait(
        targets.map((target) async {
          try {
            await led.stopRainbow(target.deviceId);
          } catch (_) {}
          await led.setOutputEnabled(target.deviceId, true);
          await led.setBrightness(target.deviceId, target.brightness);
        }),
      );

      for (final color in _probeStartupPalette) {
        await Future.wait(
          targets.map((target) async {
            await led.setTopColor(
              deviceId: target.deviceId,
              side: target.side,
              color: color,
            );
            await led.setBottomColor(
              deviceId: target.deviceId,
              side: target.side,
              color: color,
            );
          }),
        );
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }

      final last = _probeStartupPalette.last;
      for (final target in targets) {
        ledUi.setOutputEnabled(target.side, true);
        ledUi.setBrightness(target.side, target.brightness.toDouble());
        ledUi.setSegmentColor(target.side, ColorZone.both, last);
        ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.color);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _applyRestartProbeProfile(RestartProbeProfile profile) async {
    final targets = _connectedTargets(syncro: profile.syncro);
    if (targets.isEmpty) {
      return 'No connected devices available for replay.';
    }
    if (profile.syncro && targets.length < 2) {
      return 'SYNCRO replay requires both A and B connected.';
    }

    final led = ref.read(ledControllerProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final ledUi = ref.read(ledUiProvider.notifier);

    try {
      for (final target in targets) {
        heartbeat.stop(
          target.side,
          deviceId: target.deviceId,
          sendOff: false,
          resetMode: false,
        );
        try {
          await led.stopRainbow(target.deviceId);
        } catch (_) {}
        await led.setOutputEnabled(target.deviceId, true);
        await led.setBrightness(target.deviceId, profile.brightness);
        ledUi.setOutputEnabled(target.side, true);
        ledUi.setBrightness(target.side, profile.brightness.toDouble());
      }

      switch (profile.feature) {
        case RestartProbeFeature.color:
          for (final target in targets) {
            ledUi.setSegmentColor(target.side, ColorZone.both, profile.color);
            ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.color);
            await led.setTopColor(
              deviceId: target.deviceId,
              side: target.side,
              color: profile.color,
            );
            await led.setBottomColor(
              deviceId: target.deviceId,
              side: target.side,
              color: profile.color,
            );
          }
          break;
        case RestartProbeFeature.rainbow:
          for (final target in targets) {
            ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.rainbow);
            await led.startRainbow(
              target.deviceId,
              intervalMs: profile.rainbowIntervalMs,
            );
          }
          break;
        case RestartProbeFeature.heartbeat:
          for (final target in targets) {
            ledUi.setHeartbeatColor(target.side, profile.color);
            ledUi.setHeartbeatInterval(
              target.side,
              profile.heartbeatIntervalMs,
            );
            heartbeat.start(
              target.side,
              target.deviceId,
              interval: Duration(milliseconds: profile.heartbeatIntervalMs),
            );
          }
          break;
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  List<_ProbeTarget> _connectedTargets({required bool syncro}) {
    final stock = ref.read(stockProvider);
    final targets = <_ProbeTarget>[];
    for (final side in syncro
        ? const <StockSide>[StockSide.a, StockSide.b]
        : const <StockSide>[StockSide.a]) {
      final sideState = side == StockSide.a ? stock.a : stock.b;
      final deviceId = sideState.device?.id;
      if (deviceId == null ||
          sideState.status != DeviceConnectionState.connected) {
        continue;
      }
      final brightness =
          ref.read(ledUiProvider).sideState(side).brightness.round();
      targets.add(
        _ProbeTarget(
          side: side,
          deviceId: deviceId,
          brightness: brightness <= 0 ? 255 : brightness,
        ),
      );
    }
    return targets;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 1.1, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: _buildStage(),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case AppStage.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onFinished: _handleSplashComplete,
        );
      case AppStage.stress:
        return const StressLabScreen(key: ValueKey('stress_lab'));
    }
  }
}

class _RestartProbeOutcome {
  final RestartProbeProfile? profile;
  final bool? startupWaveOk;
  final String? startupWaveError;
  final bool? replayApplyOk;
  final String? replayApplyError;

  const _RestartProbeOutcome({
    this.profile,
    this.startupWaveOk,
    this.startupWaveError,
    this.replayApplyOk,
    this.replayApplyError,
  });
}

class _AutoConnectOutcome {
  final bool? ok;
  final String? errorText;
  final int attempts;

  const _AutoConnectOutcome({
    required this.ok,
    this.errorText,
    required this.attempts,
  });
}

class _ProbeTarget {
  final StockSide side;
  final String deviceId;
  final int brightness;

  const _ProbeTarget({
    required this.side,
    required this.deviceId,
    required this.brightness,
  });
}
