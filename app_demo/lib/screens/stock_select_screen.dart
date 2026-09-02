import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/product_ui_state.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';
import 'bluetooth_setting_screen.dart';
import 'led_setting_screen.dart';
import 'sceptronic_ui.dart';

class StockSelectScreen extends ConsumerStatefulWidget {
  const StockSelectScreen({super.key});

  @override
  ConsumerState<StockSelectScreen> createState() => _StockSelectScreenState();
}

class _StockSelectScreenState extends ConsumerState<StockSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    Future<void>.microtask(() async {
      await Future.wait<void>([
        ref.read(stockProvider.notifier).ensureLoaded(),
        ref.read(ledUiProvider.notifier).ensureLoaded(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);
    final syncro = ref.watch(bothSyncroProvider);
    final demoMode = ref.watch(demoModeProvider);

    return Scaffold(
      backgroundColor: SceptronicPalette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 18,
        title: const SceptronicBrandLockup(compact: true),
        actions: [
          IconButton(
            tooltip: 'Bluetooth Setting',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BluetoothSettingScreen(),
                ),
              );
            },
            icon: const Icon(Icons.bluetooth_rounded),
          ),
        ],
      ),
      body: SceptronicBackdrop(
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: _motionController,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 940;
                  final compactStocks = constraints.maxWidth < 780;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (demoMode && !sceptronicScreenshotMode) ...[
                          const SceptronicDemoBanner(),
                          const SizedBox(height: 14),
                        ],
                        _buildTopBar(
                          context,
                          syncro: syncro,
                          wide: wide,
                        ),
                        const SizedBox(height: 18),
                        if (!_ready)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 36),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildStockCard(
                                  context,
                                  side: StockSide.a,
                                  stockState: stockState,
                                  ledUiState: ledUiState,
                                  compact: false,
                                  demoMode: demoMode,
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _buildStockCard(
                                  context,
                                  side: StockSide.b,
                                  stockState: stockState,
                                  ledUiState: ledUiState,
                                  compact: false,
                                  demoMode: demoMode,
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildStockCard(
                                  context,
                                  side: StockSide.a,
                                  stockState: stockState,
                                  ledUiState: ledUiState,
                                  compact: compactStocks,
                                  demoMode: demoMode,
                                ),
                              ),
                              SizedBox(width: compactStocks ? 10 : 18),
                              Expanded(
                                child: _buildStockCard(
                                  context,
                                  side: StockSide.b,
                                  stockState: stockState,
                                  ledUiState: ledUiState,
                                  compact: compactStocks,
                                  demoMode: demoMode,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool syncro,
    required bool wide,
  }) {
    const title = SceptronicSectionTitle(title: 'STOCK SELECT');
    final syncControl = _buildSyncPanel(context, syncro);

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: title),
          const SizedBox(width: 16),
          SizedBox(width: 270, child: syncControl),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 12),
        syncControl,
      ],
    );
  }

  Widget _buildSyncPanel(BuildContext context, bool syncro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0C1016),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A+B / BOTH SYNCRO',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: SceptronicPalette.muted,
                        letterSpacing: 0.8,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  syncro ? 'SYNC ON' : 'SYNC OFF',
                  style: sceptronicDisplayStyle(
                    context,
                    size: 18,
                    color: syncro
                        ? SceptronicPalette.primary
                        : SceptronicPalette.muted,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: syncro,
            activeThumbColor: SceptronicPalette.primary,
            onChanged: (value) {
              ref.read(bothSyncroProvider.notifier).state = value;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(
    BuildContext context, {
    required StockSide side,
    required StockState stockState,
    required LedUiState ledUiState,
    required bool compact,
    required bool demoMode,
  }) {
    final sideState = side == StockSide.a ? stockState.a : stockState.b;
    final sideUi = ledUiState.sideState(side);
    final liveScreenshot = demoMode && sceptronicScreenshotMode;
    final batteryPercent =
        (sideUi.batteryPercent.clamp(0.0, 1.0) * 100).round();
    final batteryDetail = liveScreenshot
        ? 'Battery tracking active'
        : demoMode
            ? 'Virtual battery telemetry'
            : sideUi.batteryVoltage == null
                ? 'Battery data waits for BLE connect.'
                : sideUi.charging
                    ? 'Charging'
                    : 'Battery tracking active';
    final connectionColor = liveScreenshot
        ? SceptronicPalette.success
        : demoMode
            ? SceptronicPalette.success
            : _connectionColor(sideState.status);
    final connectionLabel = liveScreenshot
        ? 'CONNECTED'
        : demoMode
            ? 'DEMO READY'
            : _connectionLabel(sideState.status);
    final deviceLabel = liveScreenshot
        ? (side == StockSide.a ? 'stockA' : 'stockB')
        : demoMode
            ? (side == StockSide.a ? 'Virtual Stock A' : 'Virtual Stock B')
            : sideState.device?.name ?? 'No device assigned';

    return SceptronicPanel(
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side == StockSide.a ? 'STOCK A' : 'STOCK B',
            style: sceptronicDisplayStyle(
              context,
              size: compact ? 16 : 22,
              letterSpacing: compact ? 0.8 : 1.2,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          (compact
              ? Column(
                  children: [
                    SceptronicMetricTile(
                      label: 'Connection',
                      value: connectionLabel,
                      detail: deviceLabel,
                      icon: Icons.bluetooth_connected_rounded,
                      accent: connectionColor,
                      compact: true,
                    ),
                    const SizedBox(height: 10),
                    SceptronicMetricTile(
                      label: 'Battery',
                      value: '$batteryPercent%',
                      detail: batteryDetail,
                      icon: Icons.battery_full_rounded,
                      accent: batteryPercent >= 25
                          ? SceptronicPalette.success
                          : SceptronicPalette.warning,
                      compact: true,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: SceptronicMetricTile(
                        label: 'Connection',
                        value: connectionLabel,
                        detail: deviceLabel,
                        icon: Icons.bluetooth_connected_rounded,
                        accent: connectionColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SceptronicMetricTile(
                        label: 'Battery',
                        value: '$batteryPercent%',
                        detail: batteryDetail,
                        icon: Icons.battery_full_rounded,
                        accent: batteryPercent >= 25
                            ? SceptronicPalette.success
                            : SceptronicPalette.warning,
                      ),
                    ),
                  ],
                )),
          SizedBox(height: compact ? 14 : 22),
          Center(
            child: StockPreview(
              sideLabel: side == StockSide.a ? 'stockA' : 'stockB',
              sideState: sideUi,
              motionValue: _motionController.value,
              compact: compact,
              footer: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 20 : 34,
                    vertical: compact ? 12 : 14,
                  ),
                  backgroundColor: SceptronicPalette.primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LedSettingScreen(side: side),
                    ),
                  );
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionLabel(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return 'CONNECTED';
      case DeviceConnectionState.connecting:
        return 'CONNECTING';
      case DeviceConnectionState.disconnecting:
        return 'DISCONNECTING';
      case DeviceConnectionState.disconnected:
        return 'DISCONNECTED';
    }
  }

  Color _connectionColor(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return SceptronicPalette.success;
      case DeviceConnectionState.connecting:
        return SceptronicPalette.primary;
      case DeviceConnectionState.disconnecting:
        return SceptronicPalette.warning;
      case DeviceConnectionState.disconnected:
        return SceptronicPalette.danger;
    }
  }
}
