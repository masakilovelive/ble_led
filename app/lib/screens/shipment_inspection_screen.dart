import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:usb_serial/usb_serial.dart';

import '../ble/led_ui_state.dart';
import '../ble/mcu_serial_controller.dart';
import '../ble/shipment_inspection_controller.dart';
import '../ble/stock_controller.dart';
import 'dual_color_screen.dart';
import 'sceptronic_ui.dart';
import 'setup_screen.dart';
import 'stress_lab_screen.dart';

class ShipmentInspectionScreen extends ConsumerStatefulWidget {
  const ShipmentInspectionScreen({super.key});

  @override
  ConsumerState<ShipmentInspectionScreen> createState() =>
      _ShipmentInspectionScreenState();
}

class _ShipmentInspectionScreenState
    extends ConsumerState<ShipmentInspectionScreen> {
  late final TextEditingController _testerController;
  late final TextEditingController _serialController;
  late final TextEditingController _boardController;
  late final TextEditingController _lotController;
  late final TextEditingController _fwVersionController;
  late final TextEditingController _mcuVersionController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _retryController;
  late final TextEditingController _rssiMinController;
  late final TextEditingController _batteryMinController;
  late final TextEditingController _startupMinController;
  late final TextEditingController _mcuBootSettleController;
  late final TextEditingController _mcuBridgeHostController;
  late final TextEditingController _mcuBridgePortController;
  late final TextEditingController _noteController;
  late final TextEditingController _operatorNoteController;

  bool _requireMcuRunner = true;
  bool _verifyGatt = true;
  bool _includeAcceleration = true;
  bool _mcuBusy = false;
  String? _mcuActionMessage;
  McuTransportMode _mcuTransportMode = McuTransportMode.bridge;

  @override
  void initState() {
    super.initState();
    final defaults = ShipmentInspectionConfig.defaults();
    _testerController = TextEditingController(text: defaults.testerName);
    _serialController = TextEditingController(text: defaults.serialNo);
    _boardController = TextEditingController(text: defaults.boardId);
    _lotController = TextEditingController(text: defaults.lotNo);
    _fwVersionController = TextEditingController(text: defaults.fwVersion);
    _mcuVersionController = TextEditingController(text: defaults.mcuVersion);
    _timeoutController = TextEditingController(
      text: '${defaults.connectTimeoutSeconds}',
    );
    _retryController = TextEditingController(
      text: '${defaults.connectRetryCount}',
    );
    _rssiMinController = TextEditingController(
      text: '${defaults.rssiMinDbm}',
    );
    _batteryMinController = TextEditingController(
      text: defaults.batteryMinV.toStringAsFixed(3),
    );
    _startupMinController = TextEditingController(
      text: defaults.startupVoltageMinV.toStringAsFixed(3),
    );
    _mcuBootSettleController = TextEditingController(
      text: '${defaults.mcuBootSettleMs}',
    );
    _noteController = TextEditingController(text: defaults.note);
    _operatorNoteController = TextEditingController();
    final mcuDefaults = ref.read(mcuSerialProvider);
    _mcuBridgeHostController = TextEditingController(
      text: mcuDefaults.bridgeHost,
    );
    _mcuBridgePortController = TextEditingController(
      text: '${mcuDefaults.bridgePort}',
    );
    _requireMcuRunner = defaults.requireMcuRunner;
    _verifyGatt = defaults.verifyGattOnConnect;
    _includeAcceleration = defaults.includeAccelerationCheck;
    _mcuTransportMode = mcuDefaults.transportMode;
    final mcuSerial = ref.read(mcuSerialProvider.notifier);
    Future<void>.microtask(() async {
      if (!mounted) {
        return;
      }
      await mcuSerial.refreshDevices();
    });
  }

  @override
  void dispose() {
    _testerController.dispose();
    _serialController.dispose();
    _boardController.dispose();
    _lotController.dispose();
    _fwVersionController.dispose();
    _mcuVersionController.dispose();
    _timeoutController.dispose();
    _retryController.dispose();
    _rssiMinController.dispose();
    _batteryMinController.dispose();
    _startupMinController.dispose();
    _mcuBootSettleController.dispose();
    _mcuBridgeHostController.dispose();
    _mcuBridgePortController.dispose();
    _noteController.dispose();
    _operatorNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shipmentState = ref.watch(shipmentInspectionProvider);
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);
    final mcuState = ref.watch(mcuSerialProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
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
            const Expanded(
              child: Text(
                'SHIPMENT INSPECTION',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
          IconButton(
            tooltip: 'Manual Control',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DualColorScreen(),
                ),
              );
            },
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Stress Lab',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StressLabScreen(),
                ),
              );
            },
            icon: const Icon(Icons.science),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!Platform.isAndroid)
                const _WarningCard(
                  text: 'このアプリの出荷検査実行は Android 前提です。Windows では UI 確認のみ可能です。',
                ),
              _buildRunCard(context, shipmentState),
              const SizedBox(height: 14),
              _buildConfigCard(context, shipmentState),
              const SizedBox(height: 14),
              _buildMcuCard(context, shipmentState, mcuState),
              const SizedBox(height: 14),
              _buildDeviceCard(context, stockState, ledUiState),
              if (shipmentState.awaitingOperatorStep != null) ...[
                const SizedBox(height: 14),
                _buildOperatorCard(context, shipmentState),
              ],
              const SizedBox(height: 14),
              _buildStepsCard(context, shipmentState),
              const SizedBox(height: 14),
              _buildLogsCard(context, shipmentState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunCard(
    BuildContext context,
    ShipmentInspectionState state,
  ) {
    return Card(
      color: const Color(0xFF0F1318),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'SHIPMENT FLOW',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                ),
                const Spacer(),
                _StatusBadge(
                  label: state.status.name.toUpperCase(),
                  color: _runStatusColor(state.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.message ?? 'Ready',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: 'Progress',
                  value: '${state.completedSteps}/${state.steps.length}',
                  color: const Color(0xFF4DD0E1),
                ),
                _MetricChip(
                  label: 'Report ID',
                  value: state.reportId ?? '--',
                  color: const Color(0xFFE9C46A),
                ),
                _MetricChip(
                  label: 'App Version',
                  value: state.appVersion ?? '--',
                  color: const Color(0xFF60D394),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      state.isRunning ? null : () => _startInspection(context),
                  child: const Text('Start Inspection'),
                ),
                OutlinedButton(
                  onPressed: state.isRunning
                      ? () =>
                          ref.read(shipmentInspectionProvider.notifier).stop()
                      : null,
                  child: const Text('Stop'),
                ),
                OutlinedButton(
                  onPressed: state.reportPath == null
                      ? null
                      : () => _copyText(
                            context,
                            state.reportPath!,
                            'Report path copied',
                          ),
                  child: const Text('Copy Report Path'),
                ),
              ],
            ),
            if (state.reportPath != null) ...[
              const SizedBox(height: 10),
              Text(
                state.reportPath!,
                style: const TextStyle(
                  color: Colors.white60,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
            if (state.failureClass != null) ...[
              const SizedBox(height: 10),
              Text(
                'NG: ${state.failureClass}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if ((state.failureDetail ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  state.failureDetail!,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(
    BuildContext context,
    ShipmentInspectionState state,
  ) {
    final enabled = !state.isRunning;
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record & Thresholds',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InputField(
                  label: 'Tester',
                  controller: _testerController,
                  width: 180,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'Serial No',
                  controller: _serialController,
                  width: 180,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'Board ID',
                  controller: _boardController,
                  width: 180,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'Lot No',
                  controller: _lotController,
                  width: 180,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'FW Version',
                  controller: _fwVersionController,
                  width: 180,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'MCU Version',
                  controller: _mcuVersionController,
                  width: 180,
                  enabled: enabled && _requireMcuRunner,
                ),
                _InputField(
                  label: 'Connect Timeout(s)',
                  controller: _timeoutController,
                  width: 160,
                  enabled: enabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                ),
                _InputField(
                  label: 'Retry Count',
                  controller: _retryController,
                  width: 130,
                  enabled: enabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                ),
                _InputField(
                  label: 'RSSI Min(dBm)',
                  controller: _rssiMinController,
                  width: 150,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'Battery Min(V)',
                  controller: _batteryMinController,
                  width: 150,
                  enabled: enabled,
                ),
                _InputField(
                  label: 'Startup Min(V)',
                  controller: _startupMinController,
                  width: 150,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                _InputField(
                  label: 'MCU Boot Settle(ms)',
                  controller: _mcuBootSettleController,
                  width: 170,
                  enabled: enabled && _requireMcuRunner,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              enabled: enabled,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Run Note'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: _requireMcuRunner,
                  onSelected: enabled
                      ? (value) => setState(() => _requireMcuRunner = value)
                      : null,
                  label: const Text('MCU Runner'),
                  selectedColor: const Color(0xFF4A3118),
                  checkmarkColor: Colors.white,
                ),
                FilterChip(
                  selected: _verifyGatt,
                  onSelected: enabled
                      ? (value) => setState(() => _verifyGatt = value)
                      : null,
                  label: const Text('Verify GATT'),
                  selectedColor: const Color(0xFF184A31),
                  checkmarkColor: Colors.white,
                ),
                FilterChip(
                  selected: _includeAcceleration,
                  onSelected: enabled
                      ? (value) => setState(() => _includeAcceleration = value)
                      : null,
                  label: const Text('Acceleration Step'),
                  selectedColor: const Color(0xFF184A31),
                  checkmarkColor: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    StockState stockState,
    LedUiState ledUiState,
  ) {
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assigned Devices',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DevicePanel(
                    title: 'Stock A',
                    sideState: stockState.a,
                    batteryVoltage: ledUiState.a.batteryVoltage,
                    isCharging: ledUiState.a.charging,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DevicePanel(
                    title: 'Stock B',
                    sideState: stockState.b,
                    batteryVoltage: ledUiState.b.batteryVoltage,
                    isCharging: ledUiState.b.charging,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcuCard(
    BuildContext context,
    ShipmentInspectionState shipmentState,
    McuSerialState mcuState,
  ) {
    final enabled = !shipmentState.isRunning;
    final isBridge = _mcuTransportMode == McuTransportMode.bridge;
    final bridgePort = _mcuBridgePortController.text.trim().isEmpty
        ? '9876'
        : _mcuBridgePortController.text.trim();
    final serial = ref.read(mcuSerialProvider.notifier);
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'MCU Runner',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _StatusBadge(
                  label: mcuState.statusText,
                  color: mcuState.connected
                      ? const Color(0xFF60D394)
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '出荷検査は MCU runner で治具電源を上げる前提です。boot 後に BLE 接続へ進みます。',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            if (isBridge)
              SelectableText(
                'Bridge list: powershell -ExecutionPolicy Bypass -File .\\scripts\\start_mcu_android_bridge.ps1 -ListPorts\n'
                'Bridge start: powershell -ExecutionPolicy Bypass -File .\\scripts\\start_mcu_android_bridge.ps1 -ComPort COM4 -ListenPort $bridgePort\n'
                'Android app: host 127.0.0.1 / port $bridgePort',
                style: const TextStyle(color: Colors.amberAccent),
              )
            else
              const Text(
                'USB OTG: Android が USB host になっている状態で UNO を直結してください。',
                style: TextStyle(color: Colors.amberAccent),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('PC Bridge'),
                  selected: isBridge,
                  onSelected: enabled && !mcuState.connected
                      ? (_) {
                          setState(
                            () => _mcuTransportMode = McuTransportMode.bridge,
                          );
                          serial.setTransportMode(McuTransportMode.bridge);
                        }
                      : null,
                ),
                ChoiceChip(
                  label: const Text('USB OTG'),
                  selected: !isBridge,
                  onSelected: enabled && !mcuState.connected
                      ? (_) {
                          setState(
                            () => _mcuTransportMode = McuTransportMode.usb,
                          );
                          serial.setTransportMode(McuTransportMode.usb);
                          serial.refreshDevices();
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isBridge)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _InputField(
                    label: 'Bridge Host',
                    controller: _mcuBridgeHostController,
                    width: 180,
                    enabled: enabled,
                  ),
                  _InputField(
                    label: 'Bridge Port',
                    controller: _mcuBridgePortController,
                    width: 120,
                    enabled: enabled,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    keyboardType: TextInputType.number,
                  ),
                  FilledButton(
                    onPressed: enabled
                        ? () {
                            _applyMcuConfig();
                            serial.connect();
                          }
                        : null,
                    child: const Text('Connect MCU'),
                  ),
                  OutlinedButton(
                    onPressed: enabled && mcuState.connected
                        ? () => serial.disconnect()
                        : null,
                    child: const Text('Disconnect MCU'),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      initialValue: mcuState.selectedDeviceId != null &&
                              mcuState.devices.any(
                                (device) =>
                                    '${device.deviceId}' ==
                                    mcuState.selectedDeviceId,
                              )
                          ? mcuState.selectedDeviceId
                          : null,
                      items: mcuState.devices
                          .map(
                            (device) => DropdownMenuItem<String>(
                              value: '${device.deviceId}',
                              child: Text(_usbDeviceLabel(device)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: enabled
                          ? (value) => serial.selectDeviceId(value)
                          : null,
                      decoration: _inputDecoration('USB Device'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? () => serial.refreshDevices() : null,
                    child: const Text('Refresh'),
                  ),
                  FilledButton(
                    onPressed: enabled ? () => serial.connect() : null,
                    child: const Text('Connect MCU'),
                  ),
                  OutlinedButton(
                    onPressed: enabled && mcuState.connected
                        ? () => serial.disconnect()
                        : null,
                    child: const Text('Disconnect MCU'),
                  ),
                ],
              ),
            if (mcuState.message != null) ...[
              const SizedBox(height: 8),
              Text(
                mcuState.message!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _mcuBusy || shipmentState.isRunning
                      ? null
                      : () => _sendMcuManualCommand(
                            command: 'boot',
                            label: 'MCU Boot 2s',
                            expectedState: 'START_PULSE_OFF',
                            timeout: const Duration(seconds: 7),
                          ),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('MCU Boot 2s'),
                ),
                OutlinedButton.icon(
                  onPressed: _mcuBusy || shipmentState.isRunning
                      ? null
                      : () => _sendMcuManualCommand(
                            command: 'poff',
                            label: 'MCU Power Off',
                            expectedState: 'POWER_B_OFF',
                            timeout: const Duration(seconds: 2),
                          ),
                  icon: const Icon(Icons.power_off),
                  label: const Text('MCU Power Off'),
                ),
                if (_mcuBusy)
                  const _StatusBadge(
                    label: 'BUSY',
                    color: Color(0xFFE9C46A),
                  ),
              ],
            ),
            if (_mcuActionMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _mcuActionMessage!,
                style: TextStyle(
                  color: _mcuActionMessage!.contains('failed')
                      ? Colors.redAccent
                      : Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperatorCard(
    BuildContext context,
    ShipmentInspectionState state,
  ) {
    final kind = state.awaitingOperatorStep!;
    return Card(
      color: const Color(0xFF1A1310),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFFFA94D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operator Check: ${kind.title}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFFFD166),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              state.operatorPrompt ?? '',
              style: const TextStyle(color: Colors.white),
            ),
            if ((state.operatorHint ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                state.operatorHint!,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _operatorNoteController,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Operator Note'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _submitOperatorDecision(
                    context,
                    ShipmentOperatorDecision.pass,
                  ),
                  child: const Text('PASS'),
                ),
                FilledButton.tonal(
                  onPressed: () => _submitOperatorDecision(
                    context,
                    ShipmentOperatorDecision.fail,
                  ),
                  child: const Text('FAIL'),
                ),
                OutlinedButton(
                  onPressed: () => _submitOperatorDecision(
                    context,
                    ShipmentOperatorDecision.skip,
                  ),
                  child: const Text('SKIP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsCard(
    BuildContext context,
    ShipmentInspectionState state,
  ) {
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Inspection Steps',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${state.completedSteps}/${state.steps.length} complete',
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < state.steps.length; index++) ...[
              _buildStepTile(
                context,
                step: state.steps[index],
                order: index + 1,
                active: state.activeStepIndex == index,
              ),
              if (index != state.steps.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepTile(
    BuildContext context, {
    required ShipmentStepEntry step,
    required int order,
    required bool active,
  }) {
    final borderColor = active
        ? const Color(0xFF4DD0E1)
        : _stepStatusColor(step.status).withValues(alpha: 0.45);
    final metrics = <String>[];
    if (step.rssiA != null || step.rssiB != null) {
      metrics.add('RSSI A=${step.rssiA ?? '--'} / B=${step.rssiB ?? '--'}');
    }
    if (step.batteryA != null || step.batteryB != null) {
      metrics.add(
        'Battery A=${step.batteryA?.toStringAsFixed(3) ?? '--'} / B=${step.batteryB?.toStringAsFixed(3) ?? '--'}',
      );
    }
    if (step.duration != null) {
      metrics.add('Duration ${step.duration!.inMilliseconds}ms');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1319),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF18212B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$order',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.kind.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      step.kind.description,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatusBadge(
                label: step.status.name.toUpperCase(),
                color: _stepStatusColor(step.status),
              ),
            ],
          ),
          if (step.detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              step.detail,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          if (step.failureClass != null) ...[
            const SizedBox(height: 8),
            Text(
              'Failure: ${step.failureClass}',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if ((step.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note: ${step.note}',
              style: const TextStyle(color: Colors.white60),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final metric in metrics)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF172028),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      metric,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogsCard(
    BuildContext context,
    ShipmentInspectionState state,
  ) {
    final visibleLogs = state.logs.reversed.take(80).toList(growable: false);
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Run Logs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: visibleLogs.isEmpty
                      ? null
                      : () => _copyText(
                            context,
                            visibleLogs.reversed.join('\n'),
                            'Logs copied',
                          ),
                  child: const Text('Copy Logs'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0F14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: SelectableText(
                visibleLogs.isEmpty ? 'No logs yet.' : visibleLogs.join('\n'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF0D1319),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4DD0E1)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
    );
  }

  Future<void> _startInspection(BuildContext context) async {
    final timeout = int.tryParse(_timeoutController.text.trim());
    final retries = int.tryParse(_retryController.text.trim());
    final rssiMin = int.tryParse(_rssiMinController.text.trim());
    final batteryMin = double.tryParse(_batteryMinController.text.trim());
    final startupMin = double.tryParse(_startupMinController.text.trim());
    final mcuBootSettle = int.tryParse(_mcuBootSettleController.text.trim());
    final mcuBridgePort = int.tryParse(_mcuBridgePortController.text.trim());

    if (timeout == null ||
        retries == null ||
        rssiMin == null ||
        batteryMin == null ||
        startupMin == null ||
        (_requireMcuRunner && mcuBootSettle == null) ||
        (_requireMcuRunner &&
            _mcuTransportMode == McuTransportMode.bridge &&
            mcuBridgePort == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threshold values are invalid.')),
      );
      return;
    }

    if (timeout <= 0 ||
        retries < 0 ||
        batteryMin <= 0 ||
        startupMin <= 0 ||
        (_requireMcuRunner && mcuBootSettle! < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threshold values must be positive.')),
      );
      return;
    }

    _applyMcuConfig();
    _operatorNoteController.clear();
    final config = ShipmentInspectionConfig(
      testerName: _testerController.text.trim(),
      serialNo: _serialController.text.trim(),
      boardId: _boardController.text.trim(),
      lotNo: _lotController.text.trim(),
      fwVersion: _fwVersionController.text.trim(),
      mcuVersion: _mcuVersionController.text.trim(),
      note: _noteController.text.trim(),
      connectTimeoutSeconds: timeout,
      connectRetryCount: retries,
      rssiMinDbm: rssiMin,
      mcuBootSettleMs: mcuBootSettle ?? 0,
      batteryMinV: batteryMin,
      startupVoltageMinV: startupMin,
      requireMcuRunner: _requireMcuRunner,
      verifyGattOnConnect: _verifyGatt,
      includeAccelerationCheck: _includeAcceleration,
    );

    await ref.read(shipmentInspectionProvider.notifier).start(config);
  }

  void _submitOperatorDecision(
    BuildContext context,
    ShipmentOperatorDecision decision,
  ) {
    final note = _operatorNoteController.text.trim();
    ref.read(shipmentInspectionProvider.notifier).submitOperatorDecision(
          decision,
          note: note,
        );
    _operatorNoteController.clear();
    final message = switch (decision) {
      ShipmentOperatorDecision.pass => 'Operator marked PASS',
      ShipmentOperatorDecision.fail => 'Operator marked FAIL',
      ShipmentOperatorDecision.skip => 'Operator marked SKIP',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _applyMcuConfig() {
    final port = int.tryParse(_mcuBridgePortController.text.trim());
    final serial = ref.read(mcuSerialProvider.notifier);
    serial.setTransportMode(_mcuTransportMode);
    serial.setBridgeEndpoint(
      host: _mcuBridgeHostController.text.trim(),
      port: port,
    );
  }

  Future<void> _sendMcuManualCommand({
    required String command,
    required String label,
    required String expectedState,
    required Duration timeout,
  }) async {
    if (_mcuBusy) {
      return;
    }
    setState(() {
      _mcuBusy = true;
      _mcuActionMessage = '$label running...';
    });
    try {
      _applyMcuConfig();
      final serial = ref.read(mcuSerialProvider.notifier);
      final connected =
          ref.read(mcuSerialProvider).connected ? true : await serial.connect();
      if (!connected) {
        if (!mounted) {
          return;
        }
        setState(() {
          _mcuActionMessage =
              'MCU connect failed: ${ref.read(mcuSerialProvider).message ?? 'unknown error'}';
        });
        return;
      }

      final event = await serial.sendCommandWait(
        command,
        expectedState,
        timeout: timeout,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mcuActionMessage = event == null
            ? '$label failed: timeout waiting for $expectedState'
            : '$label done';
      });
    } finally {
      if (mounted) {
        setState(() {
          _mcuBusy = false;
        });
      }
    }
  }

  Future<void> _copyText(
    BuildContext context,
    String value,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _usbDeviceLabel(UsbDevice device) {
    final product = (device.productName ?? '').trim();
    if (product.isNotEmpty) {
      return product;
    }
    return 'USB ${device.deviceId}';
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.controller,
    required this.width,
    required this.enabled,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final double width;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF0D1319),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4DD0E1)),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 126),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF172028),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({
    required this.title,
    required this.sideState,
    required this.batteryVoltage,
    required this.isCharging,
  });

  final String title;
  final StockSideState sideState;
  final double? batteryVoltage;
  final bool isCharging;

  @override
  Widget build(BuildContext context) {
    final device = sideState.device;
    final statusColor = _connectionColor(sideState.status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1319),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              _StatusBadge(
                label: sideState.status.name.toUpperCase(),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            device?.name?.trim().isNotEmpty == true
                ? device!.name!.trim()
                : 'Unassigned',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pair ${sideState.pairNumber ?? '--'} / Role ${sideState.role ?? '--'}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Battery ${batteryVoltage?.toStringAsFixed(3) ?? '--'} V',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              if (isCharging)
                const Icon(
                  Icons.bolt_rounded,
                  color: Colors.amberAccent,
                  size: 18,
                ),
            ],
          ),
          if ((sideState.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sideState.message!,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A180C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFA94D)),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

Color _runStatusColor(ShipmentRunStatus status) {
  switch (status) {
    case ShipmentRunStatus.idle:
      return const Color(0xFF94A3B8);
    case ShipmentRunStatus.running:
      return const Color(0xFF4DD0E1);
    case ShipmentRunStatus.awaitingOperator:
      return const Color(0xFFFFD166);
    case ShipmentRunStatus.stopped:
      return const Color(0xFFF4A261);
    case ShipmentRunStatus.done:
      return const Color(0xFF60D394);
    case ShipmentRunStatus.failed:
      return const Color(0xFFFF6B6B);
    case ShipmentRunStatus.error:
      return const Color(0xFFE63946);
  }
}

Color _stepStatusColor(ShipmentStepStatus status) {
  switch (status) {
    case ShipmentStepStatus.pending:
      return const Color(0xFF94A3B8);
    case ShipmentStepStatus.running:
      return const Color(0xFF4DD0E1);
    case ShipmentStepStatus.awaitingOperator:
      return const Color(0xFFFFD166);
    case ShipmentStepStatus.pass:
      return const Color(0xFF60D394);
    case ShipmentStepStatus.fail:
      return const Color(0xFFFF6B6B);
    case ShipmentStepStatus.skipped:
      return const Color(0xFFF4A261);
  }
}

Color _connectionColor(DeviceConnectionState status) {
  switch (status) {
    case DeviceConnectionState.connected:
      return const Color(0xFF60D394);
    case DeviceConnectionState.connecting:
      return const Color(0xFF4DD0E1);
    case DeviceConnectionState.disconnecting:
      return const Color(0xFFF4A261);
    case DeviceConnectionState.disconnected:
      return const Color(0xFF94A3B8);
  }
}
