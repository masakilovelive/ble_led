import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:logger/logger.dart' as app_logger;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../env.dart';
import 'ble_client.dart';
import 'heartbeat_controller.dart';
import 'led_controller.dart';
import 'led_ui_state.dart';
import 'mcu_serial_controller.dart';
import 'models.dart';
import 'stock_controller.dart';

enum StressRunStatus { idle, running, stopped, done, failed, error }

enum StressFeature { color, heartbeat, rainbow }

enum StressScope { stockA, stockB, syncro }

enum StressRunnerMode { pc, mcu }

enum StressSweepPlan { matrix73, featureTransition9 }

extension StressSweepPlanText on StressSweepPlan {
  String get label {
    switch (this) {
      case StressSweepPlan.matrix73:
        return 'Matrix Sweep';
      case StressSweepPlan.featureTransition9:
        return 'Feature Transition';
    }
  }

  String get description {
    switch (this) {
      case StressSweepPlan.matrix73:
        return '73-case matrix with color, heartbeat, and rainbow permutations.';
      case StressSweepPlan.featureTransition9:
        return '9 cases in one power window: STOCK_A/B/SYNCRO each run COLOR -> HEARTBEAT -> RAINBOW.';
    }
  }
}

class StressSettings {
  final StressSweepPlan sweepPlan;
  final StressRunnerMode runnerMode;
  final int cycles;
  final int settleMs;
  final int caseHoldMs;
  final int caseGapMs;
  final int mcuOffGuardMs;
  final int mcuPowerToD5Ms;
  final int mcuD5PulseMs;
  final int mcuConnectWindowMs;
  final int mcuDisconnectWindowMs;
  final bool scanBeforeConnect;
  final bool reconnectEachCycle;
  final bool verifyGattOnConnect;
  final bool readBatteryEachCase;
  final bool stopOnFail;
  final bool mcuSensorOnCheck;
  final bool mcuSensorOffCheck;
  final bool includeColor;
  final bool includeHeartbeat;
  final bool includeRainbow;
  final bool includeSyncroCases;

  const StressSettings({
    required this.sweepPlan,
    required this.runnerMode,
    required this.cycles,
    required this.settleMs,
    required this.caseHoldMs,
    required this.caseGapMs,
    required this.mcuOffGuardMs,
    required this.mcuPowerToD5Ms,
    required this.mcuD5PulseMs,
    required this.mcuConnectWindowMs,
    required this.mcuDisconnectWindowMs,
    required this.scanBeforeConnect,
    required this.reconnectEachCycle,
    required this.verifyGattOnConnect,
    required this.readBatteryEachCase,
    required this.stopOnFail,
    required this.mcuSensorOnCheck,
    required this.mcuSensorOffCheck,
    required this.includeColor,
    required this.includeHeartbeat,
    required this.includeRainbow,
    required this.includeSyncroCases,
  });

  factory StressSettings.defaults() {
    return const StressSettings(
      sweepPlan: StressSweepPlan.matrix73,
      runnerMode: StressRunnerMode.mcu,
      cycles: 1,
      settleMs: 200,
      caseHoldMs: 500,
      caseGapMs: 150,
      mcuOffGuardMs: 0,
      mcuPowerToD5Ms: 2000,
      mcuD5PulseMs: 2000,
      mcuConnectWindowMs: 6000,
      mcuDisconnectWindowMs: 500,
      scanBeforeConnect: true,
      reconnectEachCycle: true,
      verifyGattOnConnect: false,
      readBatteryEachCase: true,
      stopOnFail: false,
      mcuSensorOnCheck: false,
      mcuSensorOffCheck: false,
      includeColor: true,
      includeHeartbeat: true,
      includeRainbow: true,
      includeSyncroCases: true,
    );
  }
}

class StressCaseSpec {
  final StressFeature feature;
  final StressScope scope;
  final ColorZone zone;
  final Color? color;
  final int brightness;
  final int? intervalMs;

  const StressCaseSpec({
    required this.feature,
    required this.scope,
    required this.zone,
    required this.color,
    required this.brightness,
    required this.intervalMs,
  });

  String get featureLabel {
    switch (feature) {
      case StressFeature.color:
        return 'COLOR';
      case StressFeature.heartbeat:
        return 'HEARTBEAT';
      case StressFeature.rainbow:
        return 'RAINBOW';
    }
  }

  String get scopeLabel {
    switch (scope) {
      case StressScope.stockA:
        return 'STOCK_A';
      case StressScope.stockB:
        return 'STOCK_B';
      case StressScope.syncro:
        return 'SYNCRO';
    }
  }

  String get zoneLabel {
    if (feature != StressFeature.color) {
      return 'BOTH';
    }
    switch (zone) {
      case ColorZone.top:
        return 'TOP';
      case ColorZone.bottom:
        return 'BOTTOM';
      case ColorZone.both:
        return 'BOTH';
    }
  }

  String get summary {
    final colorText = color == null ? '' : ' ${_colorToHex(color!)}';
    final intervalText =
        intervalMs == null ? '' : ' ${intervalMs.toString()}ms';
    return '$featureLabel $scopeLabel $zoneLabel BRI:$brightness$colorText$intervalText';
  }
}

class StressCaseRecord {
  final int cycle;
  final int caseIndex;
  final DateTime startedAt;
  final DateTime endedAt;
  final String result;
  final String failureClass;
  final String failureDetail;
  final String feature;
  final String scope;
  final String zone;
  final String summary;
  final String colorHex;
  final int brightness;
  final int? intervalMs;
  final int? rssiA;
  final int? rssiB;
  final double? batteryA;
  final double? batteryB;
  final Duration duration;
  final String lastLog;

  const StressCaseRecord({
    required this.cycle,
    required this.caseIndex,
    required this.startedAt,
    required this.endedAt,
    required this.result,
    required this.failureClass,
    required this.failureDetail,
    required this.feature,
    required this.scope,
    required this.zone,
    required this.summary,
    required this.colorHex,
    required this.brightness,
    required this.intervalMs,
    required this.rssiA,
    required this.rssiB,
    required this.batteryA,
    required this.batteryB,
    required this.duration,
    required this.lastLog,
  });
}

class StressLabState {
  static const Object _sentinel = Object();

  final StressRunStatus status;
  final StressSettings settings;
  final int totalCycles;
  final int doneCycles;
  final int totalCasesPerCycle;
  final int executedCases;
  final int passCount;
  final int failCount;
  final int? activeCycle;
  final int? activeCaseIndex;
  final String? activeCaseLabel;
  final String? message;
  final String? reportPath;
  final String? summaryPath;
  final String? lastOutcome;
  final Map<String, int> failureCounts;
  final List<StressCaseRecord> records;
  final List<String> logs;

  const StressLabState({
    required this.status,
    required this.settings,
    required this.totalCycles,
    required this.doneCycles,
    required this.totalCasesPerCycle,
    required this.executedCases,
    required this.passCount,
    required this.failCount,
    required this.activeCycle,
    required this.activeCaseIndex,
    required this.activeCaseLabel,
    required this.message,
    required this.reportPath,
    required this.summaryPath,
    required this.lastOutcome,
    required this.failureCounts,
    required this.records,
    required this.logs,
  });

  factory StressLabState.initial() {
    return StressLabState(
      status: StressRunStatus.idle,
      settings: StressSettings.defaults(),
      totalCycles: 0,
      doneCycles: 0,
      totalCasesPerCycle: 0,
      executedCases: 0,
      passCount: 0,
      failCount: 0,
      activeCycle: null,
      activeCaseIndex: null,
      activeCaseLabel: null,
      message: null,
      reportPath: null,
      summaryPath: null,
      lastOutcome: null,
      failureCounts: const <String, int>{},
      records: const <StressCaseRecord>[],
      logs: const <String>[],
    );
  }

  bool get isRunning => status == StressRunStatus.running;

  double get progress {
    if (totalCycles <= 0) {
      return 0;
    }
    final activeFraction = (activeCaseIndex != null && totalCasesPerCycle > 0)
        ? (activeCaseIndex! / totalCasesPerCycle).clamp(0.0, 1.0)
        : 0.0;
    return ((doneCycles + activeFraction) / totalCycles).clamp(0.0, 1.0);
  }

