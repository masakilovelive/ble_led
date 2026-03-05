import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/heartbeat_controller.dart';
import '../ble/led_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';

class LedSettingScreen extends ConsumerStatefulWidget {
  final StockSide side;
  const LedSettingScreen({super.key, required this.side});

  @override
  ConsumerState<LedSettingScreen> createState() => _LedSettingScreenState();
}

class _LedSettingScreenState extends ConsumerState<LedSettingScreen> {
  bool _topSelected = true;
  Timer? _heartbeatTimer;
  bool _heartbeatOn = false;

  @override
  void initState() {
    super.initState();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _heartbeatOn = !_heartbeatOn);
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final led = ref.read(ledControllerProvider);
    final uiState = ref.watch(ledUiProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final sideState =
        widget.side == StockSide.a ? stockState.a : stockState.b;
    final sideUi = widget.side == StockSide.a ? uiState.a : uiState.b;
    final deviceId = sideState.device?.id;
    final connected = sideState.status == DeviceConnectionState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('LED Setting'),
      ),
      body: deviceId == null
          ? const Center(child: Text('Device not registered'))
          : LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 600;
                final left = _buildStockPreview(sideUi);
                final right = _buildControlPanel(
                  context,
                  led,
                  deviceId,
                  connected,
                  sideUi,
                  uiNotifier,
                );
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: narrow
                        ? Column(
                            children: [
                              left,
                              const SizedBox(height: 16),
                              right,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 220, child: left),
                              const SizedBox(width: 24),
                              Expanded(child: right),
                            ],
                          ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Stock Select back'),
          ),
        ),
      ),
    );
  }

  Widget _buildStockPreview(LedUiSideState sideUi) {
    final topDisplayColor =
        _segmentDisplayColor(sideUi.top, sideUi.heartbeatColor);
    final bottomDisplayColor =
        _segmentDisplayColor(sideUi.bottom, sideUi.heartbeatColor);

    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white),
          ),
          child: Text(widget.side == StockSide.a ? 'A' : 'B'),
        ),
        const SizedBox(height: 12),
        const Text('TOP'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _topSelected = true),
          child: _SegmentIndicator(
            mode: sideUi.top.mode,
            color: topDisplayColor,
            borderColor: const Color(0xFFE53935),
            selected: _topSelected,
            heartbeat: sideUi.top.mode == LedMode.heartbeat,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 90,
          height: 16,
          color: Colors.white,
        ),
        const SizedBox(height: 8),
        _BatteryRect(
          percent: sideUi.batteryPercent,
          voltage: sideUi.batteryVoltage,
        ),
        const SizedBox(height: 8),
        Container(
          width: 90,
          height: 16,
          color: Colors.white,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _topSelected = false),
          child: _SegmentIndicator(
            mode: sideUi.bottom.mode,
            color: bottomDisplayColor,
            borderColor: const Color(0xFF4DD0E1),
            selected: !_topSelected,
            heartbeat: sideUi.bottom.mode == LedMode.heartbeat,
          ),
        ),
        const SizedBox(height: 8),
        const Text('BOTTOM'),
      ],
    );
  }

  Widget _buildControlPanel(
    BuildContext context,
    LedController led,
    String deviceId,
    bool connected,
    LedUiSideState sideUi,
    LedUiController uiNotifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: connected
                  ? () => _setLedOutput(led, deviceId, true, uiNotifier)
                  : null,
              child: const Text('LED ON'),
            ),
            OutlinedButton(
              onPressed: connected
                  ? () => _setLedOutput(led, deviceId, false, uiNotifier)
                  : null,
              child: const Text('LED OFF'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Heartbeat (Blink)'),
            const SizedBox(width: 8),
            DropdownButton<Color>(
              value: sideUi.heartbeatColor,
              dropdownColor: Colors.grey.shade900,
              items: const [
                Colors.red,
                Colors.blue,
                Colors.green,
                Colors.yellow,
                Colors.purple,
              ].map((color) {
                return DropdownMenuItem(
                  value: color,
                  child: Text(
                    _colorName(color),
                    style: TextStyle(color: color),
                  ),
                );
              }).toList(),
              onChanged: connected
                  ? (value) {
                      if (value == null) return;
                      uiNotifier.setHeartbeatColor(widget.side, value);
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: connected
                  ? () => _startHeartbeat(led, deviceId)
                  : null,
              child: const Text('START'),
            ),
            OutlinedButton(
              onPressed: connected
                  ? () => _stopHeartbeat(led, deviceId)
                  : null,
              child: const Text('STOP'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: connected
                  ? () => _startRainbow(led, deviceId)
                  : null,
              child: const Text('Start Rainbow'),
            ),
            OutlinedButton(
              onPressed: connected
                  ? () => _stopRainbow(led, deviceId)
                  : null,
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
            onChanged: connected
                ? (value) => uiNotifier.setBrightness(widget.side, value)
                : null,
            onChangeEnd: connected
                ? (value) => led.setBrightness(deviceId, value.round())
                : null,
          ),
        const SizedBox(height: 12),
        const Text('Color Pallet'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final paletteSize = maxWidth < 360
                ? 90.0
                : maxWidth < 480
                    ? 100.0
                    : 110.0;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: paletteSize,
                  child: _buildColorPicker(
                    label: 'TOP',
                    color: sideUi.top.color,
                    enabled: connected,
                    size: paletteSize,
                    onChanged: (color) =>
                        _applyColor(led, uiNotifier, deviceId, true, color),
                  ),
                ),
                SizedBox(
                  width: paletteSize,
                  child: _buildColorPicker(
                    label: 'BOTTOM',
                    color: sideUi.bottom.color,
                    enabled: connected,
                    size: paletteSize,
                    onChanged: (color) =>
                        _applyColor(led, uiNotifier, deviceId, false, color),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildColorPicker({
    required String label,
    required Color color,
    required bool enabled,
    required double size,
    required ValueChanged<Color> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !enabled,
            child: SizedBox(
              width: size,
              height: size,
              child: ColorPicker(
                pickerColor: color,
                paletteType: PaletteType.hueWheel,
                enableAlpha: false,
                onColorChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _segmentDisplayColor(
    LedUiSegmentState state,
    Color heartbeatColor,
  ) {
    if (state.mode == LedMode.heartbeat) {
      return _heartbeatOn ? heartbeatColor : Colors.black;
    }
    return state.color;
  }

  void _cancelHeartbeatTimer({bool resetModes = false}) {
    final controller = ref.read(heartbeatControllerProvider);
    controller.stop(
      widget.side,
      deviceId: _currentDeviceId(),
      sendOff: false,
      resetMode: resetModes,
    );
  }

    Future<void> _ensureOutput(LedController led, String deviceId) async {
      await led.setOutputEnabled(deviceId, true);
      ref.read(ledUiProvider.notifier).setOutputEnabled(widget.side, true);
    }

  Future<void> _applyColor(
    LedController led,
    LedUiController uiNotifier,
    String deviceId,
    bool isTop,
    Color color,
  ) async {
    await _ensureOutput(led, deviceId);
    setState(() {
      _cancelHeartbeatTimer(resetModes: true);
    });
    uiNotifier.setSegmentMode(widget.side, isTop, LedMode.color);
    uiNotifier.setSegmentColor(widget.side, isTop, color);
    if (isTop) {
      await led.setTopColor(deviceId: deviceId, side: widget.side, color: color);
    } else {
      await led.setBottomColor(
        deviceId: deviceId,
        side: widget.side,
        color: color,
      );
    }
  }

  Future<void> _startRainbow(LedController led, String deviceId) async {
    await _ensureOutput(led, deviceId);
    setState(() {
      _cancelHeartbeatTimer(resetModes: true);
    });
    ref.read(ledUiProvider.notifier).setBothMode(widget.side, LedMode.rainbow);
    await led.startRainbow(deviceId, intervalMs: 40);
  }

  Future<void> _stopRainbow(LedController led, String deviceId) async {
    await led.stopRainbow(deviceId);
    setState(() {
      ref.read(ledUiProvider.notifier).setBothMode(widget.side, LedMode.off);
    });
  }

  Future<void> _startHeartbeat(LedController led, String deviceId) async {
    await _ensureOutput(led, deviceId);
    setState(() {
      ref.read(ledUiProvider.notifier).setBothMode(widget.side, LedMode.heartbeat);
    });
    ref.read(heartbeatControllerProvider).start(widget.side, deviceId);
  }

  Future<void> _stopHeartbeat(LedController led, String deviceId) async {
    setState(() {
      _heartbeatOn = false;
    });
    ref.read(heartbeatControllerProvider).stop(
      widget.side,
      deviceId: deviceId,
      sendOff: true,
      resetMode: true,
    );
  }

  String _currentDeviceId() {
    final stockState = ref.read(stockProvider);
    final sideState = widget.side == StockSide.a ? stockState.a : stockState.b;
    return sideState.device?.id ?? '';
  }

  Future<void> _setLedOutput(
    LedController led,
    String deviceId,
    bool enabled,
    LedUiController uiNotifier,
  ) async {
    if (!enabled) {
      _cancelHeartbeatTimer(resetModes: true);
      uiNotifier.setBothMode(widget.side, LedMode.off);
      await led.setTopColor(
        deviceId: deviceId,
        side: widget.side,
        color: Colors.black,
      );
      await led.setBottomColor(
        deviceId: deviceId,
        side: widget.side,
        color: Colors.black,
      );
    }
    uiNotifier.setOutputEnabled(widget.side, enabled);
    await led.setOutputEnabled(deviceId, enabled);
    if (!enabled) {
      await ref.read(stockProvider.notifier).disconnect(widget.side);
    }
  }

  static String _colorName(Color color) {
    if (color == Colors.red) return 'Red';
    if (color == Colors.blue) return 'Blue';
    if (color == Colors.green) return 'Green';
    if (color == Colors.yellow) return 'Yellow';
    if (color == Colors.purple) return 'Purple';
    return 'Color';
  }
}

class _SegmentIndicator extends StatelessWidget {
  final LedMode mode;
  final Color color;
  final Color borderColor;
  final bool selected;
  final bool heartbeat;

  const _SegmentIndicator({
    required this.mode,
    required this.color,
    required this.borderColor,
    required this.selected,
    required this.heartbeat,
  });

  @override
  Widget build(BuildContext context) {
    final double size = 70;
    final border = Border.all(
      color: selected ? borderColor : Colors.white54,
      width: 3,
    );

    BoxDecoration decoration;
    if (mode == LedMode.rainbow) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        gradient: const SweepGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ),
      );
    } else {
      final fill = mode == LedMode.color || mode == LedMode.heartbeat
          ? color
          : Colors.black;
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        color: fill,
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: decoration,
      child: heartbeat
          ? const Text(
              'beat',
              style: TextStyle(fontSize: 12, color: Colors.white),
            )
          : null,
    );
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
