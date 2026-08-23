import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart' as app_logger;
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

enum McuTransportMode { bridge, usb }

class McuStateEvent {
  final int index;
  final String state;
  final String detail;
  final Map<String, String> detailMap;
  final String raw;

  const McuStateEvent({
    required this.index,
    required this.state,
    required this.detail,
    required this.detailMap,
    required this.raw,
  });
}

class McuSerialState {
  final McuTransportMode transportMode;
  final String bridgeHost;
  final int bridgePort;
  final List<UsbDevice> devices;
  final String? selectedDeviceId;
  final String? connectedDeviceId;
  final bool connected;
  final String statusText;
  final String? message;
  final List<String> logs;
  final List<McuStateEvent> events;

  const McuSerialState({
    required this.transportMode,
    required this.bridgeHost,
    required this.bridgePort,
    required this.devices,
    required this.selectedDeviceId,
    required this.connectedDeviceId,
    required this.connected,
    required this.statusText,
    required this.message,
    required this.logs,
    required this.events,
  });

  factory McuSerialState.initial() {
    return const McuSerialState(
      transportMode: McuTransportMode.bridge,
      bridgeHost: '127.0.0.1',
      bridgePort: 9876,
      devices: <UsbDevice>[],
      selectedDeviceId: null,
      connectedDeviceId: null,
      connected: false,
      statusText: 'IDLE',
      message: null,
      logs: <String>[],
      events: <McuStateEvent>[],
    );
  }

  McuSerialState copyWith({
    McuTransportMode? transportMode,
    String? bridgeHost,
    int? bridgePort,
    List<UsbDevice>? devices,
    Object? selectedDeviceId = _sentinel,
    Object? connectedDeviceId = _sentinel,
    bool? connected,
    String? statusText,
    Object? message = _sentinel,
    List<String>? logs,
    List<McuStateEvent>? events,
  }) {
    return McuSerialState(
      transportMode: transportMode ?? this.transportMode,
      bridgeHost: bridgeHost ?? this.bridgeHost,
      bridgePort: bridgePort ?? this.bridgePort,
      devices: devices ?? this.devices,
      selectedDeviceId: identical(selectedDeviceId, _sentinel)
          ? this.selectedDeviceId
          : selectedDeviceId as String?,
      connectedDeviceId: identical(connectedDeviceId, _sentinel)
          ? this.connectedDeviceId
          : connectedDeviceId as String?,
      connected: connected ?? this.connected,
      statusText: statusText ?? this.statusText,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      logs: logs ?? this.logs,
      events: events ?? this.events,
    );
  }
}

const Object _sentinel = Object();

final mcuSerialProvider =
    StateNotifierProvider<McuSerialController, McuSerialState>(
  (ref) => McuSerialController(),
);

class McuSerialController extends StateNotifier<McuSerialState> {
  McuSerialController() : super(McuSerialState.initial());

  static const int _maxLogs = 300;
  static const Set<String> _readyStates = <String>{
    'MCU_READY',
    'POWER_A_ON',
    'POWER_A_OFF',
  };

  final app_logger.Logger _log = app_logger.Logger();
  UsbPort? _port;
  Transaction<String>? _transaction;
  Socket? _socket;
  StreamSubscription<String>? _lineSubscription;
  final List<Completer<void>> _stateWaiters = <Completer<void>>[];
  final List<Completer<void>> _lineWaiters = <Completer<void>>[];
  bool _disposing = false;

  bool get _isActive => mounted && !_disposing;

  void _setStateSafely(McuSerialState next) {
    if (!_isActive) {
      return;
    }
    state = next;
  }

  void _completeWaiters() {
    for (final waiter in _stateWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _stateWaiters.clear();
    for (final waiter in _lineWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _lineWaiters.clear();
  }

  Future<void> _closeTransport() async {
    final lineSubscription = _lineSubscription;
    _lineSubscription = null;
    await lineSubscription?.cancel();

    final transaction = _transaction;
    _transaction = null;
    transaction?.dispose();

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.flush();
      } catch (_) {
        // Ignore flush failures during teardown.
      }
      try {
        await socket.close();
      } catch (_) {
        // Ignore close failures during teardown.
      }
    }

    final port = _port;
    _port = null;
    if (port != null) {
      try {
        await port.close();
      } catch (_) {
        // Ignore close failures during teardown.
      }
    }
  }

