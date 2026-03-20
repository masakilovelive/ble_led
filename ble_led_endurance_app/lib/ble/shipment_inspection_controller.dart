import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;
import 'package:package_info_plus/package_info_plus.dart';
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

enum ShipmentRunStatus {
  idle,
  running,
  awaitingOperator,
  stopped,
  done,
  failed,
  error
}

enum ShipmentStepStatus {
  pending,
  running,
  awaitingOperator,
  pass,
  fail,
  skipped
}

enum ShipmentOperatorDecision { pass, fail, skip }

enum ShipmentStepKind {
  bleConnect,
  ledColor,
  heartbeat,
  rainbow,
  batteryRead,
  appRestart,
  finalReconnect,
  minimumStartupVoltage,
  recordCheck,
  visualInspect,
  acceleration,
}

extension ShipmentStepKindText on ShipmentStepKind {
  String get title {
    switch (this) {
      case ShipmentStepKind.bleConnect:
        return 'BLE接続確認';
      case ShipmentStepKind.ledColor:
        return 'LED色確認';
      case ShipmentStepKind.heartbeat:
        return 'heartbeat確認';
      case ShipmentStepKind.rainbow:
        return 'rainbow確認';
      case ShipmentStepKind.batteryRead:
        return 'battery電圧読み取り';
      case ShipmentStepKind.appRestart:
        return 'アプリ再起動';
      case ShipmentStepKind.finalReconnect:
        return '最終再接続確認';
      case ShipmentStepKind.minimumStartupVoltage:
        return '最低起動電圧';
      case ShipmentStepKind.recordCheck:
        return '記録確認';
      case ShipmentStepKind.visualInspect:
        return '外観検査';
      case ShipmentStepKind.acceleration:
        return 'acceleration確認';
    }
  }

  String get description {
    switch (this) {
      case ShipmentStepKind.bleConnect:
        return 'Android で scan / connect を行い、RSSI と接続時間を確認します。';
      case ShipmentStepKind.ledColor:
        return 'R / G / B / White を順に表示して目視確認します。';
      case ShipmentStepKind.heartbeat:
        return 'heartbeat を表示し、正常点滅を確認します。';
      case ShipmentStepKind.rainbow:
        return 'rainbow を表示し、色遷移を確認します。';
      case ShipmentStepKind.batteryRead:
        return 'battery 電圧の読み取りと下限判定を行います。';
      case ShipmentStepKind.appRestart:
        return 'MCU power cycle を行い、再起動相当動作を確認します。';
      case ShipmentStepKind.finalReconnect:
        return '再接続後に color コマンドが通ることを確認します。';
      case ShipmentStepKind.minimumStartupVoltage:
        return '低電圧治具での起動可否を検査員が確認します。';
      case ShipmentStepKind.recordCheck:
        return '検査記録に必要な入力値と report id を確認します。';
      case ShipmentStepKind.visualInspect:
        return '傷・汚れ・実装異常・発光異常を目視確認します。';
      case ShipmentStepKind.acceleration:
        return 'acceleration 動作を有効にして反応を確認します。';
    }
  }

  bool get requiresOperator {
    switch (this) {
      case ShipmentStepKind.bleConnect:
      case ShipmentStepKind.batteryRead:
      case ShipmentStepKind.appRestart:
      case ShipmentStepKind.finalReconnect:
      case ShipmentStepKind.recordCheck:
        return false;
      case ShipmentStepKind.ledColor:
      case ShipmentStepKind.heartbeat:
      case ShipmentStepKind.rainbow:
      case ShipmentStepKind.minimumStartupVoltage:
      case ShipmentStepKind.visualInspect:
      case ShipmentStepKind.acceleration:
        return true;
    }
  }

  String get operatorPrompt {
    switch (this) {
      case ShipmentStepKind.ledColor:
        return 'R / G / B / White がすべて正常点灯したら PASS を押してください。';
      case ShipmentStepKind.heartbeat:
        return '5秒以上正常点滅していることを確認して PASS / FAIL を選択してください。';
      case ShipmentStepKind.rainbow:
        return '1サイクル以上動作し、停止や欠色がなければ PASS を押してください。';
      case ShipmentStepKind.minimumStartupVoltage:
        return '低電圧条件での起動可否を確認後、PASS / FAIL / SKIP を選択してください。';
      case ShipmentStepKind.visualInspect:
        return '傷・汚れ・実装異常・発光異常がなければ PASS を押してください。';
      case ShipmentStepKind.acceleration:
        return '本体を動かし、acceleration の反応が正常なら PASS を押してください。';
      case ShipmentStepKind.bleConnect:
      case ShipmentStepKind.batteryRead:
      case ShipmentStepKind.appRestart:
      case ShipmentStepKind.finalReconnect:
      case ShipmentStepKind.recordCheck:
        return '';
    }
  }

  String get operatorHint {
    switch (this) {
      case ShipmentStepKind.ledColor:
        return 'Android アプリが自動で色を順送りした後、最後の White を維持します。';
      case ShipmentStepKind.heartbeat:
        return '赤色 heartbeat を継続表示します。';
      case ShipmentStepKind.rainbow:
        return 'rainbow を継続表示します。';
      case ShipmentStepKind.minimumStartupVoltage:
        return 'アプリ単独では電圧を下げられないため、治具側で条件を作ってください。';
      case ShipmentStepKind.visualInspect:
        return '量産基準写真と照合してください。';
      case ShipmentStepKind.acceleration:
        return 'ESP32-C3 など対象外機種では SKIP を使用してください。';
      case ShipmentStepKind.bleConnect:
      case ShipmentStepKind.batteryRead:
      case ShipmentStepKind.appRestart:
      case ShipmentStepKind.finalReconnect:
      case ShipmentStepKind.recordCheck:
        return '';
    }
  }
}

class ShipmentInspectionConfig {
  final String testerName;
  final String serialNo;
  final String boardId;
  final String lotNo;
  final String fwVersion;
  final String mcuVersion;
  final String note;
  final int connectTimeoutSeconds;
  final int connectRetryCount;
  final int rssiMinDbm;
  final int mcuBootSettleMs;
  final double batteryMinV;
  final double startupVoltageMinV;
  final bool requireMcuRunner;
  final bool verifyGattOnConnect;
  final bool includeAccelerationCheck;

  const ShipmentInspectionConfig({
    required this.testerName,
    required this.serialNo,
    required this.boardId,
    required this.lotNo,
    required this.fwVersion,
    required this.mcuVersion,
    required this.note,
    required this.connectTimeoutSeconds,
    required this.connectRetryCount,
    required this.rssiMinDbm,
    required this.mcuBootSettleMs,
    required this.batteryMinV,
    required this.startupVoltageMinV,
    required this.requireMcuRunner,
    required this.verifyGattOnConnect,
    required this.includeAccelerationCheck,
  });

  factory ShipmentInspectionConfig.defaults() {
    return const ShipmentInspectionConfig(
      testerName: '',
      serialNo: '',
      boardId: '',
      lotNo: '',
      fwVersion: '',
      mcuVersion: '',
      note: '',
      connectTimeoutSeconds: 6,
      connectRetryCount: 1,
      rssiMinDbm: -90,
      mcuBootSettleMs: 3000,
      batteryMinV: Env.batteryMinV,
      startupVoltageMinV: Env.batteryMinV,
      requireMcuRunner: true,
      verifyGattOnConnect: true,
      includeAccelerationCheck: true,
    );
  }
}

