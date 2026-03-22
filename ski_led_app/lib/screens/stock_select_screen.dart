import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/heartbeat_controller.dart';
import '../ble/led_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';
import 'led_setting_screen.dart';

enum EditZone { top, bottom, all }

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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Stock Select'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Stock'),
              Tab(text: 'Color'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _StockColumn(
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
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StockColumn(
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
                  ),
                ],
              ),
            ),
            _ColorTab(
              rainbowAngle: rainbowAngle,
              heartbeatOn: _heartbeatOn,
            ),
          ],
        ),
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
}

class _ColorTab extends ConsumerStatefulWidget {
  final double rainbowAngle;
  final bool heartbeatOn;

  const _ColorTab({
    required this.rainbowAngle,
    required this.heartbeatOn,
  });

  @override
  ConsumerState<_ColorTab> createState() => _ColorTabState();
}

class _ColorTabState extends ConsumerState<_ColorTab> {
  StockSide _editSide = StockSide.a;
  EditZone _zone = EditZone.top;
  bool _cheatMode = false;

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(ledUiProvider);
    final stockState = ref.watch(stockProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _buildStatusCard(StockSide.a, stockState, uiState)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatusCard(StockSide.b, stockState, uiState)),
          ],
        ),
        const SizedBox(height: 16),
        _buildEditSelector(),
        const SizedBox(height: 12),
        _buildZoneSelector(),
        const SizedBox(height: 16),
        _buildPreview(uiState),
        const SizedBox(height: 16),
        _buildControls(uiState, stockState),
        const SizedBox(height: 16),
        _buildCopyControls(),
        const SizedBox(height: 16),
        _buildCheatBanner(),
      ],
    );
  }

  Widget _buildStatusCard(
    StockSide side,
    StockState stockState,
    LedUiState uiState,
  ) {
    final sideState = side == StockSide.a ? stockState.a : stockState.b;
    final sideUi = side == StockSide.a ? uiState.a : uiState.b;
    final connected = sideState.status == DeviceConnectionState.connected;
    final color = connected ? Colors.greenAccent : Colors.redAccent;
    final label = side == StockSide.a ? 'stockA' : 'stockB';
    final batteryPct = (sideUi.batteryPercent * 100).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0F0F0F),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Text(connected ? 'connect OK' : 'connect NG',
              style: TextStyle(color: color)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: sideUi.batteryPercent.clamp(0.0, 1.0),
                    child: Container(color: const Color(0xFF28A745)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$batteryPct%', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditSelector() {
    return Row(
      children: [
        const Text('Edit target:', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 12),
        Opacity(
          opacity: _cheatMode ? 0.4 : 1,
          child: AbsorbPointer(
            absorbing: _cheatMode,
            child: ToggleButtons(
              isSelected: [_editSide == StockSide.a, _editSide == StockSide.b],
              onPressed: (idx) {
                setState(() => _editSide = idx == 0 ? StockSide.a : StockSide.b);
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('stockA'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('stockB'),
                ),
              ],
            ),
          ),
        ),
        if (_cheatMode) ...[
          const SizedBox(width: 12),
          const Text(
            'SYNC A+B',
            style: TextStyle(color: Color(0xFF28A745)),
          ),
        ],
      ],
    );
  }
  Widget _buildZoneSelector() {
    return Row(
      children: [
        const Text('Zone:', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 12),
        ToggleButtons(
          isSelected: [
            _zone == EditZone.top,
            _zone == EditZone.bottom,
            _zone == EditZone.all,
          ],
          onPressed: (idx) {
            setState(() {
              _zone = EditZone.values[idx];
            });
          },
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('TOP'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('BOTTOM'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('ALL'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(LedUiState uiState) {
    final sideUi = _editSide == StockSide.a ? uiState.a : uiState.b;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            const Text('TOP'),
            const SizedBox(height: 6),
            _StockSegmentCircle(
              mode: sideUi.top.mode,
              color: sideUi.top.color,
              rainbowAngle: widget.rainbowAngle,
            ),
          ],
        ),
        const SizedBox(width: 24),
        Column(
          children: [
            const Text('BOTTOM'),
            const SizedBox(height: 6),
            _StockSegmentCircle(
              mode: sideUi.bottom.mode,
              color: sideUi.bottom.color,
              rainbowAngle: widget.rainbowAngle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(LedUiState uiState, StockState stockState) {
    final sideUi = _editSide == StockSide.a ? uiState.a : uiState.b;
    final canOperate = _targets().any((side) => _deviceId(side) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Effects', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canOperate ? () => _startHeartbeat() : null,
              child: const Text('heart beat'),
            ),
            OutlinedButton(
              onPressed: canOperate ? () => _stopHeartbeat() : null,
              child: const Text('stop'),
            ),
            _buildHeartbeatLevelButton('LOW', 120, canOperate),
            _buildHeartbeatLevelButton('MIDDLE', 180, canOperate),
            _buildHeartbeatLevelButton('HIGH', 240, canOperate),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canOperate ? () => _startRainbow() : null,
              child: const Text('Start Rainbow'),
            ),
            OutlinedButton(
              onPressed: canOperate ? () => _stopRainbow() : null,
              child: const Text('Stop Rainbow'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Brightness ${sideUi.brightness.round()}'),
        Slider(
          value: sideUi.brightness,
          min: 0,
          max: 255,
          onChanged: (value) => _setBrightness(value),
          onChangeEnd: (value) => _commitBrightness(value),
        ),
        const SizedBox(height: 12),
        const Text('Color Palette'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, 220.0);
            return Center(
              child: SizedBox(
                width: size,
                height: size,
                child: ColorPicker(
                  pickerColor: _currentPickerColor(sideUi),
                  paletteType: PaletteType.hueWheel,
                  enableAlpha: false,
                  onColorChanged: (color) => _applyColor(color),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
  Widget _buildHeartbeatLevelButton(String label, int brightness, bool enabled) {
    return OutlinedButton(
      onPressed: enabled ? () => _setBrightness(brightness.toDouble()) : null,
      child: Text(label),
    );
  }

  Widget _buildCopyControls() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => _copySide(StockSide.a, StockSide.b),
          child: const Text('Copy A -> B'),
        ),
        OutlinedButton(
          onPressed: () => _copySide(StockSide.b, StockSide.a),
          child: const Text('Copy B -> A'),
        ),
        OutlinedButton(
          onPressed: _swapSides,
          child: const Text('Swap'),
        ),
      ],
    );
  }
  Widget _buildCheatBanner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_cheatMode)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B3B2F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF28A745)),
            ),
            child: const Text(
              'CHEAT (SYNC A+B) ACTIVE',
              style: TextStyle(color: Color(0xFF28A745)),
            ),
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onLongPress: _confirmCheat,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF28A745),
                  Color(0xFF4DD0E1),
                  Color(0xFFE53935),
                ],
              ),
            ),
            child: const Text(
              'CHEAT (long press)',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_cheatMode)
          OutlinedButton(
            onPressed: () => setState(() => _cheatMode = false),
            child: const Text('Exit CHEAT'),
          ),
      ],
    );
  }

  Future<void> _confirmCheat() async {
    if (_cheatMode) return;
    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enable CHEAT'),
          content: const Text('Sync A+B for all operations?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );
    if (shouldEnable == true && mounted) {
      setState(() => _cheatMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CHEAT mode enabled (sync A+B)')),
      );
    }
  }
  Color _currentPickerColor(LedUiSideState sideUi) {
    if (_zone == EditZone.bottom) return sideUi.bottom.color;
    return sideUi.top.color;
  }

  Iterable<StockSide> _targets() {
    return _cheatMode ? [StockSide.a, StockSide.b] : [_editSide];
  }

  String? _deviceId(StockSide side) {
    final stockState = ref.read(stockProvider);
    final sideState = side == StockSide.a ? stockState.a : stockState.b;
    return sideState.device?.id;
  }

  Future<void> _applyColor(Color color) async {
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      final deviceId = _deviceId(side);
      if (_zone == EditZone.top || _zone == EditZone.all) {
        uiNotifier.setSegmentMode(side, true, LedMode.color);
        uiNotifier.setSegmentColor(side, true, color);
        if (deviceId != null) {
          await led.setTopColor(deviceId: deviceId, side: side, color: color);
        }
      }
      if (_zone == EditZone.bottom || _zone == EditZone.all) {
        uiNotifier.setSegmentMode(side, false, LedMode.color);
        uiNotifier.setSegmentColor(side, false, color);
        if (deviceId != null) {
          await led.setBottomColor(deviceId: deviceId, side: side, color: color);
        }
      }
    }
  }

  void _setBrightness(double value) {
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      uiNotifier.setBrightness(side, value);
    }
    setState(() {});
  }

  Future<void> _commitBrightness(double value) async {
    final led = ref.read(ledControllerProvider);
    for (final side in _targets()) {
      final deviceId = _deviceId(side);
      if (deviceId != null) {
        await led.setBrightness(deviceId, value.round());
      }
    }
  }

  Future<void> _startRainbow() async {
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      uiNotifier.setBothMode(side, LedMode.rainbow);
      final deviceId = _deviceId(side);
      if (deviceId != null) {
        await led.setOutputEnabled(deviceId, true);
        await led.startRainbow(deviceId, intervalMs: 40);
      }
    }
  }

  Future<void> _stopRainbow() async {
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      uiNotifier.setBothMode(side, LedMode.off);
      final deviceId = _deviceId(side);
      if (deviceId != null) {
        await led.stopRainbow(deviceId);
      }
    }
  }

  Future<void> _startHeartbeat() async {
    final heartbeat = ref.read(heartbeatControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      uiNotifier.setBothMode(side, LedMode.heartbeat);
      final deviceId = _deviceId(side);
      if (deviceId != null) {
        heartbeat.start(side, deviceId);
      }
    }
  }

  Future<void> _stopHeartbeat() async {
    final heartbeat = ref.read(heartbeatControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targets()) {
      uiNotifier.setBothMode(side, LedMode.off);
      final deviceId = _deviceId(side);
      if (deviceId != null) {
        heartbeat.stop(side, deviceId: deviceId, sendOff: true, resetMode: true);
      }
    }
  }

  Future<void> _copySide(StockSide from, StockSide to) async {
    final uiState = ref.read(ledUiProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final fromUi = from == StockSide.a ? uiState.a : uiState.b;
    uiNotifier.setBrightness(to, fromUi.brightness);
    uiNotifier.setHeartbeatColor(to, fromUi.heartbeatColor);
    uiNotifier.setOutputEnabled(to, fromUi.outputEnabled);
    uiNotifier.setSegmentMode(to, true, fromUi.top.mode);
    uiNotifier.setSegmentColor(to, true, fromUi.top.color);
    uiNotifier.setSegmentMode(to, false, fromUi.bottom.mode);
    uiNotifier.setSegmentColor(to, false, fromUi.bottom.color);
    await _applyUiToDevice(to, fromUi);
  }

  Future<void> _swapSides() async {
    await _copySide(StockSide.a, StockSide.b);
    await _copySide(StockSide.b, StockSide.a);
  }

  Future<void> _applyUiToDevice(StockSide side, LedUiSideState sideUi) async {
    final deviceId = _deviceId(side);
    if (deviceId == null) return;
    final led = ref.read(ledControllerProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    if (!sideUi.outputEnabled) {
      await led.setOutputEnabled(deviceId, false);
      return;
    }
    await led.setOutputEnabled(deviceId, true);
    await led.setBrightness(deviceId, sideUi.brightness.round());
    if (sideUi.top.mode == LedMode.rainbow ||
        sideUi.bottom.mode == LedMode.rainbow) {
      await led.startRainbow(deviceId, intervalMs: 40);
      return;
    }
    if (sideUi.top.mode == LedMode.heartbeat ||
        sideUi.bottom.mode == LedMode.heartbeat) {
      heartbeat.start(side, deviceId);
      return;
    }
    await led.setTopColor(
      deviceId: deviceId,
      side: side,
      color: sideUi.top.mode == LedMode.color
          ? sideUi.top.color
          : Colors.black,
    );
    await led.setBottomColor(
      deviceId: deviceId,
      side: side,
      color: sideUi.bottom.mode == LedMode.color
          ? sideUi.bottom.color
          : Colors.black,
    );
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
        const Spacer(),
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
    final showVoltage = voltage != null && voltage! >= 1.5 && voltage! <= 6.0;
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
            child: Text(
              showVoltage
                  ? '${voltage!.toStringAsFixed(2)}V\n${(clamped * 100).round()}%'
                  : '${(clamped * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white),
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
          width: 110,
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '$label$noteText',
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

