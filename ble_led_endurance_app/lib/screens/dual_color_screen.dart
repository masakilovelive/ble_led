import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/heartbeat_controller.dart';
import '../ble/led_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';
import 'setup_screen.dart';

class DualColorScreen extends ConsumerStatefulWidget {
  const DualColorScreen({super.key});

  @override
  ConsumerState<DualColorScreen> createState() => _DualColorScreenState();
}

class _DualColorScreenState extends ConsumerState<DualColorScreen>
    with SingleTickerProviderStateMixin {
  static const List<int> _heartbeatPresets = [1000, 600, 300];
  static const double _startupCycleMs = 1000;
  static const int _defaultRainbowIntervalMs = 40;
  static const List<Color> _startupColors = [
    Color(0xFFFF0000),
    Color(0xFFFF8000),
    Color(0xFFFFFF00),
    Color(0xFF00FFFF),
    Color(0xFF0080FF),
  ];

  late final AnimationController _rainbowController;
  ProviderSubscription<StockState>? _stockSubscription;
  Timer? _pulseTimer;
  Timer? _applyTimer;
  Timer? _startupWaveTimer;
  bool _heartbeatOn = false;
  bool _pickerPrimed = true;
  bool _syncro = false;
  bool _startupWaveRunning = false;
  bool _startupWaveCompletedForCurrentConnection = false;
  StockSide _selectedSide = StockSide.a;
  ColorZone _selectedZone = ColorZone.top;
  int _selectedHeartbeatPresetMs = 600;
  double _hue = 0;
  double _saturation = 255;
  double _brightness = 255;

  @override
  void initState() {
    super.initState();
    _stockSubscription = ref.listenManual<StockState>(stockProvider, (
      prev,
      next,
    ) {
      final isBothConnected = _bothConnected(next);

      if (!isBothConnected) {
        _startupWaveTimer?.cancel();
        _startupWaveCompletedForCurrentConnection = false;
        return;
      }

      if (!_startupWaveCompletedForCurrentConnection && !_startupWaveRunning) {
        _scheduleStartupWave();
      }
    });
    _rainbowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() => _heartbeatOn = !_heartbeatOn);
      }
    });
    Future<void>.microtask(
      () => ref.read(stockProvider.notifier).ensureLoaded(),
    );
  }

  @override
  void dispose() {
    _stockSubscription?.close();
    _startupWaveTimer?.cancel();
    _applyTimer?.cancel();
    _pulseTimer?.cancel();
    _rainbowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);
    _primePickerIfNeeded(ledUiState);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('DUAL CONTROL'),
        actions: [
          IconButton(
            tooltip: 'Bluetooth Setup',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
              );
            },
            icon: const Icon(Icons.bluetooth_searching),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildColorBody(stockState, ledUiState),
      ),
    );
  }

  void _setSyncro(bool value) {
    setState(() {
      _syncro = value;
      if (_syncro) {
        _selectedZone = ColorZone.both;
      }
    });
    _loadPickerFromUi(ref.read(ledUiProvider));
  }

  void _selectSideAndZone(StockSide side, ColorZone zone) {
    if (_syncro && zone != ColorZone.both) {
      return;
    }
    setState(() {
      _selectedSide = side;
      _selectedZone = _syncro ? ColorZone.both : zone;
    });
    _loadPickerFromUi(ref.read(ledUiProvider));
  }

  Widget _buildColorBody(StockState stockState, LedUiState ledUiState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopToolbar(stockState),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildSideCard(
                      side: StockSide.a,
                      stockState: stockState,
                      ledUiState: ledUiState,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildSideCard(
                      side: StockSide.b,
                      stockState: stockState,
                      ledUiState: ledUiState,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildCenterPickerCard(ledUiState)),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 320,
                          child: _buildMotionCard(stockState, ledUiState),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildCenterPickerCard(ledUiState),
                        const SizedBox(height: 14),
                        _buildMotionCard(stockState, ledUiState),
                      ],
                    ),
              if (stockState.message != null) ...[
                const SizedBox(height: 12),
                Text(
                  stockState.message!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopToolbar(StockState stockState) {
    final targetLabel = _syncro ? 'A + B' : _selectedSide.name.toUpperCase();
    final zoneLabel = switch (_selectedZone) {
      ColorZone.top => 'TOP',
      ColorZone.bottom => 'BOTTOM',
      ColorZone.both => 'BOTH',
    };
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('Target: $targetLabel / $zoneLabel'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('SYNCRO'),
                    Switch(value: _syncro, onChanged: _setSyncro),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideCard({
    required StockSide side,
    required StockState stockState,
    required LedUiState ledUiState,
  }) {
    final sideState = side == StockSide.a ? stockState.a : stockState.b;
    final sideUi = side == StockSide.a ? ledUiState.a : ledUiState.b;
    final selected = _syncro || _selectedSide == side;
    final showOk = sideState.status == DeviceConnectionState.connected;

    return Card(
      color: selected ? const Color(0xFF182028) : Colors.white10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? Colors.white : Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  side == StockSide.a ? 'stockA' : 'stockB',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (showOk)
                  const Text(
                    'ok',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: sideState.device != null &&
                      sideState.status != DeviceConnectionState.connected
                  ? () => ref.read(stockProvider.notifier).connect(side)
                  : null,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 10),
            _BatteryPanel(sideUi: sideUi),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPickerCard(LedUiState ledUiState) {
    final color = _currentPickerColor();
    final textColor =
        color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    return Card(
      color: const Color(0xFFD5D7DA),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              'COLOR SELECT',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VerticalHsvSlider(
                  label: 'H',
                  value: _hue,
                  min: 0,
                  max: 359,
                  activeColor: Colors.redAccent,
                  onChanged: (value) {
                    setState(() => _hue = value);
                    _scheduleApply();
                  },
                ),
                const SizedBox(width: 10),
                _VerticalHsvSlider(
                  label: 'S',
                  value: _saturation,
                  min: 0,
                  max: 255,
                  activeColor: Colors.greenAccent,
                  onChanged: (value) {
                    setState(() => _saturation = value);
                    _scheduleApply();
                  },
                ),
                const SizedBox(width: 10),
                _VerticalHsvSlider(
                  label: 'B',
                  value: _brightness,
                  min: 0,
                  max: 255,
                  activeColor: Colors.lightGreen,
                  onChanged: (value) {
                    setState(() => _brightness = value);
                    _scheduleApply();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black87),
              ),
              child: Text(
                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFigureCard(
                    side: StockSide.a,
                    sideUi: ledUiState.a,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFigureCard(
                    side: StockSide.b,
                    sideUi: ledUiState.b,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFigureCard({
    required StockSide side,
    required LedUiSideState sideUi,
  }) {
    final rainbowAngle = _rainbowController.value * math.pi * 2;
    final isCurrentSide = _selectedSide == side;
    final topSelected =
        _syncro || (isCurrentSide && _selectedZone == ColorZone.top);
    final bottomSelected =
        _syncro || (isCurrentSide && _selectedZone == ColorZone.bottom);
    final bothSelected =
        _syncro || (isCurrentSide && _selectedZone == ColorZone.both);
    return Card(
      color: bothSelected ? const Color(0x2200E676) : const Color(0x33000000),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: bothSelected ? Colors.greenAccent : Colors.black26,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          children: [
            Text(
              side == StockSide.a ? 'stockA' : 'stockB',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            _FigureTapTarget(
              label: 'TOP',
              selected: topSelected || bothSelected,
              onTap: _syncro
                  ? null
                  : () => _selectSideAndZone(side, ColorZone.top),
              child: _StockSegmentCircle(
                mode: sideUi.top.mode,
                color: _segmentDisplayColor(sideUi.top, sideUi.heartbeatColor),
                rainbowAngle: rainbowAngle,
              ),
            ),
            Container(
              width: 96,
              height: 18,
              margin: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.white,
            ),
            _BatteryRect(
              percent: sideUi.batteryPercent,
              isCharging: sideUi.charging,
            ),
            Container(
              width: 96,
              height: 18,
              margin: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.white,
            ),
            _FigureTapTarget(
              label: 'BOTTOM',
              selected: bottomSelected || bothSelected,
              onTap: _syncro
                  ? null
                  : () => _selectSideAndZone(side, ColorZone.bottom),
              child: _StockSegmentCircle(
                mode: sideUi.bottom.mode,
                color: _segmentDisplayColor(
                  sideUi.bottom,
                  sideUi.heartbeatColor,
                ),
                rainbowAngle: rainbowAngle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotionCard(StockState stockState, LedUiState ledUiState) {
    final currentColor = _currentPickerColor();
    final textColor =
        currentColor.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    final heartbeatEnabled = _isModeActive(
      stockState,
      ledUiState,
      LedMode.heartbeat,
    );
    final rainbowEnabled = _isModeActive(
      stockState,
      ledUiState,
      LedMode.rainbow,
    );
    final heartbeatPreset =
        _heartbeatPresets.contains(_selectedHeartbeatPresetMs)
            ? _selectedHeartbeatPresetMs
            : _heartbeatPresets[1];
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('heart beat', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('ON/OFF'),
                const SizedBox(width: 12),
                Switch(
                  value: heartbeatEnabled,
                  onChanged: (value) async {
                    if (value) {
                      await _startHeartbeat(heartbeatPreset);
                    } else {
                      await _stopHeartbeat();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white),
              ),
              child: Text(
                'HB ${currentColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Speed',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: heartbeatPreset,
                        isExpanded: true,
                        items: _heartbeatPresets
                            .map(
                              (ms) => DropdownMenuItem<int>(
                                value: ms,
                                child: Text(_heartbeatLabel(ms)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _selectedHeartbeatPresetMs = value);
                          if (heartbeatEnabled) {
                            unawaited(_startHeartbeat(value));
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async {
                    await _setHeartbeatColorFromCurrent();
                  },
                  child: const Text('SET'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('RAINBOW', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('ON/OFF'),
                const SizedBox(width: 12),
                Switch(
                  value: rainbowEnabled,
                  onChanged: (value) async {
                    if (value) {
                      await _startRainbow();
                    } else {
                      await _stopRainbow();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              stockState.registered
                  ? 'Assigned pair ready for COLOR control.'
                  : 'Open Bluetooth Setup to assign A/B devices.',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  bool _isModeActive(
    StockState stockState,
    LedUiState ledUiState,
    LedMode mode,
  ) {
    final sides = _targetSides(stockState);
    if (sides.isEmpty) {
      return false;
    }
    return sides.every((side) {
      final sideUi = ledUiState.sideState(side);
      return sideUi.top.mode == mode && sideUi.bottom.mode == mode;
    });
  }

  String _heartbeatLabel(int intervalMs) {
    switch (intervalMs) {
      case 1000:
        return 'LOW';
      case 600:
        return 'MIDDLE';
      case 300:
        return 'HIGH';
      default:
        return '$intervalMs ms';
    }
  }

  Color _currentPickerColor() {
    return HSVColor.fromAHSV(
      1,
      _hue.clamp(0, 359),
      (_saturation / 255).clamp(0, 1),
      (_brightness / 255).clamp(0, 1),
    ).toColor();
  }

  void _primePickerIfNeeded(LedUiState state) {
    if (_pickerPrimed) {
      return;
    }
    _pickerPrimed = true;
    _loadPickerFromUi(state);
  }

  void _loadPickerFromUi(LedUiState state) {
    final sideState =
        _syncro ? state.sideState(StockSide.a) : state.sideState(_selectedSide);
    final color = switch (_selectedZone) {
      ColorZone.top => sideState.top.color,
      ColorZone.bottom => sideState.bottom.color,
      ColorZone.both => sideState.top.color,
    };
    final hsv = HSVColor.fromColor(color);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation * 255;
      _brightness = sideState.brightness;
      _selectedHeartbeatPresetMs = sideState.heartbeatIntervalMs;
    });
  }

  void _scheduleApply() {
    _applyTimer?.cancel();
    _applyTimer = Timer(const Duration(milliseconds: 60), () {
      unawaited(_applyCurrentSelection());
    });
  }

  Future<void> _applyCurrentSelection() async {
    final stockState = ref.read(stockProvider);
    final led = ref.read(ledControllerProvider);
    final ui = ref.read(ledUiProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final color = _currentPickerColor();
    for (final side in _targetSides(stockState)) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null) {
        continue;
      }

      final currentSide = ui.sideState(side);
      final nextTopMode =
          _selectedZone == ColorZone.top || _selectedZone == ColorZone.both
              ? LedMode.color
              : (currentSide.top.mode == LedMode.color
                  ? LedMode.color
                  : LedMode.off);
      final nextBottomMode =
          _selectedZone == ColorZone.bottom || _selectedZone == ColorZone.both
              ? LedMode.color
              : (currentSide.bottom.mode == LedMode.color
                  ? LedMode.color
                  : LedMode.off);
      final nextTopColor =
          _selectedZone == ColorZone.top || _selectedZone == ColorZone.both
              ? color
              : currentSide.top.color;
      final nextBottomColor =
          _selectedZone == ColorZone.bottom || _selectedZone == ColorZone.both
              ? color
              : currentSide.bottom.color;

      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setSegmentMode(side, ColorZone.top, nextTopMode);
      uiNotifier.setSegmentMode(side, ColorZone.bottom, nextBottomMode);
      if (_selectedZone == ColorZone.both) {
        uiNotifier.setSegmentColor(side, ColorZone.both, color);
      } else {
        uiNotifier.setSegmentColor(side, _selectedZone, color);
      }

      final sideState = side == StockSide.a ? stockState.a : stockState.b;
      if (sideState.status != DeviceConnectionState.connected) {
        continue;
      }

      await heartbeat.stop(
        side,
        deviceId: deviceId,
        sendOff: false,
        resetMode: false,
      );
      try {
        await led.stopRainbow(deviceId);
      } catch (_) {}
      await led.setOutputEnabled(deviceId, true);
      await led.setBrightness(deviceId, _brightness.round());
      await led.setTopColor(
        deviceId: deviceId,
        side: side,
        color: nextTopMode == LedMode.off ? Colors.black : nextTopColor,
      );
      await led.setBottomColor(
        deviceId: deviceId,
        side: side,
        color: nextBottomMode == LedMode.off ? Colors.black : nextBottomColor,
      );
    }
  }

  Future<void> _startHeartbeat(int intervalMs) async {
    final stockState = ref.read(stockProvider);
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);
    for (final side in _targetSides(stockState, connectedOnly: true)) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null) {
        continue;
      }
      try {
        await led.stopRainbow(deviceId);
      } catch (_) {}
      await led.setOutputEnabled(deviceId, true);
      await led.setBrightness(deviceId, _brightness.round());
      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setHeartbeatInterval(side, intervalMs);
      await heartbeat.start(
        side,
        deviceId,
        interval: Duration(milliseconds: intervalMs),
      );
    }
  }

  Future<void> _setHeartbeatColorFromCurrent() async {
    final color = _currentPickerColor();
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final stockState = ref.read(stockProvider);
    for (final side in _targetSides(stockState)) {
      uiNotifier.setHeartbeatColor(side, color);
    }
    final ledUiState = ref.read(ledUiProvider);
    final heartbeatEnabled = _isModeActive(
      stockState,
      ledUiState,
      LedMode.heartbeat,
    );
    if (heartbeatEnabled) {
      await _startHeartbeat(_selectedHeartbeatPresetMs);
    }
  }

  Future<void> _stopHeartbeat() async {
    final stockState = ref.read(stockProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    for (final side in _targetSides(stockState)) {
      await heartbeat.stop(
        side,
        deviceId: _deviceId(stockState, side),
        sendOff: true,
        resetMode: true,
      );
    }
  }

  Future<void> _startRainbow() async {
    final stockState = ref.read(stockProvider);
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);
    for (final side in _targetSides(stockState, connectedOnly: true)) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null) {
        continue;
      }
      await heartbeat.stop(
        side,
        deviceId: deviceId,
        sendOff: false,
        resetMode: false,
      );
      await led.setOutputEnabled(deviceId, true);
      await led.setBrightness(deviceId, _brightness.round());
      await led.startRainbow(deviceId, intervalMs: _defaultRainbowIntervalMs);
      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setRainbowInterval(side, _defaultRainbowIntervalMs);
      uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.rainbow);
    }
  }

  Future<void> _stopRainbow() async {
    final stockState = ref.read(stockProvider);
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targetSides(stockState, connectedOnly: true)) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null) {
        continue;
      }
      await led.stopRainbow(deviceId);
      await led.setTopColor(
        deviceId: deviceId,
        side: side,
        color: Colors.black,
      );
      await led.setBottomColor(
        deviceId: deviceId,
        side: side,
        color: Colors.black,
      );
      uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.off);
    }
  }

  Future<void> _runDefaultStartupWave() async {
    final stockState = ref.read(stockProvider);
    await _runStartupWaveForSides(_connectedSides(stockState));
  }

  void _scheduleStartupWave() {
    _startupWaveTimer?.cancel();
    _startupWaveTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted ||
          _startupWaveRunning ||
          _startupWaveCompletedForCurrentConnection) {
        return;
      }
      final stockState = ref.read(stockProvider);
      if (!_bothConnected(stockState)) {
        return;
      }
      _startupWaveCompletedForCurrentConnection = true;
      unawaited(_runDefaultStartupWave());
    });
  }

  Future<void> _runStartupWaveForSides(List<StockSide> sides) async {
    if (sides.isEmpty || _startupWaveRunning) {
      return;
    }

    final led = ref.read(ledControllerProvider);
    final ui = ref.read(ledUiProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final stepMs = (_startupCycleMs / _startupColors.length).round().clamp(
          60,
          5000,
        );

    _startupWaveRunning = true;
    try {
      final stockState = ref.read(stockProvider);
      final targets = <({StockSide side, String deviceId, int brightness})>[];
      for (final side in sides) {
        final deviceId = _deviceId(stockState, side);
        if (deviceId == null) {
          continue;
        }
        targets.add((
          side: side,
          deviceId: deviceId,
          brightness: ui.sideState(side).brightness.round(),
        ));
      }
      if (targets.isEmpty) {
        return;
      }

      for (final target in targets) {
        await heartbeat.stop(
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

      for (final color in _startupColors) {
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

      await _restoreLightingAfterStartupWave(targets);
    } finally {
      _startupWaveRunning = false;
    }
  }

  Future<void> _restoreLightingAfterStartupWave(
    List<({StockSide side, String deviceId, int brightness})> targets,
  ) async {
    final led = ref.read(ledControllerProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);

    for (final target in targets) {
      final desired = ref.read(ledUiProvider).sideState(target.side);

      uiNotifier.setOutputEnabled(target.side, desired.outputEnabled);
      uiNotifier.setBrightness(target.side, desired.brightness);
      uiNotifier.setHeartbeatColor(target.side, desired.heartbeatColor);
      uiNotifier.setHeartbeatInterval(target.side, desired.heartbeatIntervalMs);
      uiNotifier.setRainbowInterval(target.side, desired.rainbowIntervalMs);
      uiNotifier.setSegmentColor(target.side, ColorZone.top, desired.top.color);
      uiNotifier.setSegmentColor(
        target.side,
        ColorZone.bottom,
        desired.bottom.color,
      );
      uiNotifier.setSegmentMode(target.side, ColorZone.top, desired.top.mode);
      uiNotifier.setSegmentMode(
        target.side,
        ColorZone.bottom,
        desired.bottom.mode,
      );

      if (!desired.outputEnabled) {
        await led.applyIdleState(target.deviceId);
        continue;
      }

      await led.setOutputEnabled(target.deviceId, true);
      await led.setBrightness(target.deviceId, desired.brightness.round());

      if (desired.top.mode == LedMode.rainbow ||
          desired.bottom.mode == LedMode.rainbow) {
        await led.startRainbow(
          target.deviceId,
          intervalMs: desired.rainbowIntervalMs,
        );
        continue;
      }

      if (desired.top.mode == LedMode.heartbeat ||
          desired.bottom.mode == LedMode.heartbeat) {
        await heartbeat.start(
          target.side,
          target.deviceId,
          interval: Duration(milliseconds: desired.heartbeatIntervalMs),
        );
        continue;
      }

      await led.setTopColor(
        deviceId: target.deviceId,
        side: target.side,
        color:
            desired.top.mode == LedMode.off ? Colors.black : desired.top.color,
      );
      await led.setBottomColor(
        deviceId: target.deviceId,
        side: target.side,
        color: desired.bottom.mode == LedMode.off
            ? Colors.black
            : desired.bottom.color,
      );
    }
  }

  bool _bothConnected(StockState state) {
    return _connectedSides(state).length == 2;
  }

  List<StockSide> _connectedSides(StockState state) {
    return [StockSide.a, StockSide.b].where((side) {
      final sideState = side == StockSide.a ? state.a : state.b;
      return sideState.status == DeviceConnectionState.connected &&
          _deviceId(state, side) != null;
    }).toList();
  }

  List<StockSide> _targetSides(StockState state, {bool connectedOnly = false}) {
    final sides =
        _syncro ? <StockSide>[StockSide.a, StockSide.b] : [_selectedSide];
    if (!connectedOnly) {
      return sides.where((side) => _deviceId(state, side) != null).toList();
    }
    return sides.where((side) {
      final sideState = side == StockSide.a ? state.a : state.b;
      return sideState.status == DeviceConnectionState.connected &&
          _deviceId(state, side) != null;
    }).toList();
  }

  String? _deviceId(StockState state, StockSide side) {
    return side == StockSide.a ? state.a.device?.id : state.b.device?.id;
  }

  Color _segmentDisplayColor(LedUiSegmentState state, Color heartbeatColor) {
    if (state.mode == LedMode.heartbeat) {
      return _heartbeatOn ? heartbeatColor : Colors.black;
    }
    if (state.mode == LedMode.off) {
      return Colors.white;
    }
    return state.color;
  }
}

class _BatteryPanel extends StatelessWidget {
  final LedUiSideState sideUi;

  const _BatteryPanel({required this.sideUi});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: sideUi.batteryPercent.clamp(0.0, 1.0),
            minHeight: 14,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Battery ${(sideUi.batteryPercent.clamp(0.0, 1.0) * 100).round()}%',
            ),
            if (sideUi.charging) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.bolt_rounded,
                color: Colors.amberAccent,
                size: 18,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _VerticalHsvSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _VerticalHsvSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 50,
          height: 210,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor,
                inactiveTrackColor: Colors.black26,
                thumbColor: Colors.white,
                overlayColor: Colors.white24,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _BatteryRect extends StatelessWidget {
  final double percent;
  final bool isCharging;

  const _BatteryRect({
    required this.percent,
    required this.isCharging,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 1.0);
    return Container(
      width: 92,
      height: 138,
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
                '${(clamped * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
          ),
          if (isCharging)
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.bolt_rounded,
                color: Colors.amberAccent,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}

class _FigureTapTarget extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  const _FigureTapTarget({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = selected ? Colors.greenAccent : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                letterSpacing: 2,
                color: labelColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? Colors.greenAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: child,
            ),
          ],
        ),
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
    return Container(width: 74, height: 74, decoration: decoration);
  }
}