class ShipmentStepEntry {
  static const Object _sentinel = Object();

  final ShipmentStepKind kind;
  final ShipmentStepStatus status;
  final String detail;
  final String? failureClass;
  final String? note;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? rssiA;
  final int? rssiB;
  final double? batteryA;
  final double? batteryB;

  const ShipmentStepEntry({
    required this.kind,
    this.status = ShipmentStepStatus.pending,
    this.detail = '',
    this.failureClass,
    this.note,
    this.startedAt,
    this.endedAt,
    this.rssiA,
    this.rssiB,
    this.batteryA,
    this.batteryB,
  });

  Duration? get duration => startedAt != null && endedAt != null
      ? endedAt!.difference(startedAt!)
      : null;

  ShipmentStepEntry copyWith({
    ShipmentStepStatus? status,
    Object? detail = _sentinel,
    Object? failureClass = _sentinel,
    Object? note = _sentinel,
    Object? startedAt = _sentinel,
    Object? endedAt = _sentinel,
    Object? rssiA = _sentinel,
    Object? rssiB = _sentinel,
    Object? batteryA = _sentinel,
    Object? batteryB = _sentinel,
  }) {
    return ShipmentStepEntry(
      kind: kind,
      status: status ?? this.status,
      detail: identical(detail, _sentinel) ? this.detail : detail as String,
      failureClass: identical(failureClass, _sentinel)
          ? this.failureClass
          : failureClass as String?,
      note: identical(note, _sentinel) ? this.note : note as String?,
      startedAt: identical(startedAt, _sentinel)
          ? this.startedAt
          : startedAt as DateTime?,
      endedAt:
          identical(endedAt, _sentinel) ? this.endedAt : endedAt as DateTime?,
      rssiA: identical(rssiA, _sentinel) ? this.rssiA : rssiA as int?,
      rssiB: identical(rssiB, _sentinel) ? this.rssiB : rssiB as int?,
      batteryA:
          identical(batteryA, _sentinel) ? this.batteryA : batteryA as double?,
      batteryB:
          identical(batteryB, _sentinel) ? this.batteryB : batteryB as double?,
    );
  }
}

class ShipmentInspectionState {
  static const Object _sentinel = Object();

  final ShipmentRunStatus status;
  final ShipmentInspectionConfig config;
  final List<ShipmentStepEntry> steps;
  final int? activeStepIndex;
  final ShipmentStepKind? awaitingOperatorStep;
  final String? operatorPrompt;
  final String? operatorHint;
  final String? message;
  final String? appVersion;
  final String? reportId;
  final String? reportPath;
  final String? summaryPath;
  final String? failureClass;
  final String? failureDetail;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<String> logs;

  const ShipmentInspectionState({
    required this.status,
    required this.config,
    required this.steps,
    required this.activeStepIndex,
    required this.awaitingOperatorStep,
    required this.operatorPrompt,
    required this.operatorHint,
    required this.message,
    required this.appVersion,
    required this.reportId,
    required this.reportPath,
    required this.summaryPath,
    required this.failureClass,
    required this.failureDetail,
    required this.startedAt,
    required this.finishedAt,
    required this.logs,
  });

  factory ShipmentInspectionState.initial() {
    final defaults = ShipmentInspectionConfig.defaults();
    return ShipmentInspectionState(
      status: ShipmentRunStatus.idle,
      config: defaults,
      steps: _buildDefaultSteps(defaults),
      activeStepIndex: null,
      awaitingOperatorStep: null,
      operatorPrompt: null,
      operatorHint: null,
      message: 'Ready',
      appVersion: null,
      reportId: null,
      reportPath: null,
      summaryPath: null,
      failureClass: null,
      failureDetail: null,
      startedAt: null,
      finishedAt: null,
      logs: const <String>[],
    );
  }

  bool get isRunning =>
      status == ShipmentRunStatus.running ||
      status == ShipmentRunStatus.awaitingOperator;

  int get completedSteps => steps
      .where(
        (step) =>
            step.status == ShipmentStepStatus.pass ||
            step.status == ShipmentStepStatus.fail ||
            step.status == ShipmentStepStatus.skipped,
      )
      .length;

  ShipmentInspectionState copyWith({
    ShipmentRunStatus? status,
    ShipmentInspectionConfig? config,
    List<ShipmentStepEntry>? steps,
    Object? activeStepIndex = _sentinel,
    Object? awaitingOperatorStep = _sentinel,
    Object? operatorPrompt = _sentinel,
    Object? operatorHint = _sentinel,
    Object? message = _sentinel,
    Object? appVersion = _sentinel,
    Object? reportId = _sentinel,
    Object? reportPath = _sentinel,
    Object? summaryPath = _sentinel,
    Object? failureClass = _sentinel,
    Object? failureDetail = _sentinel,
    Object? startedAt = _sentinel,
    Object? finishedAt = _sentinel,
    List<String>? logs,
  }) {
    return ShipmentInspectionState(
      status: status ?? this.status,
      config: config ?? this.config,
      steps: steps ?? this.steps,
      activeStepIndex: identical(activeStepIndex, _sentinel)
          ? this.activeStepIndex
          : activeStepIndex as int?,
      awaitingOperatorStep: identical(awaitingOperatorStep, _sentinel)
          ? this.awaitingOperatorStep
          : awaitingOperatorStep as ShipmentStepKind?,
      operatorPrompt: identical(operatorPrompt, _sentinel)
          ? this.operatorPrompt
          : operatorPrompt as String?,
      operatorHint: identical(operatorHint, _sentinel)
          ? this.operatorHint
          : operatorHint as String?,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      appVersion: identical(appVersion, _sentinel)
          ? this.appVersion
          : appVersion as String?,
      reportId:
          identical(reportId, _sentinel) ? this.reportId : reportId as String?,
      reportPath: identical(reportPath, _sentinel)
          ? this.reportPath
          : reportPath as String?,
      summaryPath: identical(summaryPath, _sentinel)
          ? this.summaryPath
          : summaryPath as String?,
      failureClass: identical(failureClass, _sentinel)
          ? this.failureClass
          : failureClass as String?,
      failureDetail: identical(failureDetail, _sentinel)
          ? this.failureDetail
          : failureDetail as String?,
      startedAt: identical(startedAt, _sentinel)
          ? this.startedAt
          : startedAt as DateTime?,
      finishedAt: identical(finishedAt, _sentinel)
          ? this.finishedAt
          : finishedAt as DateTime?,
      logs: logs ?? this.logs,
    );
  }

  static List<ShipmentStepEntry> _buildDefaultSteps(
    ShipmentInspectionConfig config,
  ) {
    return ShipmentStepKind.values
        .map(
          (kind) => ShipmentStepEntry(
            kind: kind,
            status: kind == ShipmentStepKind.acceleration &&
                    !config.includeAccelerationCheck
                ? ShipmentStepStatus.skipped
                : ShipmentStepStatus.pending,
            detail: kind == ShipmentStepKind.acceleration &&
                    !config.includeAccelerationCheck
                ? 'Disabled in config'
                : '',
          ),
        )
        .toList(growable: false);
  }
}