  String get statusText {
    switch (status) {
      case StressRunStatus.idle:
        return 'IDLE';
      case StressRunStatus.running:
        return 'RUNNING';
      case StressRunStatus.stopped:
        return 'STOPPED';
      case StressRunStatus.done:
        return 'DONE';
      case StressRunStatus.failed:
        return 'FAILED';
      case StressRunStatus.error:
        return 'ERROR';
    }
  }

  StressLabState copyWith({
    StressRunStatus? status,
    StressSettings? settings,
    int? totalCycles,
    int? doneCycles,
    int? totalCasesPerCycle,
    int? executedCases,
    int? passCount,
    int? failCount,
    Object? activeCycle = _sentinel,
    Object? activeCaseIndex = _sentinel,
    Object? activeCaseLabel = _sentinel,
    Object? message = _sentinel,
    Object? reportPath = _sentinel,
    Object? summaryPath = _sentinel,
    Object? lastOutcome = _sentinel,
    Map<String, int>? failureCounts,
    List<StressCaseRecord>? records,
    List<String>? logs,
  }) {
    return StressLabState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      totalCycles: totalCycles ?? this.totalCycles,
      doneCycles: doneCycles ?? this.doneCycles,
      totalCasesPerCycle: totalCasesPerCycle ?? this.totalCasesPerCycle,
      executedCases: executedCases ?? this.executedCases,
      passCount: passCount ?? this.passCount,
      failCount: failCount ?? this.failCount,
      activeCycle: identical(activeCycle, _sentinel)
          ? this.activeCycle
          : activeCycle as int?,
      activeCaseIndex: identical(activeCaseIndex, _sentinel)
          ? this.activeCaseIndex
          : activeCaseIndex as int?,
      activeCaseLabel: identical(activeCaseLabel, _sentinel)
          ? this.activeCaseLabel
          : activeCaseLabel as String?,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      reportPath: identical(reportPath, _sentinel)
          ? this.reportPath
          : reportPath as String?,
      summaryPath: identical(summaryPath, _sentinel)
          ? this.summaryPath
          : summaryPath as String?,
      lastOutcome: identical(lastOutcome, _sentinel)
          ? this.lastOutcome
          : lastOutcome as String?,
      failureCounts: failureCounts ?? this.failureCounts,
      records: records ?? this.records,
      logs: logs ?? this.logs,
    );
  }
}

final stressLabProvider =
    StateNotifierProvider<StressLabController, StressLabState>(
  (ref) => StressLabController(ref),
);

class StressLabController extends StateNotifier<StressLabState> {
  StressLabController(this._ref) : super(StressLabState.initial());

  static const Duration _scanWindow = Duration(seconds: 4);
  static const Duration _connectTimeout = Duration(seconds: 18);
  static const Duration _postRunDisconnectTimeout = Duration(seconds: 4);
  static const int _maxLogs = 300;
  static const double _startupCycleMs = 1000;
  static final List<Color> _startupPalette = <Color>[
    const Color(0xFFFF0000),
    const Color(0xFFFF8000),
    const Color(0xFFFFFF00),
    const Color(0xFF00FFFF),
    const Color(0xFF0080FF),
  ];
  static const List<Color> _colorPalette = <Color>[
    Color(0xFFFF3B30),
    Color(0xFF34C759),
    Color(0xFF007AFF),
    Color(0xFFFFFFFF),
  ];
  static const int _fixedBrightness = 255;
  static const List<int> _brightnessLevels = <int>[_fixedBrightness];
  static const List<int> _heartbeatIntervalsMs = <int>[300, 600, 1000];
  static const List<int> _rainbowIntervalsMs = <int>[20, 40, 120];
  static const int _transitionHeartbeatIntervalMs = 600;
  static const int _transitionRainbowIntervalMs = 40;

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  bool _stopRequested = false;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  int? _lastScanRssiA;
  int? _lastScanRssiB;

  BleClient get _client => _ref.read(bleClientProvider);
  StockController get _stock => _ref.read(stockProvider.notifier);
  LedController get _led => _ref.read(ledControllerProvider);
  HeartbeatController get _heartbeat => _ref.read(heartbeatControllerProvider);
  LedUiController get _ledUi => _ref.read(ledUiProvider.notifier);
  McuSerialController get _mcu => _ref.read(mcuSerialProvider.notifier);

  int plannedCaseCount(StressSettings settings) {
    return _buildCases(settings).length;
  }

  Future<void> start({
    required StressSweepPlan sweepPlan,
    required StressRunnerMode runnerMode,
    required int cycles,
    required int settleMs,
    required int caseHoldMs,
    required int caseGapMs,
    required int mcuOffGuardMs,
    required int mcuPowerToD5Ms,
    required int mcuD5PulseMs,
    required int mcuConnectWindowMs,
    required int mcuDisconnectWindowMs,
    required bool scanBeforeConnect,
    required bool reconnectEachCycle,
    required bool verifyGattOnConnect,
    required bool readBatteryEachCase,
    required bool stopOnFail,
    required bool mcuSensorOnCheck,
    required bool mcuSensorOffCheck,
    required bool includeColor,
    required bool includeHeartbeat,
    required bool includeRainbow,
    required bool includeSyncroCases,
  }) async {
    if (state.isRunning) {
      return;
    }

    final settings = StressSettings(
      sweepPlan: sweepPlan,
      runnerMode: runnerMode,
      cycles: cycles,
      settleMs: settleMs,
      caseHoldMs: caseHoldMs,
      caseGapMs: caseGapMs,
      mcuOffGuardMs: mcuOffGuardMs,
      mcuPowerToD5Ms: mcuPowerToD5Ms,
      mcuD5PulseMs: mcuD5PulseMs,
      mcuConnectWindowMs: mcuConnectWindowMs,
      mcuDisconnectWindowMs: mcuDisconnectWindowMs,
      scanBeforeConnect: scanBeforeConnect,
      reconnectEachCycle: reconnectEachCycle,
      verifyGattOnConnect: verifyGattOnConnect,
      readBatteryEachCase: readBatteryEachCase,
      stopOnFail: stopOnFail,
      mcuSensorOnCheck: mcuSensorOnCheck,
      mcuSensorOffCheck: mcuSensorOffCheck,
      includeColor: includeColor,
      includeHeartbeat: includeHeartbeat,
      includeRainbow: includeRainbow,
      includeSyncroCases: includeSyncroCases,
    );
    final cases = _buildCases(settings);
    final validationError = await _validateBeforeStart(settings, cases.length);
    if (validationError != null) {
      state = state.copyWith(
        status: StressRunStatus.failed,
        settings: settings,
        totalCycles: cycles,
        totalCasesPerCycle: cases.length,
        message: validationError,
      );
      _appendLog('[STRESS] validation failed: $validationError');
      return;
    }

    _stopRequested = false;
    _lastScanRssiA = null;
    _lastScanRssiB = null;
    state = StressLabState.initial().copyWith(
      status: StressRunStatus.running,
      settings: settings,
      totalCycles: settings.cycles,
      totalCasesPerCycle: cases.length,
      message: '${settings.sweepPlan.label} started',
    );
    _appendLog(
      '[STRESS] start plan=${settings.sweepPlan.label} '
      'cycles=${settings.cycles} casesPerCycle=${cases.length}',
    );

    unawaited(_runLoop(settings, cases));
  }

  void stop() {
    if (!state.isRunning) {
      return;
    }
    _stopRequested = true;
    _appendLog('[STRESS] stop requested');
    if (state.settings.runnerMode == StressRunnerMode.mcu) {
      unawaited(_mcu.sendLine('stop'));
    }
    unawaited(_scanSubscription?.cancel());
    _scanSubscription = null;
  }

