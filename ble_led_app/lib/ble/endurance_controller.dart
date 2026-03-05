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
import 'led_controller.dart';
import 'led_ui_state.dart';
import 'models.dart';
import 'stock_controller.dart';

enum EnduranceRunStatus { idle, running, stopped, done, failed, error }

class EnduranceSettings {
  final int cycles;
  final double connectWaitSeconds;
  final double disconnectWaitSeconds;
  final bool scanBeforeConnect;
  final bool runStartupWave;
  final bool runGattCheck;
  final bool stopOnFail;

  const EnduranceSettings({
    required this.cycles,
    required this.connectWaitSeconds,
    required this.disconnectWaitSeconds,
    required this.scanBeforeConnect,
    required this.runStartupWave,
    required this.runGattCheck,
    required this.stopOnFail,
  });

  factory EnduranceSettings.defaults() {
    return const EnduranceSettings(
      cycles: 100,
      connectWaitSeconds: 0.5,
      disconnectWaitSeconds: 0.5,
      scanBeforeConnect: true,
      runStartupWave: true,
      runGattCheck: true,
      stopOnFail: false,
    );
  }
}

class EnduranceCycleRecord {
  final int cycle;
  final DateTime startedAt;
  final DateTime endedAt;
  final String result;
  final String failureClass;
  final String failureDetail;
  final Duration scanDuration;
  final Duration connectDuration;
  final Duration gattDuration;
  final Duration disconnectDuration;
  final bool scanOk;
  final bool connectOk;
  final bool gattOk;
  final bool disconnectOk;
  final String lastLog;

  const EnduranceCycleRecord({
    required this.cycle,
    required this.startedAt,
    required this.endedAt,
    required this.result,
    required this.failureClass,
    required this.failureDetail,
    required this.scanDuration,
    required this.connectDuration,
    required this.gattDuration,
    required this.disconnectDuration,
    required this.scanOk,
    required this.connectOk,
    required this.gattOk,
    required this.disconnectOk,
    required this.lastLog,
  });

  Duration get totalDuration =>
      scanDuration + connectDuration + gattDuration + disconnectDuration;
}

class EnduranceState {
  static const Object _sentinel = Object();

  final EnduranceRunStatus status;
  final EnduranceSettings settings;
  final int totalCycles;
  final int doneCycles;
  final int passCount;
  final int failCount;
  final int? activeCycle;
  final String? message;
  final String? reportPath;
  final String? summaryPath;
  final String? lastOutcome;
  final Map<String, int> failureCounts;
  final List<EnduranceCycleRecord> records;
  final List<String> logs;

  const EnduranceState({
    required this.status,
    required this.settings,
    required this.totalCycles,
    required this.doneCycles,
    required this.passCount,
    required this.failCount,
    required this.activeCycle,
    required this.message,
    required this.reportPath,
    required this.summaryPath,
    required this.lastOutcome,
    required this.failureCounts,
    required this.records,
    required this.logs,
  });

  factory EnduranceState.initial() {
    return EnduranceState(
      status: EnduranceRunStatus.idle,
      settings: EnduranceSettings.defaults(),
      totalCycles: 0,
      doneCycles: 0,
      passCount: 0,
      failCount: 0,
      activeCycle: null,
      message: null,
      reportPath: null,
      summaryPath: null,
      lastOutcome: null,
      failureCounts: const <String, int>{},
      records: const <EnduranceCycleRecord>[],
      logs: const <String>[],
    );
  }

  bool get isRunning => status == EnduranceRunStatus.running;

  double get progress =>
      totalCycles <= 0 ? 0 : (doneCycles / totalCycles).clamp(0.0, 1.0);

  String get statusText {
    switch (status) {
      case EnduranceRunStatus.idle:
        return 'IDLE';
      case EnduranceRunStatus.running:
        return 'RUNNING';
      case EnduranceRunStatus.stopped:
        return 'STOPPED';
      case EnduranceRunStatus.done:
        return 'DONE';
      case EnduranceRunStatus.failed:
        return 'FAILED';
      case EnduranceRunStatus.error:
        return 'ERROR';
    }
  }