final shipmentInspectionProvider = StateNotifierProvider<
    ShipmentInspectionController, ShipmentInspectionState>(
  (ref) => ShipmentInspectionController(ref),
);

class ShipmentInspectionController
    extends StateNotifier<ShipmentInspectionState> {
  ShipmentInspectionController(this._ref)
      : super(ShipmentInspectionState.initial());

  static const Duration _disconnectTimeout = Duration(seconds: 4);
  static const Duration _connectRetryGap = Duration(milliseconds: 1200);
  static const Duration _mcuPowerOffDelay = Duration(milliseconds: 500);
  static const Duration _colorHold = Duration(seconds: 2);
  static const Duration _finalReconnectColorHold = Duration(milliseconds: 700);
  static const Color _inspectColor = Color(0xFFFF3B30);

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  bool _stopRequested = false;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  Completer<_OperatorResolution>? _operatorDecision;
  double? _lastBatteryA;
  double? _lastBatteryB;

  BleClient get _client => _ref.read(bleClientProvider);
  StockController get _stock => _ref.read(stockProvider.notifier);
  LedController get _led => _ref.read(ledControllerProvider);
  HeartbeatController get _heartbeat => _ref.read(heartbeatControllerProvider);
  LedUiController get _ledUi => _ref.read(ledUiProvider.notifier);
  McuSerialController get _mcu => _ref.read(mcuSerialProvider.notifier);

  Future<void> start(ShipmentInspectionConfig config) async {
    if (state.isRunning) {
      return;
    }

    final validationError = await _validateBeforeStart(config);
    final appVersion = await _resolveAppVersion();
    final reportId = _buildReportId(DateTime.now());
    final steps = ShipmentStepKind.values
        .map(
          (kind) => ShipmentStepEntry(
            kind: kind,
            status: kind == ShipmentStepKind.acceleration &&
                    !config.includeAccelerationCheck
                ? ShipmentStepStatus.skipped
                : ShipmentStepStatus.pending,
            detail: kind == ShipmentStepKind.acceleration &&
                    !config.includeAccelerationCheck
                ? 'Disabled in config'
                : '',
          ),
        )
        .toList(growable: false);

    if (validationError != null) {
      state = state.copyWith(
        status: ShipmentRunStatus.failed,
        config: config,
        steps: steps,
        appVersion: appVersion,
        reportId: reportId,
        message: validationError,
        failureClass: 'VALIDATION_FAIL',
        failureDetail: validationError,
      );
      _appendLog('[SHIP] validation failed: $validationError');
      return;
    }

    _stopRequested = false;
    _lastBatteryA = null;
    _lastBatteryB = null;
    state = state.copyWith(
      status: ShipmentRunStatus.running,
      config: config,
      steps: steps,
      activeStepIndex: 0,
      awaitingOperatorStep: null,
      operatorPrompt: null,
      operatorHint: null,
      message: 'Shipment inspection started',
      appVersion: appVersion,
      reportId: reportId,
      reportPath: null,
      summaryPath: null,
      failureClass: null,
      failureDetail: null,
      startedAt: DateTime.now(),
      finishedAt: null,
      logs: const <String>[],
    );
    _appendLog('[SHIP] start reportId=$reportId appVersion=$appVersion');

    unawaited(_runSequence(config));
  }

  void stop() {
    if (!state.isRunning) {
      return;
    }
    _stopRequested = true;
    _appendLog('[SHIP] stop requested');
    final pending = _operatorDecision;
    if (pending != null && !pending.isCompleted) {
      pending.complete(
        const _OperatorResolution(
          decision: ShipmentOperatorDecision.skip,
          note: 'Run stopped',
        ),
      );
    }
  }

  void submitOperatorDecision(
    ShipmentOperatorDecision decision, {
    String note = '',
  }) {
    final pending = _operatorDecision;
    if (pending == null || pending.isCompleted) {
      return;
    }
    pending
        .complete(_OperatorResolution(decision: decision, note: note.trim()));
  }

  Future<void> _runSequence(ShipmentInspectionConfig config) async {
    try {
      if (config.requireMcuRunner) {
        await _prepareMcuRunner(config);
      }
      await _disconnectAndIdle();

      await _runBleConnectStep(
        kind: ShipmentStepKind.bleConnect,
        config: config,
      );
      await _runLedColorStep();
      await _runHeartbeatStep();
      await _runRainbowStep();
      await _runBatteryStep(config);
      await _runAppRestartStep(config);
      await _runBleConnectStep(
        kind: ShipmentStepKind.finalReconnect,
        config: config,
        sendFinalColor: true,
      );
      await _runMinimumStartupVoltageStep(config);
      await _runRecordCheckStep(config);
      await _runVisualInspectStep();
      await _runAccelerationStep();

      await _setAllIdleBestEffort();
      final reportPaths = await _exportReports();
      if (reportPaths != null) {
        _appendDetailToStep(
          ShipmentStepKind.recordCheck,
          ' / report=${reportPaths.$1.split(Platform.pathSeparator).last}',
        );
      }
      state = state.copyWith(
        status: ShipmentRunStatus.done,
        activeStepIndex: null,
        awaitingOperatorStep: null,
        operatorPrompt: null,
        operatorHint: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        finishedAt: DateTime.now(),
        message: 'Shipment inspection finished',
      );
      _appendLog('[SHIP] finished');
    } on _ShipmentStopRequested {
      await _setAllIdleBestEffort();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: ShipmentRunStatus.stopped,
        activeStepIndex: null,
        awaitingOperatorStep: null,
        operatorPrompt: null,
        operatorHint: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        finishedAt: DateTime.now(),
        message: 'Shipment inspection stopped',
      );
    } on _ShipmentStepFailure catch (failure) {
      _log.w('shipment step failed', error: failure.detail);
      await _setAllIdleBestEffort();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: ShipmentRunStatus.failed,
        activeStepIndex: null,
        awaitingOperatorStep: null,
        operatorPrompt: null,
        operatorHint: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        failureClass: failure.failureClass,
        failureDetail: failure.detail,
        finishedAt: DateTime.now(),
        message: '${failure.kind.title} failed: ${failure.failureClass}',
      );
      _appendLog(
        '[SHIP] failed step=${failure.kind.title} class=${failure.failureClass} detail=${failure.detail}',
      );
    } catch (e, st) {
      _log.e('shipment inspection failed', error: e, stackTrace: st);
      await _setAllIdleBestEffort();
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: ShipmentRunStatus.error,
        activeStepIndex: null,
        awaitingOperatorStep: null,
        operatorPrompt: null,
        operatorHint: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        failureClass: 'UNEXPECTED_ERROR',
        failureDetail: e.toString(),
        finishedAt: DateTime.now(),
        message: e.toString(),
      );
      _appendLog('[SHIP] error: $e');
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _operatorDecision = null;
      await _stock.disconnectBoth();
      await _stock.waitForBothDisconnected(_disconnectTimeout);
      await _powerOffMcuBestEffort(config);
    }
  }

  Future<void> _prepareMcuRunner(ShipmentInspectionConfig config) async {
    _appendLog('[SHIP][MCU] prepare start');
    _mcu.clearStateHistory();
    final ready = await _mcu.ensureReady();
    if (!ready) {
      final detail =
          _ref.read(mcuSerialProvider).message ?? 'MCU serial is not ready.';
      throw _ShipmentStepFailure(
        kind: ShipmentStepKind.bleConnect,
        failureClass: 'MCU_NOT_READY',
        detail: detail,
      );
    }

    final bootEvent = await _mcu.sendCommandWait(
      'boot',
      'START_PULSE_OFF',
      timeout: const Duration(seconds: 7),
    );
    if (bootEvent == null) {
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.bleConnect,
        failureClass: 'MCU_BOOT_TIMEOUT',
        detail: 'MCU boot command timed out waiting for START_PULSE_OFF.',
      );
    }

    if (config.mcuBootSettleMs > 0) {
      _appendLog('[SHIP][MCU] boot settle ${config.mcuBootSettleMs}ms');
      await _interruptibleDelay(
        Duration(milliseconds: config.mcuBootSettleMs),
      );
    }
    _appendLog('[SHIP][MCU] boot ready');
  }

  Future<void> _powerOffMcuBestEffort(ShipmentInspectionConfig config) async {
    if (!config.requireMcuRunner) {
      return;
    }
    try {
      if (!_ref.read(mcuSerialProvider).connected) {
        return;
      }
      final event = await _mcu.sendCommandWait(
        'poff',
        'POWER_B_OFF',
        timeout: const Duration(seconds: 2),
      );
      if (event == null) {
        _appendLog('[SHIP][MCU] poff timeout');
      } else {
        _appendLog('[SHIP][MCU] power off complete');
      }
    } catch (e, st) {
      _log.w('shipment MCU power off failed', error: e, stackTrace: st);
    }
  }

  Future<void> _runBleConnectStep({
    required ShipmentStepKind kind,
    required ShipmentInspectionConfig config,
    bool sendFinalColor = false,
  }) async {
    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');

    final timeout = Duration(seconds: config.connectTimeoutSeconds);
    _ConnectEvidence? lastEvidence;

    for (var attempt = 0; attempt <= config.connectRetryCount; attempt++) {
      _throwIfStopRequested();
      final tryNumber = attempt + 1;
      final totalAttempts = config.connectRetryCount + 1;
      _appendLog('[SHIP] ${kind.title} attempt $tryNumber/$totalAttempts');

      await _disconnectAndIdle();

      final scanEvidence = await _scanAssignedDevices(timeout);
      if (!scanEvidence.ok) {
        lastEvidence = _ConnectEvidence.failure(
          'ADV_NOT_FOUND',
          scanEvidence.detail,
          rssiA: scanEvidence.rssiA,
          rssiB: scanEvidence.rssiB,
        );
      } else if (scanEvidence.rssiA == null || scanEvidence.rssiB == null) {
        lastEvidence = _ConnectEvidence.failure(
          'RSSI_MISSING',
          'RSSI values were not captured in the scan window.',
          rssiA: scanEvidence.rssiA,
          rssiB: scanEvidence.rssiB,
        );
      } else if (scanEvidence.rssiA! < config.rssiMinDbm ||
          scanEvidence.rssiB! < config.rssiMinDbm) {
        lastEvidence = _ConnectEvidence.failure(
          'RSSI_BELOW_LIMIT',
          'RSSI below limit A=${scanEvidence.rssiA} B=${scanEvidence.rssiB} min=${config.rssiMinDbm}',
          rssiA: scanEvidence.rssiA,
          rssiB: scanEvidence.rssiB,
        );
      } else {
        final startedAt = DateTime.now();
        await _stock.connectBoth();
        final connected = await _stock.waitForBothConnected(timeout);
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        if (!connected) {
          lastEvidence = _ConnectEvidence.failure(
            'CONNECT_FAILED',
            'Connection timeout after ${elapsedMs}ms.',
            elapsedMs: elapsedMs,
            rssiA: scanEvidence.rssiA,
            rssiB: scanEvidence.rssiB,
          );
        } else if (config.verifyGattOnConnect) {
          final gattA = await _stock.verifyGattProfile(StockSide.a);
          final gattB = await _stock.verifyGattProfile(StockSide.b);
          if (gattA != null || gattB != null) {
            lastEvidence = _ConnectEvidence.failure(
              'GATT_VERIFY_FAIL',
              'A=${gattA ?? 'OK'} / B=${gattB ?? 'OK'}',
              elapsedMs: elapsedMs,
              rssiA: scanEvidence.rssiA,
              rssiB: scanEvidence.rssiB,
            );
          } else {
            lastEvidence = _ConnectEvidence.success(
              elapsedMs: elapsedMs,
              rssiA: scanEvidence.rssiA,
              rssiB: scanEvidence.rssiB,
            );
          }
        } else {
          lastEvidence = _ConnectEvidence.success(
            elapsedMs: elapsedMs,
            rssiA: scanEvidence.rssiA,
            rssiB: scanEvidence.rssiB,
          );
        }
      }

      if (lastEvidence.ok) {
        if (sendFinalColor) {
          await _applySolidColorToConnectedTargets(_inspectColor);
          await _interruptibleDelay(_finalReconnectColorHold);
          await _setAllIdleBestEffort();
        }
        _setStepPass(
          kind,
          detail:
              '${kind == ShipmentStepKind.bleConnect ? 'Android auto connect' : 'Reconnect'} ok in ${lastEvidence.elapsedMs}ms / retry $attempt/${config.connectRetryCount} / RSSI A=${lastEvidence.rssiA} B=${lastEvidence.rssiB}',
          rssiA: lastEvidence.rssiA,
          rssiB: lastEvidence.rssiB,
        );
        _appendLog('[SHIP] ${kind.title} pass');
        return;
      }

      if (attempt < config.connectRetryCount) {
        await _interruptibleDelay(_connectRetryGap);
      }
    }

    _setStepFail(
      kind,
      failureClass: lastEvidence?.failureClass ?? 'CONNECT_FAILED',
      detail: lastEvidence?.detail ?? 'Connection failed.',
      rssiA: lastEvidence?.rssiA,
      rssiB: lastEvidence?.rssiB,
    );
    throw _ShipmentStepFailure(
      kind: kind,
      failureClass: lastEvidence?.failureClass ?? 'CONNECT_FAILED',
      detail: lastEvidence?.detail ?? 'Connection failed.',
    );
  }

  Future<void> _runLedColorStep() async {
    const kind = ShipmentStepKind.ledColor;
    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');
    try {
      await _applySolidColorToConnectedTargets(const Color(0xFFFF0000));
      await _interruptibleDelay(_colorHold);
      await _applySolidColorToConnectedTargets(const Color(0xFF00FF00));
      await _interruptibleDelay(_colorHold);
      await _applySolidColorToConnectedTargets(const Color(0xFF0000FF));
      await _interruptibleDelay(_colorHold);
      await _applySolidColorToConnectedTargets(const Color(0xFFFFFFFF));
      final resolution = await _awaitOperator(kind);
      await _setAllIdleBestEffort();
      _completeOperatorStep(kind, resolution,
          successDetail: 'R/G/B/White confirmed');
    } catch (_) {
      await _setAllIdleBestEffort();
      rethrow;
    }
  }

  Future<void> _runHeartbeatStep() async {
    const kind = ShipmentStepKind.heartbeat;
    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');
    try {
      await _applyHeartbeatToConnectedTargets(
        color: _inspectColor,
        intervalMs: 600,
      );
      final resolution = await _awaitOperator(kind);
      await _setAllIdleBestEffort();
      _completeOperatorStep(kind, resolution,
          successDetail: 'heartbeat confirmed');
    } catch (_) {
      await _setAllIdleBestEffort();
      rethrow;
    }
  }

  Future<void> _runRainbowStep() async {
    const kind = ShipmentStepKind.rainbow;
    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');
    try {
      await _applyRainbowToConnectedTargets(intervalMs: 40);
      final resolution = await _awaitOperator(kind);
      await _setAllIdleBestEffort();
      _completeOperatorStep(kind, resolution,
          successDetail: 'rainbow confirmed');
    } catch (_) {
      await _setAllIdleBestEffort();
      rethrow;
    }
  }

  Future<void> _runBatteryStep(ShipmentInspectionConfig config) async {
    const kind = ShipmentStepKind.batteryRead;
    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');

    final batteryA = await _stock.readBattery(StockSide.a);
    final batteryB = await _stock.readBattery(StockSide.b);
    _lastBatteryA = batteryA;
    _lastBatteryB = batteryB;

    if (batteryA == null ||
        batteryB == null ||
        batteryA <= 0 ||
        batteryB <= 0) {
      final detail =
          'Battery read failed A=${batteryA?.toStringAsFixed(3) ?? 'null'} B=${batteryB?.toStringAsFixed(3) ?? 'null'}';
      _setStepFail(
        kind,
        failureClass: 'BATTERY_READ_FAIL',
        detail: detail,
        batteryA: batteryA,
        batteryB: batteryB,
      );
      throw _ShipmentStepFailure(
        kind: kind,
        failureClass: 'BATTERY_READ_FAIL',
        detail: detail,
      );
    }
    if (batteryA < config.batteryMinV || batteryB < config.batteryMinV) {
      final detail =
          'Battery below limit A=${batteryA.toStringAsFixed(3)} B=${batteryB.toStringAsFixed(3)} min=${config.batteryMinV.toStringAsFixed(3)}';
      _setStepFail(
        kind,
        failureClass: 'BATTERY_BELOW_LIMIT',
        detail: detail,
        batteryA: batteryA,
        batteryB: batteryB,
      );
      throw _ShipmentStepFailure(
        kind: kind,
        failureClass: 'BATTERY_BELOW_LIMIT',
        detail: detail,
      );
    }

    _setStepPass(
      kind,
      detail:
          'Battery ok A=${batteryA.toStringAsFixed(3)}V B=${batteryB.toStringAsFixed(3)}V min=${config.batteryMinV.toStringAsFixed(3)}V',
      batteryA: batteryA,
      batteryB: batteryB,
    );
  }

  Future<void> _runAppRestartStep(ShipmentInspectionConfig config) async {
    const kind = ShipmentStepKind.appRestart;
    _setStepRunning(
      kind,
      config.requireMcuRunner
          ? 'MCU power cycle で再起動相当動作を確認します。'
          : kind.description,
    );
    _appendLog('[SHIP] ${kind.title} start');

    if (config.requireMcuRunner) {
      await _disconnectAndIdle();

      final ready = await _mcu.ensureReady();
      if (!ready) {
        final detail =
            _ref.read(mcuSerialProvider).message ?? 'MCU serial is not ready.';
        _setStepFail(
          kind,
          failureClass: 'MCU_NOT_READY',
          detail: detail,
        );
        throw _ShipmentStepFailure(
          kind: kind,
          failureClass: 'MCU_NOT_READY',
          detail: detail,
        );
      }

      final powerOffStartIndex = _ref.read(mcuSerialProvider).events.length;
      final powerOffSent = await _mcu.sendLine('poff');
      if (!powerOffSent) {
        const detail = 'MCU power off command send failed.';
        _setStepFail(
          kind,
          failureClass: 'MCU_POWEROFF_SEND_FAIL',
          detail: detail,
        );
        throw const _ShipmentStepFailure(
          kind: ShipmentStepKind.appRestart,
          failureClass: 'MCU_POWEROFF_SEND_FAIL',
          detail: detail,
        );
      }
      final powerOffEvent = await _mcu.waitForState(
        <String>{'POWER_A_OFF', 'POWER_B_OFF'},
        timeout: const Duration(seconds: 2),
        startIndex: powerOffStartIndex,
      );
      if (powerOffEvent == null) {
        const detail =
            'MCU power off timeout waiting for POWER_A_OFF / POWER_B_OFF.';
        _setStepFail(
          kind,
          failureClass: 'MCU_POWEROFF_TIMEOUT',
          detail: detail,
        );
        throw const _ShipmentStepFailure(
          kind: ShipmentStepKind.appRestart,
          failureClass: 'MCU_POWEROFF_TIMEOUT',
          detail: detail,
        );
      }

      await _interruptibleDelay(_mcuPowerOffDelay);

      final bootStartIndex = _ref.read(mcuSerialProvider).events.length;
      final bootSent = await _mcu.sendLine('boot');
      if (!bootSent) {
        const detail = 'MCU boot command send failed.';
        _setStepFail(
          kind,
          failureClass: 'MCU_BOOT_SEND_FAIL',
          detail: detail,
        );
        throw const _ShipmentStepFailure(
          kind: ShipmentStepKind.appRestart,
          failureClass: 'MCU_BOOT_SEND_FAIL',
          detail: detail,
        );
      }
      final bootEvent = await _mcu.waitForState(
        <String>{'START_PULSE_OFF'},
        timeout: const Duration(seconds: 7),
        startIndex: bootStartIndex,
      );
      if (bootEvent == null) {
        const detail = 'MCU boot timeout waiting for START_PULSE_OFF.';
        _setStepFail(
          kind,
          failureClass: 'MCU_BOOT_TIMEOUT',
          detail: detail,
        );
        throw const _ShipmentStepFailure(
          kind: ShipmentStepKind.appRestart,
          failureClass: 'MCU_BOOT_TIMEOUT',
          detail: detail,
        );
      }

      if (config.mcuBootSettleMs > 0) {
        await _interruptibleDelay(
          Duration(milliseconds: config.mcuBootSettleMs),
        );
      }

      _setStepPass(
        kind,
        detail:
            'MCU power cycle completed / off=${powerOffEvent.state} / boot=${bootEvent.state} / settle=${config.mcuBootSettleMs}ms',
      );
      return;
    }

    await _disconnectAndIdle();
    _ref.invalidate(heartbeatControllerProvider);
    _ref.invalidate(ledUiProvider);
    _ref.invalidate(ledControllerProvider);
    _ref.invalidate(stockProvider);
    _ref.invalidate(bleClientProvider);
    await _interruptibleDelay(const Duration(milliseconds: 800));
    await _ref.read(stockProvider.notifier).ensureLoaded();

    final stockState = _ref.read(stockProvider);
    if (!stockState.registered) {
      const detail = 'Stored A/B assignment was lost after restart simulation.';
      _setStepFail(
        kind,
        failureClass: 'RESTART_STATE_LOST',
        detail: detail,
      );
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.appRestart,
        failureClass: 'RESTART_STATE_LOST',
        detail: detail,
      );
    }

    _setStepPass(
      kind,
      detail: 'BLE session reset completed and stored devices reloaded.',
    );
  }

  Future<void> _runMinimumStartupVoltageStep(
    ShipmentInspectionConfig config,
  ) async {
    const kind = ShipmentStepKind.minimumStartupVoltage;
    _setStepRunning(
      kind,
      'Target ${config.startupVoltageMinV.toStringAsFixed(3)}V / current A=${_lastBatteryA?.toStringAsFixed(3) ?? '--'} B=${_lastBatteryB?.toStringAsFixed(3) ?? '--'}',
    );
    final resolution = await _awaitOperator(kind);
    _completeOperatorStep(
      kind,
      resolution,
      successDetail:
          'Operator confirmed startup at ${config.startupVoltageMinV.toStringAsFixed(3)}V',
    );
  }

  Future<void> _runRecordCheckStep(ShipmentInspectionConfig config) async {
    const kind = ShipmentStepKind.recordCheck;
    _setStepRunning(kind, kind.description);

    final missing = <String>[];
    if (config.testerName.trim().isEmpty) {
      missing.add('tester_name');
    }
    if (config.serialNo.trim().isEmpty) {
      missing.add('serial_no');
    }
    if (config.boardId.trim().isEmpty) {
      missing.add('board_id');
    }
    if (config.fwVersion.trim().isEmpty) {
      missing.add('fw_version');
    }
    if (config.requireMcuRunner && config.mcuVersion.trim().isEmpty) {
      missing.add('mcu_version');
    }
    if ((state.appVersion ?? '').trim().isEmpty) {
      missing.add('app_version');
    }
    if ((state.reportId ?? '').trim().isEmpty) {
      missing.add('report_id');
    }

    if (missing.isNotEmpty) {
      final detail = 'Missing record fields: ${missing.join(', ')}';
      _setStepFail(
        kind,
        failureClass: 'RECORD_FIELD_MISSING',
        detail: detail,
      );
      throw _ShipmentStepFailure(
        kind: kind,
        failureClass: 'RECORD_FIELD_MISSING',
        detail: detail,
      );
    }

    _setStepPass(
      kind,
      detail:
          'Record fields ready / reportId=${state.reportId} / appVersion=${state.appVersion}',
    );
  }

  Future<void> _runVisualInspectStep() async {
    const kind = ShipmentStepKind.visualInspect;
    _setStepRunning(kind, kind.description);
    final resolution = await _awaitOperator(kind);
    _completeOperatorStep(
      kind,
      resolution,
      successDetail: 'No visual defect found',
    );
  }

  Future<void> _runAccelerationStep() async {
    const kind = ShipmentStepKind.acceleration;
    final current = _stepEntry(kind);
    if (current.status == ShipmentStepStatus.skipped) {
      return;
    }

    _setStepRunning(kind, kind.description);
    _appendLog('[SHIP] ${kind.title} start');
    try {
      await _applyAccelerationToConnectedTargets();
      final resolution = await _awaitOperator(kind);
      await _setAllIdleBestEffort();
      _completeOperatorStep(
        kind,
        resolution,
        successDetail: 'acceleration confirmed',
      );
    } catch (_) {
      await _setAllIdleBestEffort();
      rethrow;
    }
  }

  Future<_OperatorResolution> _awaitOperator(ShipmentStepKind kind) async {
    _throwIfStopRequested();
    final completer = Completer<_OperatorResolution>();
    _operatorDecision = completer;
    final index = _indexOf(kind);
    state = state.copyWith(
      status: ShipmentRunStatus.awaitingOperator,
      activeStepIndex: index,
      awaitingOperatorStep: kind,
      operatorPrompt: kind.operatorPrompt,
      operatorHint: kind.operatorHint,
      message: '${kind.title}: waiting operator',
    );
    _setStepStatus(kind, ShipmentStepStatus.awaitingOperator);
    final result = await completer.future;
    _operatorDecision = null;
    _throwIfStopRequested();
    state = state.copyWith(
      status: ShipmentRunStatus.running,
      awaitingOperatorStep: null,
      operatorPrompt: null,
      operatorHint: null,
    );
    return result;
  }

  void _completeOperatorStep(
    ShipmentStepKind kind,
    _OperatorResolution resolution, {
    required String successDetail,
  }) {
    switch (resolution.decision) {
      case ShipmentOperatorDecision.pass:
        _setStepPass(kind, detail: successDetail, note: resolution.note);
        return;
      case ShipmentOperatorDecision.skip:
        _setStepSkipped(
          kind,
          detail: 'Operator skipped step',
          note: resolution.note,
        );
        return;
      case ShipmentOperatorDecision.fail:
        final detail = resolution.note.isEmpty
            ? 'Operator marked the step as fail.'
            : resolution.note;
        _setStepFail(
          kind,
          failureClass: 'OPERATOR_FAIL',
          detail: detail,
          note: resolution.note,
        );
        throw _ShipmentStepFailure(
          kind: kind,
          failureClass: 'OPERATOR_FAIL',
          detail: detail,
        );
    }
  }

  Future<void> _applySolidColorToConnectedTargets(Color color) async {
    final targets = _connectedTargets();
    if (targets.isEmpty) {
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.ledColor,
        failureClass: 'NOT_CONNECTED',
        detail: 'No connected targets available.',
      );
    }
    for (final target in targets) {
      await _led.setOutputEnabled(target.deviceId, true);
      await _led.setBrightness(target.deviceId, 255);
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
      _ledUi.setOutputEnabled(target.side, true);
      _ledUi.setBrightness(target.side, 255);
      _ledUi.setSegmentColor(target.side, ColorZone.both, color);
      _ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.color);
    }
  }

  Future<void> _applyHeartbeatToConnectedTargets({
    required Color color,
    required int intervalMs,
  }) async {
    final targets = _connectedTargets();
    if (targets.isEmpty) {
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.heartbeat,
        failureClass: 'NOT_CONNECTED',
        detail: 'No connected targets available.',
      );
    }
    for (final target in targets) {
      await _led.setOutputEnabled(target.deviceId, true);
      await _led.setBrightness(target.deviceId, 255);
      _ledUi.setOutputEnabled(target.side, true);
      _ledUi.setBrightness(target.side, 255);
      _ledUi.setHeartbeatColor(target.side, color);
      _ledUi.setHeartbeatInterval(target.side, intervalMs);
      _heartbeat.start(
        target.side,
        target.deviceId,
        interval: Duration(milliseconds: intervalMs),
      );
    }
  }

  Future<void> _applyRainbowToConnectedTargets(
      {required int intervalMs}) async {
    final targets = _connectedTargets();
    if (targets.isEmpty) {
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.rainbow,
        failureClass: 'NOT_CONNECTED',
        detail: 'No connected targets available.',
      );
    }
    for (final target in targets) {
      await _led.setOutputEnabled(target.deviceId, true);
      await _led.setBrightness(target.deviceId, 255);
      await _led.startRainbow(target.deviceId, intervalMs: intervalMs);
      _ledUi.setOutputEnabled(target.side, true);
      _ledUi.setBrightness(target.side, 255);
      _ledUi.setSegmentMode(target.side, ColorZone.both, LedMode.rainbow);
    }
  }

  Future<void> _applyAccelerationToConnectedTargets() async {
    final targets = _connectedTargets();
    if (targets.isEmpty) {
      throw const _ShipmentStepFailure(
        kind: ShipmentStepKind.acceleration,
        failureClass: 'NOT_CONNECTED',
        detail: 'No connected targets available.',
      );
    }
    for (final target in targets) {
      await _led.setOutputEnabled(target.deviceId, true);
      await _led.setBrightness(target.deviceId, 255);
      await _led.setAccelMode(target.deviceId, true);
      _ledUi.setOutputEnabled(target.side, true);
      _ledUi.setBrightness(target.side, 255);
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

  Future<void> _disconnectAndIdle() async {
    await _setAllIdleBestEffort();
    await _stock.disconnectBoth();
    await _stock.waitForBothDisconnected(_disconnectTimeout);
  }

  Future<_ScanEvidence> _scanAssignedDevices(Duration timeout) async {
    final stockState = _ref.read(stockProvider);
    final expectedA = stockState.a.device;
    final expectedB = stockState.b.device;
    if (expectedA == null || expectedB == null) {
      return const _ScanEvidence(
        ok: false,
        detail: 'Devices A/B are not assigned.',
      );
    }

    final completer = Completer<void>();
    final found = <StockSide, bool>{StockSide.a: false, StockSide.b: false};
    int? rssiA;
    int? rssiB;
    Object? error;
    StackTrace? errorStack;

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
        errorStack = st;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await Future.any<void>(<Future<void>>[
        completer.future,
        Future<void>.delayed(timeout),
      ]);
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    _throwIfStopRequested();

    if (error != null) {
      _log.w('shipment scan failed', error: error, stackTrace: errorStack);
      return _ScanEvidence(
        ok: false,
        detail: error.toString(),
        rssiA: rssiA,
        rssiB: rssiB,
      );
    }
    if (!found[StockSide.a]! || !found[StockSide.b]!) {
      return _ScanEvidence(
        ok: false,
        detail:
            'A=${found[StockSide.a]! ? 'OK' : 'NG'} B=${found[StockSide.b]! ? 'OK' : 'NG'}',
        rssiA: rssiA,
        rssiB: rssiB,
      );
    }
    return _ScanEvidence(
      ok: true,
      detail: 'OK',
      rssiA: rssiA,
      rssiB: rssiB,
    );
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

  Future<String?> _validateBeforeStart(ShipmentInspectionConfig config) async {
    if (!Platform.isAndroid) {
      return 'Shipment inspection app runs on Android only.';
    }
    final granted = await _ensurePermissions();
    if (!granted) {
      return 'BLE permissions not granted.';
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
    if (config.requireMcuRunner) {
      final mcuState = _ref.read(mcuSerialProvider);
      if (mcuState.transportMode == McuTransportMode.bridge) {
        if (mcuState.bridgeHost.trim().isEmpty ||
            mcuState.bridgePort <= 0 ||
            mcuState.bridgePort > 65535) {
          return 'Enter a valid MCU bridge host/port.';
        }
      } else {
        await _mcu.refreshDevices();
        final refreshed = _ref.read(mcuSerialProvider);
        if (!refreshed.connected && refreshed.devices.isEmpty) {
          return 'No MCU USB serial device found.';
        }
      }
    }
    return null;
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
    final granted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
    if (!granted) {
      _log.w('BLE permission denied: $statuses');
    }
    return granted;
  }

  Future<String?> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  Future<(String, String)?> _exportReports() async {
    if (state.startedAt == null) {
      return null;
    }

    final directory = await _resolveReportDirectory();
    final stamp = _timestampForFile(state.startedAt!);
    final reportId = state.reportId ?? _buildReportId(state.startedAt!);
    final detailPath =
        '${directory.path}${Platform.pathSeparator}shipment_report_$stamp.json';
    final summaryPath =
        '${directory.path}${Platform.pathSeparator}shipment_report_steps_$stamp.csv';

    final stockState = _ref.read(stockProvider);
    final mcuState = _ref.read(mcuSerialProvider);
    final overallStatus = switch (state.status) {
      ShipmentRunStatus.done => 'pass',
      ShipmentRunStatus.failed => 'fail',
      ShipmentRunStatus.error => 'error',
      ShipmentRunStatus.stopped => 'stopped',
      ShipmentRunStatus.awaitingOperator => 'in_progress',
      ShipmentRunStatus.running => 'in_progress',
      ShipmentRunStatus.idle => 'not_started',
    };

    final payload = <String, Object?>{
      'report_id': reportId,
      'started_at': _timestampIso(state.startedAt!),
      'finished_at':
          state.finishedAt != null ? _timestampIso(state.finishedAt!) : null,
      'overall_status': overallStatus,
      'judge': state.status == ShipmentRunStatus.done
          ? 'pass'
          : (state.status == ShipmentRunStatus.failed ||
                  state.status == ShipmentRunStatus.error
              ? 'fail'
              : 'pending'),
      'failure_class': state.failureClass,
      'failure_detail': state.failureDetail,
      'serial_no': state.config.serialNo,
      'board_id': state.config.boardId,
      'lot_no': state.config.lotNo,
      'tester_name': state.config.testerName,
      'fw_version': state.config.fwVersion,
      'mcu_version': state.config.mcuVersion,
      'app_version': state.appVersion,
      'note': state.config.note,
      'mcu_runner_required': state.config.requireMcuRunner,
      'mcu_transport_mode': mcuState.transportMode.name,
      'mcu_connected': mcuState.connected,
      'mcu_endpoint': mcuState.connectedDeviceId ??
          (mcuState.transportMode == McuTransportMode.bridge
              ? '${mcuState.bridgeHost}:${mcuState.bridgePort}'
              : mcuState.selectedDeviceId),
      'ble_name_a': stockState.a.device?.name,
      'ble_name_b': stockState.b.device?.name,
      'mac_a': stockState.a.device?.id,
      'mac_b': stockState.b.device?.id,
      'steps': state.steps
          .map(
            (step) => <String, Object?>{
              'title': step.kind.title,
              'description': step.kind.description,
              'status': step.status.name,
              'detail': step.detail,
              'failure_class': step.failureClass,
              'note': step.note,
              'started_at': step.startedAt != null
                  ? _timestampIso(step.startedAt!)
                  : null,
              'ended_at':
                  step.endedAt != null ? _timestampIso(step.endedAt!) : null,
              'duration_ms': step.duration?.inMilliseconds,
              'rssi_a_dbm': step.rssiA,
              'rssi_b_dbm': step.rssiB,
              'battery_a_v': step.batteryA?.toStringAsFixed(3),
              'battery_b_v': step.batteryB?.toStringAsFixed(3),
            },
          )
          .toList(growable: false),
    };
    await File(detailPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    final csv = StringBuffer()
      ..writeln(
        _csvRow(const <Object?>[
          'order',
          'title',
          'status',
          'started_at',
          'ended_at',
          'duration_ms',
          'failure_class',
          'detail',
          'note',
          'rssi_a_dbm',
          'rssi_b_dbm',
          'battery_a_v',
          'battery_b_v',
        ]),
      );
    for (var index = 0; index < state.steps.length; index++) {
      final step = state.steps[index];
      csv.writeln(
        _csvRow(<Object?>[
          index + 1,
          step.kind.title,
          step.status.name,
          step.startedAt != null ? _timestampIso(step.startedAt!) : null,
          step.endedAt != null ? _timestampIso(step.endedAt!) : null,
          step.duration?.inMilliseconds,
          step.failureClass,
          step.detail,
          step.note,
          step.rssiA,
          step.rssiB,
          step.batteryA?.toStringAsFixed(3),
          step.batteryB?.toStringAsFixed(3),
        ]),
      );
    }
    await File(summaryPath).writeAsString(csv.toString());
    return (detailPath, summaryPath);
  }

  Future<Directory> _resolveReportDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${baseDir.path}${Platform.pathSeparator}shipment_reports',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  void _setStepRunning(ShipmentStepKind kind, String detail) {
    final now = DateTime.now();
    final index = _indexOf(kind);
    _updateStep(
      kind,
      (step) => step.copyWith(
        status: ShipmentStepStatus.running,
        detail: detail,
        failureClass: null,
        note: null,
        startedAt: now,
        endedAt: null,
      ),
    );
    state = state.copyWith(
      status: ShipmentRunStatus.running,
      activeStepIndex: index,
      message: '${kind.title} running',
    );
  }

  void _setStepPass(
    ShipmentStepKind kind, {
    required String detail,
    String? note,
    int? rssiA,
    int? rssiB,
    double? batteryA,
    double? batteryB,
  }) {
    _updateStep(
      kind,
      (step) => step.copyWith(
        status: ShipmentStepStatus.pass,
        detail: detail,
        failureClass: null,
        note: note,
        endedAt: DateTime.now(),
        rssiA: rssiA,
        rssiB: rssiB,
        batteryA: batteryA,
        batteryB: batteryB,
      ),
    );
    state = state.copyWith(message: '${kind.title} pass');
  }

  void _setStepFail(
    ShipmentStepKind kind, {
    required String failureClass,
    required String detail,
    String? note,
    int? rssiA,
    int? rssiB,
    double? batteryA,
    double? batteryB,
  }) {
    _updateStep(
      kind,
      (step) => step.copyWith(
        status: ShipmentStepStatus.fail,
        detail: detail,
        failureClass: failureClass,
        note: note,
        endedAt: DateTime.now(),
        rssiA: rssiA,
        rssiB: rssiB,
        batteryA: batteryA,
        batteryB: batteryB,
      ),
    );
    state = state.copyWith(
      failureClass: failureClass,
      failureDetail: detail,
      message: '${kind.title} fail: $failureClass',
    );
  }

  void _setStepSkipped(
    ShipmentStepKind kind, {
    required String detail,
    String? note,
  }) {
    _updateStep(
      kind,
      (step) => step.copyWith(
        status: ShipmentStepStatus.skipped,
        detail: detail,
        note: note,
        endedAt: DateTime.now(),
      ),
    );
    state = state.copyWith(message: '${kind.title} skipped');
  }

  void _setStepStatus(ShipmentStepKind kind, ShipmentStepStatus status) {
    _updateStep(kind, (step) => step.copyWith(status: status));
  }

  void _appendDetailToStep(ShipmentStepKind kind, String suffix) {
    _updateStep(
      kind,
      (step) => step.copyWith(detail: '${step.detail}$suffix'),
    );
  }

  void _updateStep(
    ShipmentStepKind kind,
    ShipmentStepEntry Function(ShipmentStepEntry step) update,
  ) {
    final nextSteps = state.steps.map((step) {
      if (step.kind != kind) {
        return step;
      }
      return update(step);
    }).toList(growable: false);
    state = state.copyWith(steps: nextSteps);
  }

  ShipmentStepEntry _stepEntry(ShipmentStepKind kind) {
    return state.steps.firstWhere((step) => step.kind == kind);
  }

  int _indexOf(ShipmentStepKind kind) {
    return state.steps.indexWhere((step) => step.kind == kind);
  }

  List<({StockSide side, String deviceId})> _connectedTargets() {
    final stockState = _ref.read(stockProvider);
    final targets = <({StockSide side, String deviceId})>[];
    for (final side in StockSide.values) {
      final sideState = side == StockSide.a ? stockState.a : stockState.b;
      final deviceId = sideState.device?.id;
      if (deviceId == null ||
          sideState.status != DeviceConnectionState.connected) {
        continue;
      }
      targets.add((side: side, deviceId: deviceId));
    }
    return targets;
  }

  void _appendLog(String line) {
    final next = <String>[...state.logs, line];
    if (next.length > 300) {
      next.removeRange(0, next.length - 300);
    }
    state = state.copyWith(logs: next);
  }

  String _buildReportId(DateTime time) {
    return 'SHIP-${_timestampForFile(time)}';
  }

  String _timestampIso(DateTime value) {
    return value.toIso8601String();
  }

  String _timestampForFile(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }

  String _csvRow(List<Object?> values) {
    return values.map((value) {
      final text = value?.toString() ?? '';
      final escaped = text.replaceAll('"', '""');
      return '"$escaped"';
    }).join(',');
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

  void _throwIfStopRequested() {
    if (_stopRequested) {
      throw const _ShipmentStopRequested();
    }
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    if (_operatorDecision != null && !_operatorDecision!.isCompleted) {
      _operatorDecision!.complete(
        const _OperatorResolution(
          decision: ShipmentOperatorDecision.skip,
          note: 'Disposed',
        ),
      );
    }
    super.dispose();
  }
}

class _OperatorResolution {
  final ShipmentOperatorDecision decision;
  final String note;

  const _OperatorResolution({
    required this.decision,
    required this.note,
  });
}

class _ScanEvidence {
  final bool ok;
  final String detail;
  final int? rssiA;
  final int? rssiB;

  const _ScanEvidence({
    required this.ok,
    required this.detail,
    this.rssiA,
    this.rssiB,
  });
}

class _ConnectEvidence {
  final bool ok;
  final String failureClass;
  final String detail;
  final int? elapsedMs;
  final int? rssiA;
  final int? rssiB;

  const _ConnectEvidence({
    required this.ok,
    required this.failureClass,
    required this.detail,
    this.elapsedMs,
    this.rssiA,
    this.rssiB,
  });

  factory _ConnectEvidence.success({
    required int elapsedMs,
    required int? rssiA,
    required int? rssiB,
  }) {
    return _ConnectEvidence(
      ok: true,
      failureClass: 'PASS',
      detail: 'Connect ok',
      elapsedMs: elapsedMs,
      rssiA: rssiA,
      rssiB: rssiB,
    );
  }

  factory _ConnectEvidence.failure(
    String failureClass,
    String detail, {
    int? elapsedMs,
    int? rssiA,
    int? rssiB,
  }) {
    return _ConnectEvidence(
      ok: false,
      failureClass: failureClass,
      detail: detail,
      elapsedMs: elapsedMs,
      rssiA: rssiA,
      rssiB: rssiB,
    );
  }
}

class _ShipmentStepFailure implements Exception {
  final ShipmentStepKind kind;
  final String failureClass;
  final String detail;

  const _ShipmentStepFailure({
    required this.kind,
    required this.failureClass,
    required this.detail,
  });
}

class _ShipmentStopRequested implements Exception {
  const _ShipmentStopRequested();
}
