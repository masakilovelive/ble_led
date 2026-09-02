import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/product_ui_state.dart';
import '../ble/heartbeat_controller.dart';
import '../ble/led_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';
import 'sceptronic_ui.dart';

class LedSettingScreen extends ConsumerStatefulWidget {
  const LedSettingScreen({
    super.key,
    required this.side,
  });

  final StockSide side;

  @override
  ConsumerState<LedSettingScreen> createState() => _LedSettingScreenState();
}

class _LedSettingScreenState extends ConsumerState<LedSettingScreen> {
  static const List<int> _heartbeatPresets = [1000, 600, 300];
  static const int _defaultRainbowIntervalMs = 40;
  static const Duration _connectAssistTimeout = Duration(seconds: 8);

  bool _ready = false;
  bool _connectAssistInFlight = false;
  int _selectedHeartbeatPresetMs = 600;
  double _hue = 0;
  double _saturation = 255;
  double _brightness = 210;
  DateTime? _lastConnectionNoticeAt;

  String get _appBarTitle =>
      widget.side == StockSide.a ? 'STOCK A SETTING' : 'STOCK B SETTING';

  String get _frameworkTitle => 'COLOR';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await Future.wait<void>([
        ref.read(stockProvider.notifier).ensureLoaded(),
        ref.read(ledUiProvider.notifier).ensureLoaded(),
      ]);
      if (!mounted) {
        return;
      }
      _loadPickerFromUi(ref.read(ledUiProvider));
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);
    final syncro = ref.watch(bothSyncroProvider);
    final demoMode = ref.watch(demoModeProvider);
    final primarySide = syncro
        ? ledUiState.sideState(StockSide.a)
        : ledUiState.sideState(widget.side);
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final wide = screenWidth >= 980;
    final denseLayout = screenWidth < 430 || screenSize.height < 900;
    final compactZones = screenWidth < 820 || denseLayout;

    return Scaffold(
      backgroundColor: SceptronicPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 44,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 4,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                kBrandIconAsset,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTitleText(
                context,
                text: _appBarTitle,
                size: 16,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'BOTH SYNCRO',
            onPressed: () {
              ref.read(bothSyncroProvider.notifier).state = !syncro;
              _loadPickerFromUi(ref.read(ledUiProvider));
            },
            icon: Icon(
              syncro ? Icons.link_rounded : Icons.link_off_rounded,
              color:
                  syncro ? SceptronicPalette.primary : SceptronicPalette.muted,
            ),
          ),
        ],
      ),
      body: SceptronicBackdrop(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (demoMode && !sceptronicScreenshotMode) ...[
                  const SceptronicDemoBanner(),
                  SizedBox(height: denseLayout ? 10 : 14),
                ],
                if (!_ready)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildPickerPanel(
                                context,
                                dense: denseLayout,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _buildZoneRow(
                                context,
                                sideState: primarySide,
                                compact: denseLayout,
                                dense: denseLayout,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _buildPickerPanel(context, dense: denseLayout),
                            SizedBox(height: denseLayout ? 10 : 18),
                            _buildZoneRow(
                              context,
                              sideState: primarySide,
                              compact: compactZones,
                              dense: denseLayout,
                            ),
                          ],
                        ),
                if (!demoMode && stockState.message != null) ...[
                  const SizedBox(height: 18),
                  SceptronicPanel(
                    child: Text(
                      stockState.message!,
                      style: const TextStyle(color: SceptronicPalette.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerPanel(
    BuildContext context, {
    required bool dense,
  }) {
    final pickerColor = _currentPickerColor();
    return SceptronicPanel(
      padding: EdgeInsets.fromLTRB(
        dense ? 16 : 20,
        dense ? 12 : 14,
        dense ? 16 : 20,
        dense ? 14 : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleText(context,
              text: _frameworkTitle, size: dense ? 18 : 20),
          SizedBox(height: dense ? 12 : 18),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(dense ? 14 : 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  pickerColor.withValues(alpha: 0.92),
                  pickerColor.withValues(alpha: 0.38),
                ],
              ),
              border: Border.all(color: Colors.white24),
            ),
            child: SizedBox(height: dense ? 36 : 72),
          ),
          SizedBox(height: dense ? 10 : 18),
          _LabeledSlider(
            label: 'Color Tone',
            value: _hue,
            min: 0,
            max: 359,
            accent: SceptronicPalette.primary,
            dense: dense,
            onChanged: (value) => setState(() => _hue = value),
          ),
          _LabeledSlider(
            label: 'Color Strength',
            value: _saturation,
            min: 0,
            max: 255,
            accent: SceptronicPalette.secondary,
            dense: dense,
            onChanged: (value) => setState(() => _saturation = value),
          ),
          _LabeledSlider(
            label: 'Brightness',
            value: _brightness,
            min: 0,
            max: 255,
            accent: SceptronicPalette.success,
            dense: dense,
            onChanged: (value) => setState(() => _brightness = value),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleText(
    BuildContext context, {
    required String text,
    required double size,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: sceptronicDisplayStyle(
            context,
            size: size,
            letterSpacing: 0.45,
          ),
        ),
      ),
    );
  }

  Widget _buildZoneRow(
    BuildContext context, {
    required LedUiSideState sideState,
    required bool compact,
    required bool dense,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildZoneCard(
            context,
            sideState: sideState,
            zone: ColorZone.top,
            title: 'Head',
            compact: compact,
            dense: dense,
          ),
        ),
        SizedBox(width: compact ? 12 : 18),
        Expanded(
          child: _buildZoneCard(
            context,
            sideState: sideState,
            zone: ColorZone.bottom,
            title: 'Tip',
            compact: compact,
            dense: dense,
          ),
        ),
      ],
    );
  }

  Widget _buildZoneCard(
    BuildContext context, {
    required LedUiSideState sideState,
    required ColorZone zone,
    required String title,
    required bool compact,
    required bool dense,
  }) {
    final segment = zone == ColorZone.top ? sideState.top : sideState.bottom;
    final heartbeatEnabled = _isModeActive(sideState, LedMode.heartbeat);
    final rainbowEnabled = _isModeActive(sideState, LedMode.rainbow);
    final previewColor = segment.mode == LedMode.heartbeat
        ? sideState.heartbeatColor
        : segment.mode == LedMode.off
            ? const Color(0xFF0B0D11)
            : segment.color;
    return SceptronicPanel(
      padding: EdgeInsets.fromLTRB(
        dense ? 12 : (compact ? 14 : 18),
        dense ? 12 : (compact ? 14 : 18),
        dense ? 12 : (compact ? 14 : 18),
        dense ? 12 : (compact ? 16 : 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: sceptronicDisplayStyle(
                  context,
                  size: dense ? 15 : (compact ? 17 : 20),
                ),
              ),
              const Spacer(),
              SceptronicStatusPill(
                label: _modeLabel(segment.mode),
                color: _modeColor(segment.mode),
              ),
            ],
          ),
          SizedBox(height: dense ? 8 : (compact ? 12 : 16)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(dense ? 10 : (compact ? 12 : 16)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  previewColor.withValues(
                    alpha: segment.mode == LedMode.off ? 0.16 : 0.88,
                  ),
                  previewColor.withValues(alpha: 0.24),
                ],
              ),
              border: Border.all(color: Colors.white10),
            ),
            child: SizedBox(height: dense ? 22 : (compact ? 44 : 64)),
          ),
          SizedBox(height: dense ? 8 : (compact ? 12 : 16)),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _applySolidColor(zone),
              style: FilledButton.styleFrom(
                backgroundColor: SceptronicPalette.primary,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(
                  vertical: dense ? 8 : (compact ? 10 : 14),
                ),
              ),
              child: const Text('SET'),
            ),
          ),
          SizedBox(height: dense ? 8 : (compact ? 12 : 16)),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Heart Beat',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: dense ? 13 : (compact ? 15 : null),
                      ),
                ),
              ),
              Transform.scale(
                scale: dense ? 0.8 : 1,
                child: Switch(
                  value: heartbeatEnabled,
                  activeThumbColor: SceptronicPalette.primary,
                  onChanged: (value) async {
                    if (value) {
                      await _setHeartbeatColorFromCurrent();
                      await _startHeartbeat(_selectedHeartbeatPresetMs);
                    } else {
                      await _stopHeartbeat();
                    }
                  },
                ),
              ),
            ],
          ),
          DropdownButtonFormField<int>(
            initialValue: _selectedHeartbeatPresetMs,
            decoration: InputDecoration(
              labelText: 'Speed',
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: dense ? 10 : 14,
              ),
            ),
            items: _heartbeatPresets
                .map(
                  (ms) => DropdownMenuItem<int>(
                    value: ms,
                    child: Text(_heartbeatLabel(ms)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _selectedHeartbeatPresetMs = value);
            },
          ),
          SizedBox(height: dense ? 8 : (compact ? 12 : 16)),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rainbow',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: dense ? 13 : (compact ? 15 : null),
                      ),
                ),
              ),
              Transform.scale(
                scale: dense ? 0.8 : 1,
                child: Switch(
                  value: rainbowEnabled,
                  activeThumbColor: SceptronicPalette.secondary,
                  onChanged: (value) async {
                    if (value) {
                      await _startRainbow();
                    } else {
                      await _stopRainbow();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _loadPickerFromUi(LedUiState state) {
    final syncro = ref.read(bothSyncroProvider);
    final sideState =
        syncro ? state.sideState(StockSide.a) : state.sideState(widget.side);
    final hsv = HSVColor.fromColor(sideState.top.color);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation * 255;
      _brightness = sideState.brightness;
      _selectedHeartbeatPresetMs = sideState.heartbeatIntervalMs;
    });
  }

  Color _currentPickerColor() {
    return HSVColor.fromAHSV(
      1,
      _hue,
      (_saturation / 255).clamp(0, 1),
      (_brightness / 255).clamp(0, 1),
    ).toColor();
  }

  Future<void> _applySolidColor(ColorZone zone) async {
    final demoMode = ref.read(demoModeProvider);
    var stockState = ref.read(stockProvider);
    if (!demoMode) {
      stockState = await _ensureTargetConnections(stockState);
    }
    final led = ref.read(ledControllerProvider);
    final ui = ref.read(ledUiProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);
    final color = _currentPickerColor();

    for (final side in _targetSides()) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null && !demoMode) {
        continue;
      }

      final currentSide = ui.sideState(side);
      final nextHeadMode = zone == ColorZone.top
          ? LedMode.color
          : (currentSide.top.mode == LedMode.color
              ? LedMode.color
              : LedMode.off);
      final nextTipMode = zone == ColorZone.bottom
          ? LedMode.color
          : (currentSide.bottom.mode == LedMode.color
              ? LedMode.color
              : LedMode.off);
      final nextHeadColor =
          zone == ColorZone.top ? color : currentSide.top.color;
      final nextTipColor =
          zone == ColorZone.bottom ? color : currentSide.bottom.color;

      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setSegmentMode(side, ColorZone.top, nextHeadMode);
      uiNotifier.setSegmentMode(side, ColorZone.bottom, nextTipMode);
      uiNotifier.setSegmentColor(side, zone, color);

      if (demoMode) {
        continue;
      }
      final liveDeviceId = deviceId!;

      final sideState = side == StockSide.a ? stockState.a : stockState.b;
      if (sideState.status != DeviceConnectionState.connected) {
        continue;
      }

      await heartbeat.stop(
        side,
        deviceId: liveDeviceId,
        sendOff: false,
        resetMode: false,
      );
      try {
        await led.stopRainbow(liveDeviceId);
      } catch (_) {}
      await led.setOutputEnabled(liveDeviceId, true);
      await led.setBrightness(liveDeviceId, _brightness.round());
      await led.setTopColor(
        deviceId: liveDeviceId,
        side: side,
        color: nextHeadMode == LedMode.off ? Colors.black : nextHeadColor,
      );
      await led.setBottomColor(
        deviceId: liveDeviceId,
        side: side,
        color: nextTipMode == LedMode.off ? Colors.black : nextTipColor,
      );
    }
  }

  Future<void> _startHeartbeat(int intervalMs) async {
    final demoMode = ref.read(demoModeProvider);
    var stockState = ref.read(stockProvider);
    if (!demoMode) {
      stockState = await _ensureTargetConnections(stockState);
    }
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);

    for (final side in _targetSides(
      connectedOnly: true,
      stockSnapshot: stockState,
    )) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null && !demoMode) {
        continue;
      }
      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setHeartbeatInterval(side, intervalMs);
      if (demoMode) {
        uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.heartbeat);
        continue;
      }
      final liveDeviceId = deviceId!;
      try {
        await led.stopRainbow(liveDeviceId);
      } catch (_) {}
      await led.setOutputEnabled(liveDeviceId, true);
      await led.setBrightness(liveDeviceId, _brightness.round());
      await heartbeat.start(
        side,
        liveDeviceId,
        interval: Duration(milliseconds: intervalMs),
      );
    }
  }

  Future<void> _setHeartbeatColorFromCurrent() async {
    final color = _currentPickerColor();
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targetSides()) {
      uiNotifier.setHeartbeatColor(side, color);
    }
  }

  Future<void> _stopHeartbeat() async {
    if (ref.read(demoModeProvider)) {
      final uiNotifier = ref.read(ledUiProvider.notifier);
      for (final side in _targetSides()) {
        uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.off);
      }
      return;
    }
    final stockState = ref.read(stockProvider);
    final heartbeat = ref.read(heartbeatControllerProvider);
    for (final side in _targetSides()) {
      await heartbeat.stop(
        side,
        deviceId: _deviceId(stockState, side),
        sendOff: true,
        resetMode: true,
      );
    }
  }

  Future<void> _startRainbow() async {
    final demoMode = ref.read(demoModeProvider);
    var stockState = ref.read(stockProvider);
    if (!demoMode) {
      stockState = await _ensureTargetConnections(stockState);
    }
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    final heartbeat = ref.read(heartbeatControllerProvider);
    for (final side in _targetSides(
      connectedOnly: true,
      stockSnapshot: stockState,
    )) {
      final deviceId = _deviceId(stockState, side);
      if (deviceId == null && !demoMode) {
        continue;
      }
      uiNotifier.setOutputEnabled(side, true);
      uiNotifier.setBrightness(side, _brightness);
      uiNotifier.setRainbowInterval(side, _defaultRainbowIntervalMs);
      uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.rainbow);
      if (demoMode) {
        continue;
      }
      final liveDeviceId = deviceId!;
      await heartbeat.stop(
        side,
        deviceId: liveDeviceId,
        sendOff: false,
        resetMode: false,
      );
      await led.setOutputEnabled(liveDeviceId, true);
      await led.setBrightness(liveDeviceId, _brightness.round());
      await led.startRainbow(
        liveDeviceId,
        intervalMs: _defaultRainbowIntervalMs,
      );
    }
  }

  Future<void> _stopRainbow() async {
    if (ref.read(demoModeProvider)) {
      final uiNotifier = ref.read(ledUiProvider.notifier);
      for (final side in _targetSides()) {
        uiNotifier.setSegmentMode(side, ColorZone.both, LedMode.off);
      }
      return;
    }
    final stockState = ref.read(stockProvider);
    final led = ref.read(ledControllerProvider);
    final uiNotifier = ref.read(ledUiProvider.notifier);
    for (final side in _targetSides(
      connectedOnly: true,
      stockSnapshot: stockState,
    )) {
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

  Future<StockState> _ensureTargetConnections(StockState state) async {
    if (ref.read(demoModeProvider)) {
      return state;
    }
    final targets = _targetSides(stockSnapshot: state);
    if (targets.isEmpty) {
      return state;
    }
    final missing = _disconnectedTargetSides(state, targets);
    if (missing.isEmpty) {
      return state;
    }

    if (_connectAssistInFlight) {
      await _waitForTargetConnections(targets, _connectAssistTimeout);
      return ref.read(stockProvider);
    }

    _connectAssistInFlight = true;
    try {
      final stock = ref.read(stockProvider.notifier);
      for (final side in missing) {
        await stock.connect(side);
      }
      final connected =
          await _waitForTargetConnections(targets, _connectAssistTimeout);
      final nextState = ref.read(stockProvider);
      if (!connected) {
        _showConnectionNotice(_connectionPendingMessage(nextState, targets));
      }
      return nextState;
    } finally {
      _connectAssistInFlight = false;
    }
  }

  Future<bool> _waitForTargetConnections(
    List<StockSide> sides,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = ref.read(stockProvider);
      if (_disconnectedTargetSides(state, sides).isEmpty) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _disconnectedTargetSides(ref.read(stockProvider), sides).isEmpty;
  }

  List<StockSide> _disconnectedTargetSides(
    StockState state,
    List<StockSide> sides,
  ) {
    return sides.where((side) {
      final sideState = side == StockSide.a ? state.a : state.b;
      return sideState.status != DeviceConnectionState.connected;
    }).toList(growable: false);
  }

  String _connectionPendingMessage(StockState state, List<StockSide> sides) {
    final missing = _disconnectedTargetSides(state, sides)
        .map((side) => side == StockSide.a ? 'A' : 'B')
        .join('/');
    if (missing.isEmpty) {
      return 'BLE reconnect completed.';
    }
    return 'BLE reconnect pending: $missing. Open Bluetooth Setting if it does not recover.';
  }

  void _showConnectionNotice(String message) {
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final last = _lastConnectionNoticeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastConnectionNoticeAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<StockSide> _targetSides({
    bool connectedOnly = false,
    StockState? stockSnapshot,
  }) {
    final StockState stockState = stockSnapshot ?? ref.read(stockProvider);
    final syncro = ref.read(bothSyncroProvider);
    final sides = syncro
        ? <StockSide>[StockSide.a, StockSide.b]
        : <StockSide>[widget.side];
    if (ref.read(demoModeProvider)) {
      return sides;
    }
    if (!connectedOnly) {
      return sides
          .where((side) => _deviceId(stockState, side) != null)
          .toList(growable: false);
    }
    return sides.where((side) {
      final sideState = side == StockSide.a ? stockState.a : stockState.b;
      return sideState.status == DeviceConnectionState.connected &&
          _deviceId(stockState, side) != null;
    }).toList(growable: false);
  }

  String? _deviceId(StockState state, StockSide side) {
    return side == StockSide.a ? state.a.device?.id : state.b.device?.id;
  }

  bool _isModeActive(LedUiSideState state, LedMode mode) {
    return state.top.mode == mode || state.bottom.mode == mode;
  }

  String _modeLabel(LedMode mode) {
    switch (mode) {
      case LedMode.off:
        return 'OFF';
      case LedMode.color:
        return 'SOLID';
      case LedMode.rainbow:
        return 'RAINBOW';
      case LedMode.heartbeat:
        return 'HEART BEAT';
    }
  }

  Color _modeColor(LedMode mode) {
    switch (mode) {
      case LedMode.off:
        return SceptronicPalette.muted;
      case LedMode.color:
        return SceptronicPalette.primary;
      case LedMode.rainbow:
        return SceptronicPalette.secondary;
      case LedMode.heartbeat:
        return SceptronicPalette.warning;
    }
  }

  String _heartbeatLabel(int intervalMs) {
    switch (intervalMs) {
      case 1000:
        return 'Slow';
      case 600:
        return 'Normal';
      case 300:
        return 'Fast';
      default:
        return '$intervalMs ms';
    }
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    this.dense = false,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Color accent;
  final bool dense;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 0.4,
                      fontSize: dense ? 12 : null,
                    ),
              ),
            ),
            Text(
              value.round().toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SceptronicPalette.muted,
                    fontSize: dense ? 11 : null,
                  ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: accent.withValues(alpha: 0.18),
            trackHeight: dense ? 3 : 4,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