  EnduranceState copyWith({
    EnduranceRunStatus? status,
    EnduranceSettings? settings,
    int? totalCycles,
    int? doneCycles,
    int? passCount,
    int? failCount,
    Object? activeCycle = _sentinel,
    Object? message = _sentinel,
    Object? reportPath = _sentinel,
    Object? summaryPath = _sentinel,
    Object? lastOutcome = _sentinel,
    Map<String, int>? failureCounts,
    List<EnduranceCycleRecord>? records,
    List<String>? logs,
  }) {
    return EnduranceState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      totalCycles: totalCycles ?? this.totalCycles,
      doneCycles: doneCycles ?? this.doneCycles,
      passCount: passCount ?? this.passCount,
      failCount: failCount ?? this.failCount,
      activeCycle:
          identical(activeCycle, _sentinel) ? this.activeCycle : activeCycle as int?,
      message: identical(message, _sentinel) ? this.message : message as String?,
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

final enduranceProvider =
    StateNotifierProvider<EnduranceController, EnduranceState>(
  (ref) => EnduranceController(ref),
);

class EnduranceController extends StateNotifier<EnduranceState> {
  EnduranceController(this._ref) : super(EnduranceState.initial());

  static const Duration _scanWindow = Duration(seconds: 4);
  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _disconnectTimeout = Duration(seconds: 8);
  static const Duration _postRunDisconnectTimeout = Duration(seconds: 4);
  static const int _maxLogs = 200;
  static final List<Color> _startupPalette = <Color>[
    const Color(0xFFFF0000),
    const Color(0xFFFF8000),
    const Color(0xFFFFFF00),
    const Color(0xFF00FFFF),
    const Color(0xFF0080FF),
  ];

  final Ref _ref;
  final app_logger.Logger _log = app_logger.Logger();

  bool _stopRequested = false;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  BleClient get _client => _ref.read(bleClientProvider);
  StockController get _stock => _ref.read(stockProvider.notifier);
  LedController get _led => _ref.read(ledControllerProvider);

  Future<void> start({
    required int cycles,
    required double connectWaitSeconds,
    required double disconnectWaitSeconds,
    required bool scanBeforeConnect,
    required bool runStartupWave,
    required bool runGattCheck,
    required bool stopOnFail,
  }) async {
    if (state.isRunning) {
      return;
    }

    final validationError = await _validateBeforeStart(
      cycles: cycles,
      connectWaitSeconds: connectWaitSeconds,
      disconnectWaitSeconds: disconnectWaitSeconds,
    );
    if (validationError != null) {
      state = state.copyWith(
        status: EnduranceRunStatus.failed,
        message: validationError,
      );
      _appendLog('[ENDURANCE] validation failed: $validationError');
      return;
    }

    final settings = EnduranceSettings(
      cycles: cycles,
      connectWaitSeconds: connectWaitSeconds,
      disconnectWaitSeconds: disconnectWaitSeconds,
      scanBeforeConnect: scanBeforeConnect,
      runStartupWave: runStartupWave,
      runGattCheck: runGattCheck,
      stopOnFail: stopOnFail,
    );

    _stopRequested = false;
    state = EnduranceState.initial().copyWith(
      status: EnduranceRunStatus.running,
      settings: settings,
      totalCycles: cycles,
      message: 'Endurance run started',
    );
    _appendLog('[ENDURANCE] start cycles=$cycles');

    unawaited(_runLoop(settings));
  }

  void stop() {
    if (!state.isRunning) {
      return;
    }
    _stopRequested = true;
    _appendLog('[ENDURANCE] stop requested');
    unawaited(_scanSubscription?.cancel());
    _scanSubscription = null;
  }

  Future<String?> _validateBeforeStart({
    required int cycles,
    required double connectWaitSeconds,
    required double disconnectWaitSeconds,
  }) async {
    if (cycles <= 0) {
      return 'Cycles must be greater than 0.';
    }
    if (connectWaitSeconds < 0 || disconnectWaitSeconds < 0) {
      return 'Wait time must be 0 or more.';
    }
    await _stock.ensureLoaded();
    final stockState = _ref.read(stockProvider);
    if (!stockState.registered) {
      return 'Assign A and B devices before starting endurance.';
    }
    if (stockState.hasPairMismatch) {
      return 'N mismatch: A=${stockState.a.pairNumber}, B=${stockState.b.pairNumber}';
    }
    if (stockState.roleMismatchA || stockState.roleMismatchB) {
      return 'Role mismatch: odd device number = A, even = B.';
    }
    final granted = await _ensurePermissions();
    if (!granted) {
      return 'BLE permissions not granted.';
    }
    return null;
  }

  Future<void> _runLoop(EnduranceSettings settings) async {
    try {
      await _stock.disconnectBoth();
      await _stock.waitForBothDisconnected(_postRunDisconnectTimeout);

      for (int cycle = 1; cycle <= settings.cycles; cycle++) {
        _throwIfStopRequested();
        state = state.copyWith(activeCycle: cycle, message: 'Cycle $cycle running');
        final record = await _runCycle(cycle, settings);
        final nextRecords = <EnduranceCycleRecord>[...state.records, record];
        final nextCounts = <String, int>{...state.failureCounts};
        nextCounts[record.failureClass] = (nextCounts[record.failureClass] ?? 0) + 1;

        state = state.copyWith(
          doneCycles: cycle,
          passCount: state.passCount + (record.result == 'PASS' ? 1 : 0),
          failCount: state.failCount + (record.result == 'FAIL' ? 1 : 0),
          activeCycle: null,
          lastOutcome:
              'cycle ${record.cycle} ${record.result} (${record.failureClass})',
          failureCounts: nextCounts,
          records: nextRecords,
          message: record.result == 'PASS'
              ? 'Cycle ${record.cycle} passed'
              : 'Cycle ${record.cycle} failed: ${record.failureClass}',
        );

        if (record.result == 'FAIL' && settings.stopOnFail) {
          _appendLog('[ENDURANCE] stop on fail at cycle=$cycle');
          break;
        }
      }

      await _stock.disconnectBoth();
      await _stock.waitForBothDisconnected(_postRunDisconnectTimeout);
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: _stopRequested ? EnduranceRunStatus.stopped : EnduranceRunStatus.done,
        activeCycle: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message: _stopRequested
            ? 'Endurance run stopped'
            : 'Endurance run finished',
      );
      if (reportPaths != null) {
        _appendLog('[ENDURANCE] report ${reportPaths.$1}');
        _appendLog('[ENDURANCE] summary ${reportPaths.$2}');
      }
    } on _StopRequested {
      await _stock.disconnectBoth();
      await _stock.waitForBothDisconnected(_postRunDisconnectTimeout);
      final reportPaths = await _exportReports();
      state = state.copyWith(
        status: EnduranceRunStatus.stopped,
        activeCycle: null,
        reportPath: reportPaths?.$1,
        summaryPath: reportPaths?.$2,
        message: 'Endurance run stopped',
      );
    } catch (e, st) {
      _log.e('endurance run failed', error: e, stackTrace: st);
      await _stock.disconnectBoth();
      await _stock.waitForBothDisconnected(_postRunDisconnectTimeout);
      state = state.copyWith(
        status: EnduranceRunStatus.error,
        activeCycle: null,
        message: e.toString(),
      );
      _appendLog('[ENDURANCE] error: $e');
    }
  }

  Future<EnduranceCycleRecord> _runCycle(
    int cycle,
    EnduranceSettings settings,
  ) async {
    final cycleLogs = <String>[];
    void cycleLog(String message) {
      final entry = '[CYCLE ${cycle.toString().padLeft(3, '0')}] $message';
      cycleLogs.add(entry);
      _appendLog(entry);
    }

    final startedAt = DateTime.now();
    final scanWatch = Stopwatch()..start();
    bool scanOk = true;
    String failureClass = 'PASS';
    String failureDetail = '';

    cycleLog('start $cycle/${settings.cycles}');
    if (settings.scanBeforeConnect) {
      final scanResult = await _scanAssignedDevices();
      scanOk = scanResult.ok;
      if (!scanOk) {
        failureClass = 'ADV_NOT_FOUND';
        failureDetail = scanResult.detail;
        cycleLog('scan failed: ${scanResult.detail}');
      } else {
        cycleLog('scan ok');
      }
    }
    scanWatch.stop();
    _throwIfStopRequested();

    final connectWatch = Stopwatch()..start();
    bool connectOk = false;
    if (scanOk) {
      await _stock.connectBoth();
      connectOk = await _stock.waitForBothConnected(_connectTimeout);
      if (connectOk) {
        cycleLog('connect ok');
        await _interruptibleDelay(
          Duration(milliseconds: (settings.connectWaitSeconds * 1000).round()),
        );
      } else {
        failureClass = 'CONNECT_FAILED';
        failureDetail = 'Timed out waiting for A/B connection';
        cycleLog('connect failed');
      }
    }
    connectWatch.stop();
    _throwIfStopRequested();

    final gattWatch = Stopwatch()..start();
    bool gattOk = false;
    if (connectOk) {
      gattOk = true;
      if (settings.runStartupWave) {
        final startupError = await _runStartupWaveAll();
        if (startupError != null) {
          gattOk = false;
          failureClass = 'LED_WRITE_FAIL';
          failureDetail = startupError;
          cycleLog('startup wave failed: $startupError');
        } else {
          cycleLog('startup wave ok');
        }
      }
      if (gattOk && settings.runGattCheck) {
        final gattError = await _runGattChecks();
        if (gattError != null) {
          gattOk = false;
          if (gattError.startsWith('PROFILE:')) {
            failureClass = 'PROFILE_MISSING';
            failureDetail = gattError.replaceFirst('PROFILE:', '').trim();
          } else {
            failureClass = 'GATT_TIMEOUT_OR_READ_FAIL';
            failureDetail = gattError;
          }
          cycleLog('gatt failed: $failureDetail');
        } else {
          cycleLog('gatt ok');
        }
      }
    }
    gattWatch.stop();
    _throwIfStopRequested();

    final disconnectWatch = Stopwatch()..start();
    await _stock.disconnectBoth();
    if (settings.disconnectWaitSeconds > 0) {
      await _interruptibleDelay(
        Duration(milliseconds: (settings.disconnectWaitSeconds * 1000).round()),
      );
    }
    final disconnectOk =
        await _stock.waitForBothDisconnected(_disconnectTimeout);
    disconnectWatch.stop();
    if (!disconnectOk && failureClass == 'PASS') {
      failureClass = 'DISCONNECT_INCOMPLETE';
      failureDetail = 'Timed out waiting for A/B disconnect';
      cycleLog('disconnect failed');
    } else {
      cycleLog(disconnectOk ? 'disconnect ok' : 'disconnect timed out');
    }

    final result =
        scanOk && connectOk && gattOk && disconnectOk ? 'PASS' : 'FAIL';
    if (result == 'PASS') {
      failureClass = 'PASS';
      failureDetail = '';
    }

    final endedAt = DateTime.now();
    cycleLog(
      '$result scan=${scanWatch.elapsedMilliseconds}ms '
      'connect=${connectWatch.elapsedMilliseconds}ms '
      'gatt=${gattWatch.elapsedMilliseconds}ms '
      'disconnect=${disconnectWatch.elapsedMilliseconds}ms '
      'class=$failureClass',
    );

    return EnduranceCycleRecord(
      cycle: cycle,
      startedAt: startedAt,
      endedAt: endedAt,
      result: result,
      failureClass: failureClass,
      failureDetail: failureDetail,
      scanDuration: scanWatch.elapsed,
      connectDuration: connectWatch.elapsed,
      gattDuration: gattWatch.elapsed,
      disconnectDuration: disconnectWatch.elapsed,
      scanOk: scanOk,
      connectOk: connectOk,
      gattOk: gattOk,
      disconnectOk: disconnectOk,
      lastLog: cycleLogs.skip(cycleLogs.length > 6 ? cycleLogs.length - 6 : 0).join(' || '),
    );
  }

  Future<_PhaseResult> _scanAssignedDevices() async {
    final stockState = _ref.read(stockProvider);
    final expectedA = stockState.a.device;
    final expectedB = stockState.b.device;
    if (expectedA == null || expectedB == null) {
      return const _PhaseResult(false, 'Devices A/B are not assigned');
    }

    final found = <StockSide, bool>{
      StockSide.a: false,
      StockSide.b: false,
    };
    Object? error;
    StackTrace? stackTrace;
    final completer = Completer<void>();

    await _scanSubscription?.cancel();
    _scanSubscription = _client.scan(nameHint: Env.nameHint).listen(
      (device) {
        if (_matchesDevice(device, expectedA)) {
          found[StockSide.a] = true;
        }
        if (_matchesDevice(device, expectedB)) {
          found[StockSide.b] = true;
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
      await Future.any<void>([
        completer.future,
        Future<void>.delayed(_scanWindow),
      ]);
    } finally {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    _throwIfStopRequested();

    if (error != null) {
      _log.w('scan failed', error: error, stackTrace: stackTrace);
      return _PhaseResult(false, error.toString());
    }
    if (!found[StockSide.a]! || !found[StockSide.b]!) {
      return _PhaseResult(
        false,
        'A=${found[StockSide.a]! ? 'OK' : 'NG'} '
        'B=${found[StockSide.b]! ? 'OK' : 'NG'}',
      );
    }
    return const _PhaseResult(true, 'OK');
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

  Future<String?> _runStartupWaveAll() async {
    final stockState = _ref.read(stockProvider);
    final ledUiState = _ref.read(ledUiProvider);
    final stepMs = (1200 / _startupPalette.length).round().clamp(60, 5000);
    final devices = <StockSide, BleDevice?>{
      StockSide.a: stockState.a.device,
      StockSide.b: stockState.b.device,
    };

    try {
      for (final entry in devices.entries) {
        final device = entry.value;
        if (device == null) {
          return 'Missing device ${entry.key.name.toUpperCase()}';
        }
        final sideUi = ledUiState.sideState(entry.key);
        await _led.setOutputEnabled(device.id, true);
        await _led.setBrightness(device.id, sideUi.brightness.round());
      }

      for (final color in _startupPalette) {
        _throwIfStopRequested();
        await Future.wait(
          devices.entries.map((entry) async {
            final device = entry.value!;
            await _led.setTopColor(
              deviceId: device.id,
              side: entry.key,
              color: color,
            );
            await _led.setBottomColor(
              deviceId: device.id,
              side: entry.key,
              color: color,
            );
          }),
        );
        await _interruptibleDelay(Duration(milliseconds: stepMs));
      }
      return null;
    } catch (e, st) {
      _log.w('startup wave failed', error: e, stackTrace: st);
      return e.toString();
    }
  }

  Future<String?> _runGattChecks() async {
    for (final side in StockSide.values) {
      _throwIfStopRequested();
      final battery = await _stock.readBattery(side);
      if (battery == null || battery <= 0) {
        return 'Battery read failed on ${side.name.toUpperCase()}';
      }
      final profileError = await _stock.verifyGattProfile(side);
      if (profileError != null) {
        return 'PROFILE: $profileError';
      }
    }
    return null;
  }

  Future<(String, String)?> _exportReports() async {
    if (state.records.isEmpty) {
      return null;
    }
    final directory = await _resolveReportDirectory();
    final stamp = _timestampForFile(DateTime.now());
    final detailPath = '${directory.path}${Platform.pathSeparator}endurance_report_$stamp.csv';
    final summaryPath =
        '${directory.path}${Platform.pathSeparator}endurance_report_summary_$stamp.csv';

    final detailBuffer = StringBuffer()
      ..writeln(_csvRow(const <Object?>[
        'cycle',
        'start_iso',
        'end_iso',
        'result',
        'failure_class',
        'failure_detail',
        'scan_ms',
        'connect_ms',
        'gatt_ms',
        'disconnect_ms',
        'total_ms',
        'scan_ok',
        'connect_ok',
        'gatt_ok',
        'disconnect_ok',
        'last_log',
      ]));

    for (final record in state.records) {
      detailBuffer.writeln(
        _csvRow(<Object?>[
          record.cycle,
          _timestampIso(record.startedAt),
          _timestampIso(record.endedAt),
          record.result,
          record.failureClass,
          record.failureDetail,
          record.scanDuration.inMilliseconds,
          record.connectDuration.inMilliseconds,
          record.gattDuration.inMilliseconds,
          record.disconnectDuration.inMilliseconds,
          record.totalDuration.inMilliseconds,
          record.scanOk,
          record.connectOk,
          record.gattOk,
          record.disconnectOk,
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
    summaryBuffer.writeln(_csvRow(<Object?>['TOTAL', state.records.length]));
    summaryBuffer.writeln(
      _csvRow(<Object?>[
        'PASS_RATE(%)',
        ((state.passCount / state.records.length) * 100).toStringAsFixed(2),
      ]),
    );

    await File(detailPath).writeAsString(detailBuffer.toString());
    await File(summaryPath).writeAsString(summaryBuffer.toString());
    return (detailPath, summaryPath);
  }

  Future<Directory> _resolveReportDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${baseDir.path}${Platform.pathSeparator}endurance_reports',
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

  const _PhaseResult(this.ok, this.detail);
}

class _StopRequested implements Exception {
  const _StopRequested();
}
