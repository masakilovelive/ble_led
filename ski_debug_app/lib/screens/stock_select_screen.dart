import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';
import 'bluetooth_setup_screen.dart';
import 'led_setting_screen.dart';

class StockSelectScreen extends ConsumerStatefulWidget {
  const StockSelectScreen({super.key});

  @override
  ConsumerState<StockSelectScreen> createState() => _StockSelectScreenState();
}

class _StockSelectScreenState extends ConsumerState<StockSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rainbowController;
  Timer? _heartbeatTimer;
  bool _heartbeatOn = true;
  bool _permLoading = false;
  Map<Permission, PermissionStatus> _permStatus = {};

  @override
  void initState() {
    super.initState();
    _rainbowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _heartbeatOn = !_heartbeatOn);
    });
    _checkPermissions();
  }

  @override
  void dispose() {
    _rainbowController.dispose();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(ledUiProvider);
    final stockState = ref.watch(stockProvider);
    final rainbowAngle = _rainbowController.value * math.pi * 2;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Stock Select'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Bluetooth Setup',
            onPressed: () => _openBluetoothSetup(context),
            icon: const Icon(Icons.bluetooth),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 380;
          final columns = [
            _StockColumn(
              label: 'A',
              sideUi: uiState.a,
              connectionState: stockState.a.status,
              resyncStatus: stockState.a.resyncStatus,
              resyncNote: stockState.a.resyncNote,
              heartbeatOn: _heartbeatOn,
              rainbowAngle: rainbowAngle,
              onTap: () => _openSetting(context, StockSide.a),
              onConnect: () =>
                  ref.read(stockProvider.notifier).connect(StockSide.a),
            ),
            _StockColumn(
              label: 'B',
              sideUi: uiState.b,
              connectionState: stockState.b.status,
              resyncStatus: stockState.b.resyncStatus,
              resyncNote: stockState.b.resyncNote,
              heartbeatOn: _heartbeatOn,
              rainbowAngle: rainbowAngle,
              onTap: () => _openSetting(context, StockSide.b),
              onConnect: () =>
                  ref.read(stockProvider.notifier).connect(StockSide.b),
            ),
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: narrow
                ? Column(
                    children: [
                      _buildPermissionPanel(),
                      const SizedBox(height: 16),
                      columns[0],
                      const SizedBox(height: 24),
                      columns[1],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildPermissionPanel(),
                            const SizedBox(height: 16),
                            columns[0],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: columns[1]),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _openSetting(BuildContext context, StockSide side) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LedSettingScreen(side: side),
      ),
    );
  }

  void _openBluetoothSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BluetoothSetupScreen(
          onRegistered: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    setState(() => _permLoading = true);
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    final location = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    setState(() {
      _permStatus = {
        Permission.bluetoothScan: scan,
        Permission.bluetoothConnect: connect,
        Permission.locationWhenInUse: location,
      };
      _permLoading = false;
    });
    await _logPermissionStatus('CHECK', _permStatus);
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;
    setState(() => _permLoading = true);
    final result = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (!mounted) return;
    setState(() {
      _permStatus = result;
      _permLoading = false;
    });
    await _logPermissionStatus('REQUEST', _permStatus);
  }

  Future<void> _logPermissionStatus(
    String action,
    Map<Permission, PermissionStatus> statuses,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/permission_log.csv');
      final exists = await file.exists();
      if (!exists) {
        await file.writeAsString(
          'timestamp,action,scan,connect,location,all_granted\n',
        );
      }
      final scan = statuses[Permission.bluetoothScan];
      final connect = statuses[Permission.bluetoothConnect];
      final location = statuses[Permission.locationWhenInUse];
      final allGranted = (scan?.isGranted ?? false) &&
          (connect?.isGranted ?? false) &&
          (location?.isGranted ?? false);
      final appLog = '[BLE_PERM] '
          'action=$action '
          'scan=${scan?.toString() ?? 'unknown'} '
          'connect=${connect?.toString() ?? 'unknown'} '
          'location=${location?.toString() ?? 'unknown'} '
          'all_granted=${allGranted ? 'true' : 'false'}';
      debugPrint(appLog);
      // ignore: avoid_print
      print(appLog);
      dev.log(appLog, name: 'SKI_BLE');
      final line = [
        DateTime.now().toIso8601String(),
        action,
        scan?.toString() ?? 'unknown',
        connect?.toString() ?? 'unknown',
        location?.toString() ?? 'unknown',
        allGranted ? 'true' : 'false',
      ].join(',');
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('permission log failed: $e');
    }
  }

  Widget _buildPermissionPanel() {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final items = [
      ('SCAN', Permission.bluetoothScan),
      ('CONNECT', Permission.bluetoothConnect),
      ('LOCATION', Permission.locationWhenInUse),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Permissions',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              final status = _permStatus[item.$2];
              return _PermissionChip(label: item.$1, status: status);
            }).toList(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _permLoading ? null : _checkPermissions,
                child: const Text('Check'),
              ),
              OutlinedButton(
                onPressed: _permLoading ? null : _requestPermissions,
                child: const Text('Request'),
              ),
              if (_permLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  final String label;
  final PermissionStatus? status;

  const _PermissionChip({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final statusText = _statusText(status);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        '$label: $statusText',
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  String _statusText(PermissionStatus? status) {
    if (status == null) return 'unknown';
    if (status.isGranted) return 'granted';
    if (status.isLimited) return 'limited';
    if (status.isPermanentlyDenied) return 'denied';
    if (status.isRestricted) return 'restricted';
    return 'denied';
    }

  Color _statusColor(PermissionStatus? status) {
    if (status == null) return Colors.white38;
    if (status.isGranted || status.isLimited) return Colors.greenAccent;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return Colors.orangeAccent;
    }
    return Colors.redAccent;
  }
}

class _StockColumn extends StatelessWidget {
  final String label;
  final LedUiSideState sideUi;
  final DeviceConnectionState connectionState;
  final ResyncStatus resyncStatus;
  final String? resyncNote;
  final bool heartbeatOn;
  final double rainbowAngle;
  final VoidCallback onTap;
  final VoidCallback onConnect;

  const _StockColumn({
    required this.label,
    required this.sideUi,
    required this.connectionState,
    required this.resyncStatus,
    required this.resyncNote,
    required this.heartbeatOn,
    required this.rainbowAngle,
    required this.onTap,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Text(label, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(height: 12),
        _ConnectionRow(
          connected: connectionState == DeviceConnectionState.connected,
          onConnect: onConnect,
        ),
        const SizedBox(height: 6),
        _ResyncStatusRow(status: resyncStatus, note: resyncNote),
        const SizedBox(height: 8),
        const Text('TOP', style: TextStyle(letterSpacing: 2)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: _StockFigure(
            topState: sideUi.top,
            bottomState: sideUi.bottom,
            heartbeatColor: sideUi.heartbeatColor,
            heartbeatOn: heartbeatOn,
            rainbowAngle: rainbowAngle,
            batteryPercent: sideUi.batteryPercent,
            batteryVoltage: sideUi.batteryVoltage,
          ),
        ),
        const SizedBox(height: 12),
        const Text('BOTTOM', style: TextStyle(letterSpacing: 2)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StockFigure extends StatelessWidget {
  final LedUiSegmentState topState;
  final LedUiSegmentState bottomState;
  final Color heartbeatColor;
  final bool heartbeatOn;
  final double rainbowAngle;
  final double batteryPercent;
  final double? batteryVoltage;

  const _StockFigure({
    required this.topState,
    required this.bottomState,
    required this.heartbeatColor,
    required this.heartbeatOn,
    required this.rainbowAngle,
    required this.batteryPercent,
    required this.batteryVoltage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StockSegmentCircle(
          mode: topState.mode,
          color: _segmentFillColor(topState, heartbeatColor, heartbeatOn),
          rainbowAngle: rainbowAngle,
        ),
        Container(
          width: 80,
          height: 18,
          color: Colors.white,
        ),
        const SizedBox(height: 8),
        _BatteryRect(
          percent: batteryPercent,
          voltage: batteryVoltage,
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: 18,
          color: Colors.white,
        ),
        _StockSegmentCircle(
          mode: bottomState.mode,
          color: _segmentFillColor(bottomState, heartbeatColor, heartbeatOn),
          rainbowAngle: rainbowAngle,
        ),
      ],
    );
  }

  Color _segmentFillColor(
    LedUiSegmentState state,
    Color heartbeatColor,
    bool heartbeatOn,
  ) {
    if (state.mode == LedMode.heartbeat) {
      return heartbeatOn ? heartbeatColor : Colors.black;
    }
    if (state.mode == LedMode.off) {
      return Colors.white;
    }
    return state.color;
  }
}

class _BatteryRect extends StatelessWidget {
  final double percent;
  final double? voltage;

  const _BatteryRect({required this.percent, this.voltage});

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 1.0);
    final safeVoltage =
        voltage != null && voltage! >= 2.0 && voltage! <= 5.5
            ? voltage
            : null;
    return Container(
      width: 70,
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          FractionallySizedBox(
            heightFactor: clamped,
            widthFactor: 1,
            child: Container(color: const Color(0xFF28A745)),
          ),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                safeVoltage != null
                    ? '${safeVoltage.toStringAsFixed(2)}V\n${(clamped * 100).round()}%'
                    : '${(clamped * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockSegmentCircle extends StatelessWidget {
  final LedMode mode;
  final Color color;
  final double rainbowAngle;

  const _StockSegmentCircle({
    required this.mode,
    required this.color,
    required this.rainbowAngle,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Colors.white, width: 2);
    BoxDecoration decoration;
    if (mode == LedMode.rainbow) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        gradient: SweepGradient(
          colors: const [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
          transform: GradientRotation(rainbowAngle),
        ),
      );
    } else {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: color,
      );
    }
    return Container(
      width: 54,
      height: 54,
      decoration: decoration,
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;

  const _ConnectionRow({
    required this.connected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? 'connected' : 'disconnected';
    final color = connected ? Colors.greenAccent : Colors.redAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            statusText,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 120,
          child: OutlinedButton(
            onPressed: connected ? null : onConnect,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
            child: const Text('Connect', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}

class _ResyncStatusRow extends StatelessWidget {
  final ResyncStatus status;
  final String? note;

  const _ResyncStatusRow({
    required this.status,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (status) {
      case ResyncStatus.running:
        label = 'resyncing...';
        color = Colors.amberAccent;
        break;
      case ResyncStatus.success:
        label = 'resync ok';
        color = Colors.greenAccent;
        break;
      case ResyncStatus.failed:
        label = 'resync failed';
        color = Colors.redAccent;
        break;
      case ResyncStatus.idle:
      default:
        label = 'resync idle';
        color = Colors.white38;
        break;
    }
    final noteText = (note ?? '').isNotEmpty ? ' (${note!})' : '';
    return Text(
      '$label$noteText',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11),
    );
  }
}