  void setTransportMode(McuTransportMode transportMode) {
    _setStateSafely(state.copyWith(
      transportMode: transportMode,
      message: null,
    ));
  }

  void setBridgeEndpoint({
    String? host,
    int? port,
  }) {
    _setStateSafely(state.copyWith(
      bridgeHost: host ?? state.bridgeHost,
      bridgePort: port ?? state.bridgePort,
      message: null,
    ));
  }

  Future<void> refreshDevices() async {
    if (state.transportMode != McuTransportMode.usb) {
      _setStateSafely(state.copyWith(message: null));
      return;
    }
    try {
      final devices = await UsbSerial.listDevices();
      if (!_isActive) {
        return;
      }
      final selectedId = state.selectedDeviceId;
      final hasSelected = selectedId != null &&
          devices.any((device) => '${device.deviceId}' == selectedId);
      _setStateSafely(state.copyWith(
        devices: devices,
        selectedDeviceId: hasSelected
            ? selectedId
            : (devices.isNotEmpty ? '${devices.first.deviceId}' : null),
        message: null,
      ));
    } catch (e, st) {
      _log.e('mcu refresh devices failed', error: e, stackTrace: st);
      _setStateSafely(state.copyWith(message: 'USB device scan failed: $e'));
    }
  }

  void selectDeviceId(String? deviceId) {
    _setStateSafely(
      state.copyWith(selectedDeviceId: deviceId, message: null),
    );
  }

  Future<bool> connect({
    String? deviceId,
    int baudRate = 115200,
  }) async {
    await disconnect();
    if (state.transportMode == McuTransportMode.bridge) {
      return _connectBridge();
    }
    return _connectUsb(deviceId: deviceId, baudRate: baudRate);
  }

  Future<bool> _connectBridge() async {
    final host = state.bridgeHost.trim();
    final port = state.bridgePort;
    if (host.isEmpty || port <= 0 || port > 65535) {
      _setStateSafely(state.copyWith(
        message: 'Enter a valid MCU bridge host/port.',
        statusText: 'ERROR',
      ));
      return false;
    }

    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      _lineSubscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleLine,
        onError: (Object error, StackTrace stackTrace) {
          _appendLog('[MCU] bridge read error: $error');
          _setStateSafely(state.copyWith(
            connected: false,
            connectedDeviceId: null,
            statusText: 'ERROR',
            message: 'MCU bridge read failed: $error',
          ));
        },
      );