  Future<String?> _validateBeforeStart(
    StressSettings settings,
    int caseCount,
  ) async {
    if (settings.cycles <= 0) {
      return 'Cycles must be greater than 0.';
    }
    if (settings.settleMs < 0 ||
        settings.caseHoldMs < 0 ||
        settings.caseGapMs < 0 ||
        settings.mcuOffGuardMs < 0 ||
        settings.mcuPowerToD5Ms < 0 ||
        settings.mcuD5PulseMs < 0 ||
        settings.mcuConnectWindowMs < 0 ||
        settings.mcuDisconnectWindowMs < 0) {
      return 'Timing values must be 0 or more.';
    }
    if (caseCount <= 0) {
      return 'Enable at least one test category.';
    }
    final mcuSessionsPerCycle = _mcuSessionsPerCycle(settings, caseCount);
    if (settings.runnerMode == StressRunnerMode.mcu &&
        settings.cycles * mcuSessionsPerCycle > 10000) {
      return 'MCU mode supports up to 10000 MCU sessions per run.';
    }
    await _stock.ensureLoaded();
    final stockState = _ref.read(stockProvider);
    if (!stockState.registered) {
      return 'Assign A/B devices first in Bluetooth Setup.';
    }
    if (stockState.hasPairMismatch) {
      return 'N mismatch: A=${stockState.a.pairNumber}, B=${stockState.b.pairNumber}';
    }
    if (stockState.roleMismatchA || stockState.roleMismatchB) {
      return 'Role mismatch: odd number is A, even number is B.';
    }
    final granted = await _ensurePermissions();
    if (!granted) {
      return 'BLE permissions not granted.';
    }
    if (settings.runnerMode == StressRunnerMode.mcu) {
      await _mcu.refreshDevices();
      final mcuState = _ref.read(mcuSerialProvider);
      if (mcuState.transportMode == McuTransportMode.usb &&
          !mcuState.connected &&
          mcuState.devices.isEmpty) {
        return 'No MCU USB serial device found. Android must be connected to the UNO as a USB host via OTG. If the phone is connected to a PC for adb, it stays in device mode and cannot see the MCU.';
      }
      if (mcuState.transportMode == McuTransportMode.bridge) {
        if (mcuState.bridgeHost.trim().isEmpty ||
            mcuState.bridgePort <= 0 ||
            mcuState.bridgePort > 65535) {
          return 'Enter a valid MCU bridge host/port.';
        }
      }
    }
    return null;
  }

  Future<void> _runLoop(
    StressSettings settings,
    List<StressCaseSpec> cases,
  ) async {
    if (settings.runnerMode == StressRunnerMode.mcu) {
      await _runLoopMcu(settings, cases);
      return;
    }
    await _runLoopPc(settings, cases);
  }