      final label = 'BRIDGE $host:$port';
      _setStateSafely(state.copyWith(
        connected: true,
        connectedDeviceId: 'bridge://$host:$port',
        statusText: 'RUNNING ($label)',
        message: null,
      ));
      _appendLog('[MCU] connected $label');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final startIndex = state.logs.length;
      final pingOk = await sendLine('r');
      if (!pingOk) {
        await disconnect();
        _setStateSafely(state.copyWith(
          statusText: 'ERROR',
          message:
              'MCU bridge connected but the round-trip check failed during send.',
        ));
        return false;
      }
      final log = await waitForLogContains(
        '[PWR]',
        timeout: const Duration(seconds: 3),
        startIndex: startIndex,
      );
      if (log == null) {
        await disconnect();
        _setStateSafely(state.copyWith(
          statusText: 'ERROR',
          message:
              'MCU bridge connected, but the UNO did not answer the serial round-trip check. Check the bridge process and COM port.',
        ));
        return false;
      }
      return true;
    } catch (e, st) {
      _log.e('mcu bridge connect failed', error: e, stackTrace: st);
      _setStateSafely(state.copyWith(
        connected: false,
        connectedDeviceId: null,
        statusText: 'ERROR',
        message:
            'MCU bridge connect failed: $e. Start the PC bridge and adb reverse first.',
      ));
      return false;
    }
  }

  Future<bool> _connectUsb({
    String? deviceId,
    required int baudRate,
  }) async {
    if (state.devices.isEmpty) {
      await refreshDevices();
    }
    final targetId = deviceId ?? state.selectedDeviceId;
    final device = _deviceById(targetId) ??
        (state.devices.isNotEmpty ? state.devices.first : null);
    if (device == null) {
      _setStateSafely(state.copyWith(message: 'No USB serial device found.'));
      return false;
    }

    try {
      final port = await device.create();
      if (port == null) {
        _setStateSafely(state.copyWith(
          message: 'Unable to create USB serial port.',
          selectedDeviceId: '${device.deviceId}',
        ));
        return false;
      }
      final opened = await port.open();
      if (!opened) {
        _setStateSafely(state.copyWith(
          message: 'USB serial open failed.',
          selectedDeviceId: '${device.deviceId}',
        ));
        return false;
      }
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _port = port;
      _transaction = Transaction.stringTerminated(
        port.inputStream!,
        Uint8List.fromList(<int>[13, 10]),
      );
      _lineSubscription = _transaction!.stream.listen(
        _handleLine,
        onError: (Object error, StackTrace stackTrace) {
          _appendLog('[MCU] read error: $error');
          _setStateSafely(state.copyWith(
            connected: false,
            connectedDeviceId: null,
            statusText: 'ERROR',
            message: 'USB serial read failed: $error',
          ));
        },
      );

      _setStateSafely(state.copyWith(
        connected: true,
        selectedDeviceId: '${device.deviceId}',
        connectedDeviceId: '${device.deviceId}',
        statusText: 'RUNNING (${_deviceLabel(device)})',
        message: null,
      ));
      _appendLog('[MCU] connected ${_deviceLabel(device)}');
      return true;
    } catch (e, st) {
      _log.e('mcu usb connect failed', error: e, stackTrace: st);
      _setStateSafely(state.copyWith(
        connected: false,
        connectedDeviceId: null,
        statusText: 'ERROR',
        message: 'USB serial connect failed: $e',
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    _completeWaiters();
    await _closeTransport();
    _setStateSafely(state.copyWith(
      connected: false,
      connectedDeviceId: null,
      statusText: 'IDLE',
    ));
  }

  void clearStateHistory() {
    _setStateSafely(state.copyWith(events: <McuStateEvent>[]));
  }

  Future<bool> sendLine(String line) async {
    try {
      if (_socket != null) {
        _socket!.add(utf8.encode('$line\r\n'));
        await _socket!.flush();
        _appendLog('[SERIAL->MCU] $line');
        return true;
      }
      final port = _port;
      if (port == null) {
        _appendLog('[MCU] send skipped (not connected)');
        return false;
      }
      final payload = Uint8List.fromList(utf8.encode('$line\r\n'));
      await port.write(payload);
      _appendLog('[SERIAL->MCU] $line');
      return true;
    } catch (e, st) {
      _log.e('mcu send failed', error: e, stackTrace: st);
      _setStateSafely(state.copyWith(message: 'MCU send failed: $e'));
      return false;
    }
  }

  Future<McuStateEvent?> waitForState(
    Set<String> states, {
    required Duration timeout,
    int startIndex = 0,
    String detailContains = '',
  }) async {
    final deadline = DateTime.now().add(timeout);
    var index = startIndex.clamp(0, state.events.length);
    final detailFilter = detailContains.trim();

    while (true) {
      final snapshot = state.events;
      for (final event in snapshot.skip(index)) {
        if (!states.contains(event.state)) {
          continue;
        }
        if (detailFilter.isNotEmpty && !event.detail.contains(detailFilter)) {
          continue;
        }
        return event;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return null;
      }
      final waiter = Completer<void>();
      _stateWaiters.add(waiter);
      index = state.events.length;
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        if (_stateWaiters.contains(waiter)) {
          _stateWaiters.remove(waiter);
        }
        return null;
      } finally {
        _stateWaiters.remove(waiter);
      }
    }
  }

  Future<String?> waitForLogContains(
    String pattern, {
    required Duration timeout,
    int startIndex = 0,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var index = startIndex.clamp(0, state.logs.length);
    final needle = pattern.trim();
    if (needle.isEmpty) {
      return null;
    }

    while (true) {
      final snapshot = state.logs;
      for (final line in snapshot.skip(index)) {
        if (line.contains(needle)) {
          return line;
        }
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return null;
      }
      final waiter = Completer<void>();
      _lineWaiters.add(waiter);
      index = state.logs.length;
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        if (_lineWaiters.contains(waiter)) {
          _lineWaiters.remove(waiter);
        }
        return null;
      } finally {
        _lineWaiters.remove(waiter);
      }
    }
  }

  Future<McuStateEvent?> sendCommandWait(
    String line,
    String expectedState, {
    required Duration timeout,
    String detailContains = '',
  }) async {
    final startIndex = state.events.length;
    final sent = await sendLine(line);
    if (!sent) {
      return null;
    }
    return waitForState(
      <String>{expectedState},
      timeout: timeout,
      startIndex: startIndex,
      detailContains: detailContains,
    );
  }

  Future<bool> ensureReady() async {
    if (!state.connected) {
      final ok = await connect();
      if (!ok) {
        return false;
      }
    }
    if (_hasReadyState()) {
      return true;
    }
    final ready = await _probeReadyStatus();
    if (ready) {
      return true;
    }
    _setStateSafely(state.copyWith(
      message: state.transportMode == McuTransportMode.bridge
          ? 'MCU ready check failed. The bridge is up, but the UNO did not return status. Reconnect MCU or restart the PC bridge.'
          : 'MCU ready check failed after serial start.',
    ));
    return false;
  }

  void _handleLine(String line) {
    if (!_isActive) {
      return;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _appendLog(trimmed);
    if (!trimmed.startsWith('[STATE] ')) {
      return;
    }
    final body = trimmed.substring(8).trim();
    if (body.isEmpty) {
      return;
    }
    final firstSpace = body.indexOf(' ');
    final stateName = firstSpace < 0 ? body : body.substring(0, firstSpace);
    final detail = firstSpace < 0 ? '' : body.substring(firstSpace + 1).trim();
    final detailMap = <String, String>{};
    if (detail.isNotEmpty) {
      for (final token in detail.split(RegExp(r'\s+'))) {
        final equals = token.indexOf('=');
        if (equals <= 0 || equals >= token.length - 1) {
          continue;
        }
        detailMap[token.substring(0, equals)] = token.substring(equals + 1);
      }
    }
    final event = McuStateEvent(
      index: state.events.length,
      state: stateName,
      detail: detail,
      detailMap: detailMap,
      raw: trimmed,
    );
    if (!_isActive) {
      return;
    }
    final current = state;
    _setStateSafely(
      current.copyWith(events: <McuStateEvent>[...current.events, event]),
    );
    for (final waiter in List<Completer<void>>.from(_stateWaiters)) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  void _appendLog(String line) {
    if (!_isActive) {
      return;
    }
    final current = state;
    final nextLogs = <String>[...current.logs, line];
    if (nextLogs.length > _maxLogs) {
      nextLogs.removeRange(0, nextLogs.length - _maxLogs);
    }
    if (!_isActive) {
      return;
    }
    _setStateSafely(current.copyWith(logs: nextLogs));
    for (final waiter in List<Completer<void>>.from(_lineWaiters)) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  bool _hasReadyState() {
    for (final event in state.events.reversed) {
      if (_readyStates.contains(event.state)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _probeReadyStatus({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final startIndex = state.logs.length;
    final sent = await sendLine('r');
    if (!sent) {
      return false;
    }
    final log = await waitForLogContains(
      '[PWR]',
      timeout: timeout,
      startIndex: startIndex,
    );
    return log != null;
  }

  UsbDevice? _deviceById(String? deviceId) {
    if (deviceId == null) {
      return null;
    }
    for (final device in state.devices) {
      if ('${device.deviceId}' == deviceId) {
        return device;
      }
    }
    return null;
  }

  String _deviceLabel(UsbDevice device) {
    final name = (device.productName ?? '').trim();
    if (name.isNotEmpty) {
      return name;
    }
    return 'USB ${device.deviceId}';
  }

  @override
  void dispose() {
    _disposing = true;
    _completeWaiters();
    unawaited(_closeTransport());
    super.dispose();
  }
}