  Future<void> _runLoopPc(
    StressSettings settings,
    List<StressCaseSpec> cases,
  ) async {
    try {
      await _disconnectAndIdle();

      bool shouldStopOnFail = false;
      for (int cycle = 1; cycle <= settings.cycles; cycle++) {
        _throwIfStopRequested();
        state = state.copyWith(
          activeCycle: cycle,
          activeCaseIndex: 0,
          activeCaseLabel: 'Preparing connection',
          message: 'Cycle $cycle preparing',
        );

        final connectFailure = await _prepareCycleConnection(
          settings,
          forceReconnect: settings.reconnectEachCycle || !_bothConnected(),
        );
        if (connectFailure != null) {
          final record = _buildSetupFailureRecord(cycle, connectFailure);
          _pushRecord(record);
          state = state.copyWith(
            doneCycles: cycle,
            activeCaseIndex: null,
            activeCaseLabel: null,
            message: 'Cycle $cycle setup failed: ${connectFailure.code}',
          );
          shouldStopOnFail = settings.stopOnFail;
          if (shouldStopOnFail) {
            break;
          }
          continue;
        }

        bool cycleFailed = false;
        for (int index = 0; index < cases.length; index++) {
          _throwIfStopRequested();
          final spec = cases[index];
          state = state.copyWith(
            activeCycle: cycle,
            activeCaseIndex: index + 1,
            activeCaseLabel: spec.summary,
            message: 'Cycle $cycle case ${index + 1}/${cases.length}',
          );
          final record = await _runCase(
            cycle: cycle,
            caseIndex: index + 1,
            spec: spec,
            settings: settings,
          );
          _pushRecord(record);
          if (record.result == 'FAIL') {
            cycleFailed = true;
            if (settings.stopOnFail) {
              shouldStopOnFail = true;
              break;
            }
          }
        }

        if (settings.reconnectEachCycle || cycleFailed) {
          await _disconnectAndIdle();
        }

        state = state.copyWith(
          doneCycles: cycle,
          activeCaseIndex: null,
          activeCaseLabel: null,
          message: cycleFailed
              ? 'Cycle $cycle finished with failures'
              : 'Cycle $cycle passed',
        );

        if (shouldStopOnFail) {
          break;
        }
      }

      await _disconnectAndIdle();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: _stopRequested ? StressRunStatus.stopped : StressRunStatus.done,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message:
            _stopRequested ? 'Stress sweep stopped' : 'Stress sweep finished',
      );
      if (reportPaths != null) {
        _appendLog('[STRESS] report ${reportPaths.$1}');
        _appendLog('[STRESS] summary ${reportPaths.$2}');
      }
    } on _StopRequested {
      await _disconnectAndIdle();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: StressRunStatus.stopped,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message: 'Stress sweep stopped',
      );
    } catch (e, st) {
      _log.e('stress sweep failed', error: e, stackTrace: st);
      await _disconnectAndIdle();
      state = state.copyWith(
        status: StressRunStatus.error,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        message: e.toString(),
      );
      _appendLog('[STRESS] error: $e');
    }
  }

  Future<void> _runLoopMcu(
    StressSettings settings,
    List<StressCaseSpec> cases,
  ) async {
    try {
      await _disconnectAndIdle();
      _mcu.clearStateHistory();
      final ready = await _mcu.ensureReady();
      if (!ready) {
        state = state.copyWith(
          status: StressRunStatus.failed,
          message: _ref.read(mcuSerialProvider).message ??
              'MCU serial is not ready.',
        );
        return;
      }

      final caseSessions = _buildMcuCaseSessions(settings, cases);
      final totalCaseCycles = settings.cycles * caseSessions.length;
      final maxCasesPerSession = caseSessions.fold<int>(
        0,
        (max, session) => session.length > max ? session.length : max,
      );
      final effectiveConnectWindowMs = _effectiveMcuConnectWindowMs(
        settings,
        maxCasesPerSession,
      );
      if (effectiveConnectWindowMs > settings.mcuConnectWindowMs) {
        _appendLog(
          '[STRESS][MCU] connect window extended '
          '${settings.mcuConnectWindowMs}ms -> ${effectiveConnectWindowMs}ms '
          'for startup wave / GATT / battery steps',
        );
      }
      final commands = <(String line, String key)>[
        ('set off ${settings.mcuOffGuardMs}', 'off'),
        ('set ab ${settings.mcuPowerToD5Ms}', 'ab'),
        ('set bs ${settings.mcuD5PulseMs}', 'bs'),
        ('set cw $effectiveConnectWindowMs', 'cw'),
        ('set dw ${settings.mcuDisconnectWindowMs}', 'dw'),
        ('set son ${settings.mcuSensorOnCheck ? 1 : 0}', 'son'),
        ('set sof ${settings.mcuSensorOffCheck ? 1 : 0}', 'sof'),
        ('set stopfail ${settings.stopOnFail ? 1 : 0}', 'stopfail'),
      ];
      for (final command in commands) {
        final event = await _mcu.sendCommandWait(
          command.$1,
          'CONFIG_UPDATED',
          timeout: const Duration(milliseconds: 2500),
          detailContains: command.$2,
        );
        if (event == null) {
          state = state.copyWith(
            status: StressRunStatus.failed,
            message: 'MCU config timeout: ${command.$2}',
          );
          return;
        }
      }

      final started = await _mcu.sendCommandWait(
        'run $totalCaseCycles $effectiveConnectWindowMs ${settings.mcuDisconnectWindowMs}',
        'ENDURANCE_START',
        timeout: const Duration(seconds: 3),
      );
      if (started == null) {
        state = state.copyWith(
          status: StressRunStatus.failed,
          message: 'MCU ENDURANCE_START timeout',
        );
        return;
      }

      var shouldStopOnFail = false;
      var overallSessionIndex = 0;
      for (int cycle = 1; cycle <= settings.cycles; cycle++) {
        _throwIfStopRequested();
        var cycleFailed = false;
        var cycleCaseIndex = 0;
        for (final sessionCases in caseSessions) {
          _throwIfStopRequested();
          overallSessionIndex++;
          final records = await _runCaseSessionMcu(
            cycle: cycle,
            firstCaseIndex: cycleCaseIndex + 1,
            globalSessionIndex: overallSessionIndex,
            globalCaseCount: totalCaseCycles,
            sessionCases: sessionCases,
            settings: settings,
            effectiveConnectWindowMs: effectiveConnectWindowMs,
          );
          cycleCaseIndex += sessionCases.length;
          for (final record in records) {
            _pushRecord(record);
            if (record.result == 'FAIL') {
              cycleFailed = true;
              if (settings.stopOnFail) {
                shouldStopOnFail = true;
                break;
              }
            }
          }
          if (shouldStopOnFail) {
            break;
          }
        }

        state = state.copyWith(
          doneCycles: cycle,
          activeCaseIndex: null,
          activeCaseLabel: null,
          message: cycleFailed
              ? 'MCU cycle $cycle finished with failures'
              : 'MCU cycle $cycle passed',
        );

        if (shouldStopOnFail) {
          await _mcu.sendLine('stop');
          break;
        }
      }

      await _disconnectAndIdle();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: _stopRequested ? StressRunStatus.stopped : StressRunStatus.done,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message: _stopRequested
            ? 'MCU stress sweep stopped'
            : 'MCU stress sweep finished',
      );
    } on _StopRequested {
      await _mcu.sendLine('stop');
      await _disconnectAndIdle();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: StressRunStatus.stopped,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message: 'MCU stress sweep stopped',
      );
    } catch (e, st) {
      _log.e('mcu stress sweep failed', error: e, stackTrace: st);
      await _mcu.sendLine('stop');
      await _disconnectAndIdle();
      state = state.copyWith(
        status: StressRunStatus.error,
        activeCycle: null,
        activeCaseIndex: null,
        activeCaseLabel: null,
        message: e.toString(),
      );
      _appendLog('[STRESS][MCU] error: $e');
    }
  }

  Future<List<StressCaseRecord>> _runCaseSessionMcu({
    required int cycle,
    required int firstCaseIndex,
    required int globalSessionIndex,
    required int globalCaseCount,
    required List<StressCaseSpec> sessionCases,
    required StressSettings settings,
    required int effectiveConnectWindowMs,
  }) async {
    if (sessionCases.isEmpty) {
      return const <StressCaseRecord>[];
    }

    final sessionLogs = <String>[];
    final cycleToken = '$globalSessionIndex/$globalCaseCount';

    void sessionLog(String message) {
      final entry =
          '[MCU CYCLE ${cycle.toString().padLeft(3, '0')} SESSION ${globalSessionIndex.toString().padLeft(3, '0')}] $message';
      sessionLogs.add(entry);
      _appendLog(entry);
    }

    final sessionStartedAt = DateTime.now();

    final cycleStart = await _mcu.waitForState(
      <String>{'CYCLE_START'},
      timeout: const Duration(seconds: 10),
      startIndex: 0,
      detailContains: cycleToken,
    );
    if (cycleStart == null) {
      return _buildImmediateSessionFailures(
        cycle: cycle,
        firstCaseIndex: firstCaseIndex,
        specs: sessionCases,
        startedAt: sessionStartedAt,
        failureClass: 'MCU_COMMAND_TIMEOUT',
        failureDetail:
            'CYCLE_START timeout ($globalSessionIndex/$globalCaseCount)',
        logs: sessionLogs,
      );
    }

    final connectWindowBegin = await _mcu.waitForState(
      <String>{'CONNECT_WINDOW_BEGIN'},
      timeout: Duration(
        milliseconds: settings.mcuOffGuardMs +
            settings.mcuPowerToD5Ms +
            settings.mcuD5PulseMs +
            5000,
      ),
      startIndex: cycleStart.index + 1,
    );
    if (connectWindowBegin == null) {
      return _buildImmediateSessionFailures(
        cycle: cycle,
        firstCaseIndex: firstCaseIndex,
        specs: sessionCases,
        startedAt: sessionStartedAt,
        failureClass: 'MCU_COMMAND_TIMEOUT',
        failureDetail: 'CONNECT_WINDOW_BEGIN timeout',
        logs: sessionLogs,
      );
    }

    String? setupFailureClass;
    String? setupFailureDetail;
    var scanOk = !settings.scanBeforeConnect;
    if (settings.scanBeforeConnect) {
      final scanResult = await _scanAssignedDevices();
      scanOk = scanResult.ok;
      if (!scanOk) {
        setupFailureClass = 'ADV_NOT_FOUND';
        setupFailureDetail = scanResult.detail;
        sessionLog('scan failed: ${scanResult.detail}');
      } else {
        sessionLog(
          'scan ok RSSI A=${_formatRssi(_lastScanRssiA)} B=${_formatRssi(_lastScanRssiB)}',
        );
      }
    }

    var connectOk = false;
    if (scanOk) {
      await _stock.connectBoth();
      connectOk = await _stock.waitForBothConnected(_connectTimeout);
      if (!connectOk) {
        setupFailureClass = 'CONNECT_FAILED';
        setupFailureDetail = 'Timed out waiting for both devices to connect.';
        sessionLog('connect failed');
      } else {
        sessionLog('connect ok');
        if (settings.settleMs > 0) {
          await _interruptibleDelay(Duration(milliseconds: settings.settleMs));
        }
        final startupError = await _runStartupWaveAll();
        if (startupError != null) {
          setupFailureClass = 'LED_WRITE_FAIL';
          setupFailureDetail = startupError;
          sessionLog('startup wave failed: $startupError');
        } else {
          sessionLog('startup wave ok');
        }
      }
    }

    if (connectOk &&
        setupFailureClass == null &&
        settings.verifyGattOnConnect) {
      for (final side in StockSide.values) {
        final profileError = await _stock.verifyGattProfile(
          side,
          requireBatteryCharacteristic: settings.readBatteryEachCase,
        );
        if (profileError != null) {
          setupFailureClass = 'PROFILE_MISSING';
          setupFailureDetail = profileError;
          sessionLog('gatt failed: $profileError');
          break;
        }
      }
    }

    final records = <StressCaseRecord>[];
    if (setupFailureClass != null) {
      records.addAll(
        _buildImmediateSessionFailures(
          cycle: cycle,
          firstCaseIndex: firstCaseIndex,
          specs: sessionCases,
          startedAt: sessionStartedAt,
          failureClass: setupFailureClass,
          failureDetail: setupFailureDetail ?? setupFailureClass,
          logs: sessionLogs,
        ),
      );
    } else {
      for (int offset = 0; offset < sessionCases.length; offset++) {
        _throwIfStopRequested();
        final spec = sessionCases[offset];
        final caseIndex = firstCaseIndex + offset;
        state = state.copyWith(
          activeCycle: cycle,
          activeCaseIndex: caseIndex,
          activeCaseLabel: spec.summary,
          message:
              'MCU cycle $cycle case $caseIndex/${state.totalCasesPerCycle}',
        );

        final caseLogs = <String>[];

        void caseLog(String message) {
          final entry =
              '[MCU CYCLE ${cycle.toString().padLeft(3, '0')} CASE ${caseIndex.toString().padLeft(3, '0')}] $message';
          caseLogs.add(entry);
          _appendLog(entry);
        }

        final startedAt = DateTime.now();
        var result = 'PASS';
        var failureClass = 'PASS';
        var failureDetail = '';
        double? batteryA;
        double? batteryB;

        try {
          caseLog('apply ${spec.summary}');
          await _applyCase(spec);
          if (settings.caseHoldMs > 0) {
            await _interruptibleDelay(
              Duration(milliseconds: settings.caseHoldMs),
            );
          }
          if (settings.readBatteryEachCase) {
            final batteryResult = await _readBatteries();
            batteryA = batteryResult.a;
            batteryB = batteryResult.b;
            if (batteryResult.failure != null) {
              result = 'FAIL';
              failureClass = batteryResult.failure!.code;
              failureDetail = batteryResult.failure!.detail;
              caseLog('battery failed: $failureDetail');
            } else {
              caseLog(
                'battery ok A=${batteryA?.toStringAsFixed(3)} B=${batteryB?.toStringAsFixed(3)}',
              );
            }
          }
        } on _StopRequested {
          rethrow;
        } catch (e, st) {
          _log.w('mcu apply failed', error: e, stackTrace: st);
          result = 'FAIL';
          failureClass = 'APPLY_FAILED';
          failureDetail = e.toString();
          caseLog('apply failed: $failureDetail');
        } finally {
          await _setAllIdleBestEffort();
          if (offset < sessionCases.length - 1 && settings.caseGapMs > 0) {
            await _interruptibleDelay(
              Duration(milliseconds: settings.caseGapMs),
            );
          }
        }

        final endedAt = DateTime.now();
        final duration = endedAt.difference(startedAt);
        caseLog(
          '$result ${spec.summary} ${duration.inMilliseconds}ms class=$failureClass',
        );
        records.add(
          StressCaseRecord(
            cycle: cycle,
            caseIndex: caseIndex,
            startedAt: startedAt,
            endedAt: endedAt,
            result: result,
            failureClass: failureClass,
            failureDetail: failureDetail,
            feature: spec.featureLabel,
            scope: spec.scopeLabel,
            zone: spec.zoneLabel,
            summary: spec.summary,
            colorHex: spec.color == null ? '' : _colorToHex(spec.color!),
            brightness: spec.brightness,
            intervalMs: spec.intervalMs,
            rssiA: _lastScanRssiA,
            rssiB: _lastScanRssiB,
            batteryA: batteryA,
            batteryB: batteryB,
            duration: duration,
            lastLog: caseLogs.join(' || '),
          ),
        );

        if (result == 'FAIL' && settings.stopOnFail) {
          break;
        }
      }
    }

    await _disconnectAndIdle();

    final connectWindowEnd = await _mcu.waitForState(
      <String>{'CONNECT_WINDOW_END'},
      timeout: Duration(milliseconds: effectiveConnectWindowMs + 2500),
      startIndex: connectWindowBegin.index + 1,
    );
    if (connectWindowEnd == null) {
      sessionLog('CONNECT_WINDOW_END timeout');
      return _applySessionFailureToLastRecord(
        records,
        failureClass: 'MCU_COMMAND_TIMEOUT',
        failureDetail: 'CONNECT_WINDOW_END timeout',
      );
    }

    final disconnectWindowBegin = await _mcu.waitForState(
      <String>{'DISCONNECT_WINDOW_BEGIN'},
      timeout: Duration(milliseconds: settings.mcuDisconnectWindowMs + 2500),
      startIndex: connectWindowEnd.index + 1,
    );
    if (disconnectWindowBegin == null) {
      sessionLog('DISCONNECT_WINDOW_BEGIN timeout');
      return _applySessionFailureToLastRecord(
        records,
        failureClass: 'MCU_COMMAND_TIMEOUT',
        failureDetail: 'DISCONNECT_WINDOW_BEGIN timeout',
      );
    }

    final disconnectWindowEnd = await _mcu.waitForState(
      <String>{'DISCONNECT_WINDOW_END'},
      timeout: Duration(milliseconds: settings.mcuDisconnectWindowMs + 2500),
      startIndex: disconnectWindowBegin.index + 1,
    );
    if (disconnectWindowEnd == null) {
      sessionLog('DISCONNECT_WINDOW_END timeout');
      return _applySessionFailureToLastRecord(
        records,
        failureClass: 'MCU_COMMAND_TIMEOUT',
        failureDetail: 'DISCONNECT_WINDOW_END timeout',
      );
    }

    final mcuEvents = _ref
        .read(mcuSerialProvider)
        .events
        .skip(cycleStart.index)
        .toList(growable: false);
    final mcuCycleFailed = mcuEvents.any(
      (event) =>
          event.state == 'CYCLE_FAIL' ||
          event.state == 'SENSOR_ON_NG' ||
          event.state == 'SENSOR_OFF_NG',
    );
    if (mcuCycleFailed) {
      final failureDetail = mcuEvents
          .where((event) => event.state == 'CYCLE_FAIL')
          .map((event) => event.detail)
          .join(' / ');
      final detail = failureDetail.isEmpty
          ? 'MCU reported sequence failure.'
          : failureDetail;
      sessionLog('MCU sequence fail: $detail');
      return _applySessionFailureToLastRecord(
        records,
        failureClass: 'MCU_SEQUENCE_FAIL',
        failureDetail: detail,
      );
    }

    final disconnectOk = _allDisconnected();
    if (!disconnectOk) {
      sessionLog('disconnect incomplete before next MCU cycle');
      return _applySessionFailureToLastRecord(
        records,
        failureClass: 'DISCONNECT_INCOMPLETE',
        failureDetail: 'Devices did not fully disconnect before next cycle.',
      );
    }

    return records;
  }

  List<StressCaseRecord> _buildImmediateSessionFailures({
    required int cycle,
    required int firstCaseIndex,
    required List<StressCaseSpec> specs,
    required DateTime startedAt,
    required String failureClass,
    required String failureDetail,
    required List<String> logs,
  }) {
    final records = <StressCaseRecord>[];
    for (int offset = 0; offset < specs.length; offset++) {
      records.add(
        _buildImmediateCaseFailure(
          cycle: cycle,
          caseIndex: firstCaseIndex + offset,
          spec: specs[offset],
          startedAt: startedAt,
          failureClass: failureClass,
          failureDetail: failureDetail,
          logs: logs,
        ),
      );
    }
    return records;
  }

  List<StressCaseRecord> _applySessionFailureToLastRecord(
    List<StressCaseRecord> records, {
    required String failureClass,
    required String failureDetail,
  }) {
    if (records.isEmpty) {
      return records;
    }
    final last = records.last;
    if (last.result == 'FAIL') {
      return records;
    }
    final updatedLast = StressCaseRecord(
      cycle: last.cycle,
      caseIndex: last.caseIndex,
      startedAt: last.startedAt,
      endedAt: last.endedAt,
      result: 'FAIL',
      failureClass: failureClass,
      failureDetail: failureDetail,
      feature: last.feature,
      scope: last.scope,
      zone: last.zone,
      summary: last.summary,
      colorHex: last.colorHex,
      brightness: last.brightness,
      intervalMs: last.intervalMs,
      rssiA: last.rssiA,
      rssiB: last.rssiB,
      batteryA: last.batteryA,
      batteryB: last.batteryB,
      duration: last.duration,
      lastLog: last.lastLog,
    );
    return <StressCaseRecord>[
      ...records.take(records.length - 1),
      updatedLast,
    ];
  }

  Future<_FailureInfo?> _prepareCycleConnection(
    StressSettings settings, {
    required bool forceReconnect,
  }) async {
    if (forceReconnect) {
      await _disconnectAndIdle();
      if (settings.scanBeforeConnect) {
        final scanResult = await _scanAssignedDevices();
        if (!scanResult.ok) {
          return _FailureInfo('ADV_NOT_FOUND', scanResult.detail);
        }
        _appendLog(
          '[SCAN] ok RSSI A=${_formatRssi(_lastScanRssiA)} '
          'B=${_formatRssi(_lastScanRssiB)}',
        );
      }
      await _stock.connectBoth();
      final connected = await _stock.waitForBothConnected(_connectTimeout);
      if (!connected) {
        return const _FailureInfo(
          'CONNECT_FAILED',
          'Timed out waiting for both devices to connect.',
        );
      }
      if (settings.settleMs > 0) {
        await _interruptibleDelay(Duration(milliseconds: settings.settleMs));
      }
    } else if (!_bothConnected()) {
      await _stock.connectBoth();
      final connected = await _stock.waitForBothConnected(_connectTimeout);
      if (!connected) {
        return const _FailureInfo(
          'CONNECT_FAILED',
          'Timed out while recovering both links.',
        );
      }
    }

    if (settings.verifyGattOnConnect) {
      for (final side in StockSide.values) {
        final profileError = await _stock.verifyGattProfile(
          side,
          requireBatteryCharacteristic: settings.readBatteryEachCase,
        );
        if (profileError != null) {
          return _FailureInfo('PROFILE_MISSING', profileError);
        }
      }
    }
    return null;
  }

  Future<StressCaseRecord> _runCase({
    required int cycle,
    required int caseIndex,
    required StressCaseSpec spec,
    required StressSettings settings,
  }) async {
    final cycleLogs = <String>[];

    void caseLog(String message) {
      final entry =
          '[CYCLE ${cycle.toString().padLeft(3, '0')} CASE ${caseIndex.toString().padLeft(3, '0')}] $message';
      cycleLogs.add(entry);
      _appendLog(entry);
    }

    final startedAt = DateTime.now();
    String result = 'PASS';
    String failureClass = 'PASS';
    String failureDetail = '';
    double? batteryA;
    double? batteryB;

    try {
      final reconnectFailure = await _prepareCycleConnection(
        settings,
        forceReconnect: false,
      );
      if (reconnectFailure != null) {
        result = 'FAIL';
        failureClass = reconnectFailure.code;
        failureDetail = reconnectFailure.detail;
        caseLog('prepare failed: ${reconnectFailure.detail}');
      } else {
        caseLog('apply ${spec.summary}');
        await _applyCase(spec);
        if (settings.caseHoldMs > 0) {
          await _interruptibleDelay(
            Duration(milliseconds: settings.caseHoldMs),
          );
        }
        if (settings.readBatteryEachCase) {
          final batteryResult = await _readBatteries();
          batteryA = batteryResult.a;
          batteryB = batteryResult.b;
          if (batteryResult.failure != null) {
            result = 'FAIL';
            failureClass = batteryResult.failure!.code;
            failureDetail = batteryResult.failure!.detail;
            caseLog('battery failed: $failureDetail');
          } else {
            caseLog(
              'battery ok A=${batteryA?.toStringAsFixed(3)} B=${batteryB?.toStringAsFixed(3)}',
            );
          }
        }
      }
    } on _StopRequested {
      rethrow;
    } catch (e, st) {
      _log.w('stress case failed', error: e, stackTrace: st);
      result = 'FAIL';
      failureClass = 'APPLY_FAILED';
      failureDetail = e.toString();
      caseLog('apply failed: $failureDetail');
    } finally {
      await _setAllIdleBestEffort();
      if (settings.caseGapMs > 0) {
        await _interruptibleDelay(Duration(milliseconds: settings.caseGapMs));
      }
    }

    final endedAt = DateTime.now();
    final duration = endedAt.difference(startedAt);
    caseLog(
      '$result ${spec.summary} ${duration.inMilliseconds}ms class=$failureClass',
    );

    return StressCaseRecord(
      cycle: cycle,
      caseIndex: caseIndex,
      startedAt: startedAt,
      endedAt: endedAt,
      result: result,
      failureClass: failureClass,
      failureDetail: failureDetail,
      feature: spec.featureLabel,
      scope: spec.scopeLabel,
      zone: spec.zoneLabel,
      summary: spec.summary,
      colorHex: spec.color == null ? '' : _colorToHex(spec.color!),
      brightness: spec.brightness,
      intervalMs: spec.intervalMs,
      rssiA: _lastScanRssiA,
      rssiB: _lastScanRssiB,
      batteryA: batteryA,
      batteryB: batteryB,
      duration: duration,
      lastLog: cycleLogs.join(' || '),
    );
  }

  Future<void> _applyCase(StressCaseSpec spec) async {
    await _setAllIdleBestEffort();

    final targets = _targetSides(spec.scope);
    for (final side in targets) {
      final deviceId = _deviceId(side);
      if (deviceId == null) {
        throw StateError('Missing device for ${side.name.toUpperCase()}');
      }
      await _led.setOutputEnabled(deviceId, true);
      await _led.setBrightness(deviceId, spec.brightness);
      _ledUi.setOutputEnabled(side, true);
      _ledUi.setBrightness(side, spec.brightness.toDouble());
    }

    switch (spec.feature) {
      case StressFeature.color:
        await _applyColorCase(spec, targets);
        break;
      case StressFeature.heartbeat:
        await _applyHeartbeatCase(spec, targets);
        break;
      case StressFeature.rainbow:
        await _applyRainbowCase(spec, targets);
        break;
    }
  }

  Future<void> _applyColorCase(
    StressCaseSpec spec,
    List<StockSide> targets,
  ) async {
    final color = spec.color ?? Colors.white;
    for (final side in targets) {
      final deviceId = _deviceId(side)!;
      final topColor =
          (spec.zone == ColorZone.top || spec.zone == ColorZone.both)
              ? color
              : Colors.black;
      final bottomColor =
          (spec.zone == ColorZone.bottom || spec.zone == ColorZone.both)
              ? color
              : Colors.black;
      await _led.setTopColor(deviceId: deviceId, side: side, color: topColor);
      await _led.setBottomColor(
        deviceId: deviceId,
        side: side,
        color: bottomColor,
      );
      _ledUi.setSegmentColor(side, ColorZone.top, topColor);
      _ledUi.setSegmentColor(side, ColorZone.bottom, bottomColor);
      _ledUi.setSegmentMode(
        side,
        ColorZone.top,
        topColor == Colors.black ? LedMode.off : LedMode.color,
      );
      _ledUi.setSegmentMode(
        side,
        ColorZone.bottom,
        bottomColor == Colors.black ? LedMode.off : LedMode.color,
      );
    }
  }

  Future<void> _applyHeartbeatCase(
    StressCaseSpec spec,
    List<StockSide> targets,
  ) async {
    final color = spec.color ?? const Color(0xFFFF3B30);
    final interval = Duration(milliseconds: spec.intervalMs ?? 600);
    for (final side in targets) {
      final deviceId = _deviceId(side)!;
      _ledUi.setHeartbeatColor(side, color);
      _ledUi.setHeartbeatInterval(side, interval.inMilliseconds);
      _ledUi.setSegmentColor(side, ColorZone.both, color);
      _heartbeat.start(side, deviceId, interval: interval);
    }
  }

  Future<void> _applyRainbowCase(
    StressCaseSpec spec,
    List<StockSide> targets,
  ) async {
    final intervalMs = spec.intervalMs ?? 40;
    for (final side in targets) {
      final deviceId = _deviceId(side)!;
      await _led.startRainbow(deviceId, intervalMs: intervalMs);
      _ledUi.setSegmentMode(side, ColorZone.both, LedMode.rainbow);
    }
  }

  Future<void> _setAllIdleBestEffort() async {
    final stockState = _ref.read(stockProvider);
    for (final side in StockSide.values) {
      final sideState = side == StockSide.a ? stockState.a : stockState.b;
      final deviceId = sideState.device?.id;
      _heartbeat.stop(
        side,
        deviceId: deviceId,
        sendOff: false,
        resetMode: true,
      );
      if (deviceId != null &&
          sideState.status == DeviceConnectionState.connected) {
        try {
          await _led.applyIdleState(deviceId);
        } catch (e, st) {
          _log.w('idle failed on ${side.name}', error: e, stackTrace: st);
        }
      }
      _ledUi.setOutputEnabled(side, false);
      _ledUi.setSegmentColor(side, ColorZone.both, Colors.black);
      _ledUi.setSegmentMode(side, ColorZone.both, LedMode.off);
    }
  }

  Future<String?> _runStartupWaveAll() async {
    final stockState = _ref.read(stockProvider);
    final stepMs = (_startupCycleMs / _startupPalette.length)
        .round()
        .clamp(60, 5000);

    try {
      final targets = <({StockSide side, String deviceId, int brightness})>[];
      for (final side in StockSide.values) {
        final sideState = side == StockSide.a ? stockState.a : stockState.b;
        final device = sideState.device;
        if (device == null ||
            sideState.status != DeviceConnectionState.connected) {
          return 'Missing device ${side.name.toUpperCase()}';
        }
        targets.add((
          side: side,
          deviceId: device.id,
          brightness: _fixedBrightness,
        ));
      }

      for (final target in targets) {
        _heartbeat.stop(
          target.side,
          deviceId: target.deviceId,
          sendOff: false,
          resetMode: false,
        );
      }
      await Future.wait(
        targets.map((target) async {
          try {
            await _led.stopRainbow(target.deviceId);
          } catch (_) {
            // Keep startup wave best-effort aligned with the main app flow.
          }
          await _led.setOutputEnabled(target.deviceId, true);
          await _led.setBrightness(target.deviceId, target.brightness);
        }),
      );

      for (final color in _startupPalette) {
        _throwIfStopRequested();
        await Future.wait(
          targets.map((target) async {
            await _led.setTopColor(
              deviceId: target.deviceId,
              side: target.side,
              color: color,
            );
            await _led.setBottomColor(
              deviceId: target.deviceId,
              side: target.side,
              color: color,
            );
          }),
        );
        await _interruptibleDelay(Duration(milliseconds: stepMs));
      }
      final last = _startupPalette.last;
      for (final target in targets) {
        _ledUi.setOutputEnabled(target.side, true);
        _ledUi.setBrightness(target.side, target.brightness.toDouble());
        _ledUi.setSegmentColor(target.side, ColorZone.both, last);
        _ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.color);
      }
      return null;
    } on _StopRequested {
      rethrow;
    } catch (e, st) {
      _log.w('startup wave failed', error: e, stackTrace: st);
      return e.toString();
    }
  }

  Future<void> _disconnectAndIdle() async {
    await _setAllIdleBestEffort();
    await _stock.disconnectBoth();
    await _stock.waitForBothDisconnected(_postRunDisconnectTimeout);
  }

  Future<_BatteryResult> _readBatteries() async {
    final a = await _stock.readBattery(StockSide.a);
    final b = await _stock.readBattery(StockSide.b);
    if (a == null || a <= 0 || b == null || b <= 0) {
      return _BatteryResult(
        a: a,
        b: b,
        failure: _FailureInfo(
          'BATTERY_READ_FAIL',
          'Battery read failed: A=${a?.toStringAsFixed(3) ?? 'null'} B=${b?.toStringAsFixed(3) ?? 'null'}',
        ),
      );
    }
    return _BatteryResult(a: a, b: b);
  }

  Future<_PhaseResult> _scanAssignedDevices() async {
    final stockState = _ref.read(stockProvider);
    final expectedA = stockState.a.device;
    final expectedB = stockState.b.device;
    if (expectedA == null || expectedB == null) {
      _lastScanRssiA = null;
      _lastScanRssiB = null;
      return const _PhaseResult(false, 'Devices A/B are not assigned');
    }

    final found = <StockSide, bool>{StockSide.a: false, StockSide.b: false};
    int? rssiA;
    int? rssiB;
    Object? error;
    StackTrace? stackTrace;
    final completer = Completer<void>();

    _lastScanRssiA = null;
    _lastScanRssiB = null;
    await _scanSubscription?.cancel();
    _scanSubscription = _client.scan(nameHint: Env.nameHint).listen(
      (device) {
        if (_matchesDevice(device, expectedA)) {
          found[StockSide.a] = true;
          rssiA = rssiA == null || device.rssi > rssiA! ? device.rssi : rssiA;
        }
        if (_matchesDevice(device, expectedB)) {
          found[StockSide.b] = true;
          rssiB = rssiB == null || device.rssi > rssiB! ? device.rssi : rssiB;
        }
        if (found.values.every((value) => value) && !completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (e, st) {
        error = e;
        stackTrace = st;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await Future.any<void>(<Future<void>>[
        completer.future,
        Future<void>.delayed(_scanWindow),
      ]);
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    _throwIfStopRequested();
    _lastScanRssiA = rssiA;
    _lastScanRssiB = rssiB;

    if (error != null) {
      _log.w('scan failed', error: error, stackTrace: stackTrace);
      return _PhaseResult(false, error.toString(), rssiA: rssiA, rssiB: rssiB);
    }
    if (!found[StockSide.a]! || !found[StockSide.b]!) {
      return _PhaseResult(
        false,
        'A=${found[StockSide.a]! ? 'OK' : 'NG'} B=${found[StockSide.b]! ? 'OK' : 'NG'}',
        rssiA: rssiA,
        rssiB: rssiB,
      );
    }
    return _PhaseResult(true, 'OK', rssiA: rssiA, rssiB: rssiB);
  }

  bool _matchesDevice(DiscoveredDevice discovered, BleDevice expected) {
    if (discovered.id == expected.id) {
      return true;
    }
    final expectedName = expected.name?.trim();
    final discoveredName = discovered.name.trim();
    if (expectedName == null || expectedName.isEmpty) {
      return false;
    }
    return expectedName == discoveredName;
  }

  int _effectiveMcuConnectWindowMs(
    StressSettings settings,
    int casesPerSession,
  ) {
    var estimatedMs = 1000;
    if (settings.scanBeforeConnect) {
      estimatedMs += _scanWindow.inMilliseconds;
    }
    estimatedMs += 2500;
    estimatedMs += settings.settleMs;
    estimatedMs += 1200;
    if (settings.verifyGattOnConnect) {
      estimatedMs += 1200;
    }
    final effectiveCases = casesPerSession <= 0 ? 1 : casesPerSession;
    for (var index = 0; index < effectiveCases; index++) {
      estimatedMs += 2500;
      estimatedMs += settings.caseHoldMs;
      if (settings.readBatteryEachCase) {
        estimatedMs += 1000;
      }
      if (index < effectiveCases - 1) {
        estimatedMs += settings.caseGapMs;
      }
    }
    if (effectiveCases > 1) {
      estimatedMs += 3000;
    }
    return estimatedMs > settings.mcuConnectWindowMs
        ? estimatedMs
        : settings.mcuConnectWindowMs;
  }

  List<StressCaseSpec> _buildCases(StressSettings settings) {
    switch (settings.sweepPlan) {
      case StressSweepPlan.matrix73:
        return _buildMatrixCases(settings);
      case StressSweepPlan.featureTransition9:
        return _buildFeatureTransitionCases();
    }
  }

  List<StressCaseSpec> _buildMatrixCases(StressSettings settings) {
    final scopes = <StressScope>[
      StressScope.stockA,
      StressScope.stockB,
      if (settings.includeSyncroCases) StressScope.syncro,
    ];
    final cases = <StressCaseSpec>[];

    if (settings.includeColor) {
      for (final scope in scopes) {
        final zones = scope == StressScope.syncro
            ? const <ColorZone>[ColorZone.both]
            : const <ColorZone>[
                ColorZone.top,
                ColorZone.bottom,
                ColorZone.both,
              ];
        for (final zone in zones) {
          for (final brightness in _brightnessLevels) {
            for (final color in _colorPalette) {
              cases.add(
                StressCaseSpec(
                  feature: StressFeature.color,
                  scope: scope,
                  zone: zone,
                  color: color,
                  brightness: brightness,
                  intervalMs: null,
                ),
              );
            }
          }
        }
      }
    }

    if (settings.includeHeartbeat) {
      for (final scope in scopes) {
        for (final brightness in _brightnessLevels) {
          for (final color in _colorPalette) {
            for (final intervalMs in _heartbeatIntervalsMs) {
              cases.add(
                StressCaseSpec(
                  feature: StressFeature.heartbeat,
                  scope: scope,
                  zone: ColorZone.both,
                  color: color,
                  brightness: brightness,
                  intervalMs: intervalMs,
                ),
              );
            }
          }
        }
      }
    }

    if (settings.includeRainbow) {
      for (final scope in scopes) {
        for (final intervalMs in _rainbowIntervalsMs) {
          for (final brightness in _brightnessLevels) {
            cases.add(
              StressCaseSpec(
                feature: StressFeature.rainbow,
                scope: scope,
                zone: ColorZone.both,
                color: null,
                brightness: brightness,
                intervalMs: intervalMs,
              ),
            );
          }
        }
      }
    }

    return cases;
  }

  List<StressCaseSpec> _buildFeatureTransitionCases() {
    final highlightColor = _colorPalette.first;
    return <StressCaseSpec>[
      for (final scope in const <StressScope>[
        StressScope.stockA,
        StressScope.stockB,
        StressScope.syncro,
      ]) ...[
        StressCaseSpec(
          feature: StressFeature.color,
          scope: scope,
          zone: ColorZone.both,
          color: highlightColor,
          brightness: _fixedBrightness,
          intervalMs: null,
        ),
        StressCaseSpec(
          feature: StressFeature.heartbeat,
          scope: scope,
          zone: ColorZone.both,
          color: highlightColor,
          brightness: _fixedBrightness,
          intervalMs: _transitionHeartbeatIntervalMs,
        ),
        StressCaseSpec(
          feature: StressFeature.rainbow,
          scope: scope,
          zone: ColorZone.both,
          color: null,
          brightness: _fixedBrightness,
          intervalMs: _transitionRainbowIntervalMs,
        ),
      ],
    ];
  }

  int _mcuSessionsPerCycle(StressSettings settings, int caseCount) {
    switch (settings.sweepPlan) {
      case StressSweepPlan.matrix73:
        return caseCount;
      case StressSweepPlan.featureTransition9:
        return caseCount == 0 ? 0 : 1;
    }
  }

  List<List<StressCaseSpec>> _buildMcuCaseSessions(
    StressSettings settings,
    List<StressCaseSpec> cases,
  ) {
    switch (settings.sweepPlan) {
      case StressSweepPlan.matrix73:
        return [
          for (final spec in cases) <StressCaseSpec>[spec],
        ];
      case StressSweepPlan.featureTransition9:
        return cases.isEmpty
            ? <List<StressCaseSpec>>[]
            : <List<StressCaseSpec>>[cases];
    }
  }

  StressCaseRecord _buildSetupFailureRecord(int cycle, _FailureInfo failure) {
    final now = DateTime.now();
    return StressCaseRecord(
      cycle: cycle,
      caseIndex: 0,
      startedAt: now,
      endedAt: now,
      result: 'FAIL',
      failureClass: failure.code,
      failureDetail: failure.detail,
      feature: 'SETUP',
      scope: 'SYNCRO',
      zone: 'BOTH',
      summary: 'SETUP FAILURE',
      colorHex: '',
      brightness: 0,
      intervalMs: null,
      rssiA: _lastScanRssiA,
      rssiB: _lastScanRssiB,
      batteryA: null,
      batteryB: null,
      duration: Duration.zero,
      lastLog: failure.detail,
    );
  }

  void _pushRecord(StressCaseRecord record) {
    final nextRecords = <StressCaseRecord>[...state.records, record];
    final nextCounts = <String, int>{...state.failureCounts};
    nextCounts[record.failureClass] =
        (nextCounts[record.failureClass] ?? 0) + 1;

    state = state.copyWith(
      executedCases: state.executedCases + 1,
      passCount: state.passCount + (record.result == 'PASS' ? 1 : 0),
      failCount: state.failCount + (record.result == 'FAIL' ? 1 : 0),
      lastOutcome:
          'cycle ${record.cycle} case ${record.caseIndex} ${record.result} (${record.failureClass})',
      failureCounts: nextCounts,
      records: nextRecords,
      message: record.result == 'PASS'
          ? 'Cycle ${record.cycle} case ${record.caseIndex} passed'
          : 'Cycle ${record.cycle} case ${record.caseIndex} failed: ${record.failureClass}',
    );
  }

  List<StockSide> _targetSides(StressScope scope) {
    switch (scope) {
      case StressScope.stockA:
        return const <StockSide>[StockSide.a];
      case StressScope.stockB:
        return const <StockSide>[StockSide.b];
      case StressScope.syncro:
        return const <StockSide>[StockSide.a, StockSide.b];
    }
  }

  String? _deviceId(StockSide side) {
    final stockState = _ref.read(stockProvider);
    final device =
        side == StockSide.a ? stockState.a.device : stockState.b.device;
    return device?.id;
  }

  StressCaseRecord _buildImmediateCaseFailure({
    required int cycle,
    required int caseIndex,
    required StressCaseSpec spec,
    required DateTime startedAt,
    required String failureClass,
    required String failureDetail,
    required List<String> logs,
  }) {
    final endedAt = DateTime.now();
    return StressCaseRecord(
      cycle: cycle,
      caseIndex: caseIndex,
      startedAt: startedAt,
      endedAt: endedAt,
      result: 'FAIL',
      failureClass: failureClass,
      failureDetail: failureDetail,
      feature: spec.featureLabel,
      scope: spec.scopeLabel,
      zone: spec.zoneLabel,
      summary: spec.summary,
      colorHex: spec.color == null ? '' : _colorToHex(spec.color!),
      brightness: spec.brightness,
      intervalMs: spec.intervalMs,
      rssiA: _lastScanRssiA,
      rssiB: _lastScanRssiB,
      batteryA: null,
      batteryB: null,
      duration: endedAt.difference(startedAt),
      lastLog: logs.join(' || '),
    );
  }

  bool _bothConnected() {
    final stockState = _ref.read(stockProvider);
    return stockState.a.status == DeviceConnectionState.connected &&
        stockState.b.status == DeviceConnectionState.connected;
  }

  bool _allDisconnected() {
    final stockState = _ref.read(stockProvider);
    return stockState.a.status == DeviceConnectionState.disconnected &&
        stockState.b.status == DeviceConnectionState.disconnected;
  }

  Future<(String, String)?> _exportReports() async {
    if (state.records.isEmpty) {
      return null;
    }

    final directory = await _resolveReportDirectory();
    final stamp = _timestampForFile(DateTime.now());
    final detailPath =
        '${directory.path}${Platform.pathSeparator}stress_report_$stamp.csv';
    final summaryPath =
        '${directory.path}${Platform.pathSeparator}stress_report_summary_$stamp.csv';

    final detailBuffer = StringBuffer()
      ..writeln(
        _csvRow(const <Object?>[
          'cycle',
          'case_index',
          'start_iso',
          'end_iso',
          'duration_ms',
          'result',
          'failure_class',
          'failure_detail',
          'feature',
          'scope',
          'zone',
          'summary',
          'color_hex',
          'brightness',
          'interval_ms',
          'rssi_a_dbm',
          'rssi_b_dbm',
          'battery_a_v',
          'battery_b_v',
          'last_log',
        ]),
      );

    for (final record in state.records) {
      detailBuffer.writeln(
        _csvRow(<Object?>[
          record.cycle,
          record.caseIndex,
          _timestampIso(record.startedAt),
          _timestampIso(record.endedAt),
          record.duration.inMilliseconds,
          record.result,
          record.failureClass,
          record.failureDetail,
          record.feature,
          record.scope,
          record.zone,
          record.summary,
          record.colorHex,
          record.brightness,
          record.intervalMs,
          record.rssiA,
          record.rssiB,
          record.batteryA?.toStringAsFixed(3),
          record.batteryB?.toStringAsFixed(3),
          record.lastLog,
        ]),
      );
    }

    final sortedFailures = state.failureCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final summaryBuffer = StringBuffer()
      ..writeln(_csvRow(const <Object?>['failure_class', 'count']));
    for (final item in sortedFailures) {
      summaryBuffer.writeln(_csvRow(<Object?>[item.key, item.value]));
    }
    summaryBuffer.writeln(
      _csvRow(<Object?>['TOTAL_CASES', state.records.length]),
    );
    summaryBuffer.writeln(_csvRow(<Object?>['PASS', state.passCount]));
    summaryBuffer.writeln(_csvRow(<Object?>['FAIL', state.failCount]));
    summaryBuffer.writeln(
      _csvRow(<Object?>[
        'PASS_RATE(%)',
        state.records.isEmpty
            ? '0.00'
            : ((state.passCount / state.records.length) * 100).toStringAsFixed(
                2,
              ),
      ]),
    );

    await File(detailPath).writeAsString(detailBuffer.toString());
    await File(summaryPath).writeAsString(summaryBuffer.toString());
    return (detailPath, summaryPath);
  }

  Future<Directory> _resolveReportDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${baseDir.path}${Platform.pathSeparator}stress_reports',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _interruptibleDelay(Duration duration) async {
    if (duration <= Duration.zero) {
      return;
    }
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      _throwIfStopRequested();
      final remaining = deadline.difference(DateTime.now());
      final chunk = remaining > const Duration(milliseconds: 100)
          ? const Duration(milliseconds: 100)
          : remaining;
      await Future<void>.delayed(chunk);
    }
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  void _throwIfStopRequested() {
    if (_stopRequested) {
      throw const _StopRequested();
    }
  }

  void _appendLog(String message) {
    final timestamp = _timestampIso(DateTime.now());
    final line = '$timestamp $message';
    final nextLogs = <String>[...state.logs, line];
    if (nextLogs.length > _maxLogs) {
      nextLogs.removeRange(0, nextLogs.length - _maxLogs);
    }
    state = state.copyWith(logs: nextLogs);
  }

  String _csvRow(List<Object?> values) {
    return values.map((value) {
      final text = '${value ?? ''}';
      final escaped = text.replaceAll('"', '""');
      if (escaped.contains(',') ||
          escaped.contains('"') ||
          escaped.contains('\n') ||
          escaped.contains('\r')) {
        return '"$escaped"';
      }
      return escaped;
    }).join(',');
  }

String _timestampIso(DateTime dateTime) {
  return dateTime.toIso8601String();
}

String _formatRssi(int? value) {
  return value == null ? '--' : '${value}dBm';
}

String _timestampForFile(DateTime dateTime) {
  final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}

class _PhaseResult {
  final bool ok;
  final String detail;
  final int? rssiA;
  final int? rssiB;

  const _PhaseResult(this.ok, this.detail, {this.rssiA, this.rssiB});
}

class _FailureInfo {
  final String code;
  final String detail;

  const _FailureInfo(this.code, this.detail);
}

class _BatteryResult {
  final double? a;
  final double? b;
  final _FailureInfo? failure;

  const _BatteryResult({required this.a, required this.b, this.failure});
}

class _StopRequested implements Exception {
  const _StopRequested();
}

String _colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
