import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:usb_serial/usb_serial.dart';

import '../ble/led_ui_state.dart';
import '../ble/mcu_serial_controller.dart';
import '../ble/stress_lab_controller.dart';
import '../ble/stock_controller.dart';
import 'dual_color_screen.dart';
import 'setup_screen.dart';

class StressLabScreen extends ConsumerStatefulWidget {
  const StressLabScreen({super.key});

  @override
  ConsumerState<StressLabScreen> createState() => _StressLabScreenState();
}

class _StressLabScreenState extends ConsumerState<StressLabScreen> {
  late final TextEditingController _cyclesController;
  late final TextEditingController _settleController;
  late final TextEditingController _holdController;
  late final TextEditingController _gapController;
  late final TextEditingController _mcuOffGuardController;
  late final TextEditingController _mcuPowerToD5Controller;
  late final TextEditingController _mcuD5PulseController;
  late final TextEditingController _mcuConnectWindowController;
  late final TextEditingController _mcuDisconnectWindowController;
  late final TextEditingController _mcuBridgeHostController;
  late final TextEditingController _mcuBridgePortController;

  StressRunnerMode _runnerMode = StressRunnerMode.mcu;
  StressSweepPlan _sweepPlan = StressSweepPlan.matrix73;
  McuTransportMode _mcuTransportMode = McuTransportMode.bridge;
  bool _scanBeforeConnect = true;
  bool _reconnectEachCycle = true;
  bool _verifyGattOnConnect = true;
  bool _readBatteryEachCase = true;
  bool _stopOnFail = false;
  bool _mcuSensorOnCheck = false;
  bool _mcuSensorOffCheck = false;
  bool _mcuBusy = false;
  String? _mcuActionMessage;
  bool _includeColor = true;
  bool _includeHeartbeat = true;
  bool _includeRainbow = true;
  bool _includeSyncroCases = true;

  @override
  void initState() {
    super.initState();
    final defaults = StressSettings.defaults();
    _cyclesController = TextEditingController(text: '${defaults.cycles}');
    _settleController = TextEditingController(text: '${defaults.settleMs}');
    _holdController = TextEditingController(text: '${defaults.caseHoldMs}');
    _gapController = TextEditingController(text: '${defaults.caseGapMs}');
    _mcuOffGuardController = TextEditingController(
      text: '${defaults.mcuOffGuardMs}',
    );
    _mcuPowerToD5Controller = TextEditingController(
      text: '${defaults.mcuPowerToD5Ms}',
    );
    _mcuD5PulseController = TextEditingController(
      text: '${defaults.mcuD5PulseMs}',
    );
    _mcuConnectWindowController = TextEditingController(
      text: '${defaults.mcuConnectWindowMs}',
    );
    _mcuDisconnectWindowController = TextEditingController(
      text: '${defaults.mcuDisconnectWindowMs}',
    );
    final mcuDefaults = McuSerialState.initial();
    _mcuBridgeHostController = TextEditingController(
      text: mcuDefaults.bridgeHost,
    );
    _mcuBridgePortController = TextEditingController(
      text: '${mcuDefaults.bridgePort}',
    );
    _sweepPlan = defaults.sweepPlan;
    _runnerMode = defaults.runnerMode;
    _mcuTransportMode = mcuDefaults.transportMode;
    _scanBeforeConnect = defaults.scanBeforeConnect;
    _reconnectEachCycle = defaults.reconnectEachCycle;
    _verifyGattOnConnect = defaults.verifyGattOnConnect;
    _readBatteryEachCase = defaults.readBatteryEachCase;
    _stopOnFail = defaults.stopOnFail;
    _mcuSensorOnCheck = defaults.mcuSensorOnCheck;
    _mcuSensorOffCheck = defaults.mcuSensorOffCheck;
    _includeColor = defaults.includeColor;
    _includeHeartbeat = defaults.includeHeartbeat;
    _includeRainbow = defaults.includeRainbow;
    _includeSyncroCases = defaults.includeSyncroCases;
    Future<void>.microtask(
      () => ref.read(mcuSerialProvider.notifier).refreshDevices(),
    );
  }

  @override
  void dispose() {
    _cyclesController.dispose();
    _settleController.dispose();
    _holdController.dispose();
    _gapController.dispose();
    _mcuOffGuardController.dispose();
    _mcuPowerToD5Controller.dispose();
    _mcuD5PulseController.dispose();
    _mcuConnectWindowController.dispose();
    _mcuDisconnectWindowController.dispose();
    _mcuBridgeHostController.dispose();
    _mcuBridgePortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stressLabProvider);
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);
    final mcuState = ref.watch(mcuSerialProvider);
    final preview = _previewSettings();
    final caseCount =
        ref.read(stressLabProvider.notifier).plannedCaseCount(preview);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('ANDROID BLE STRESS'),
        actions: [
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsCard(
                context,
                state,
                stockState,
                mcuState,
                caseCount,
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(context, state),
              const SizedBox(height: 14),
              _buildDeviceCard(context, stockState, ledUiState),
              if (_runnerMode == StressRunnerMode.mcu) ...[
                const SizedBox(height: 14),
                _buildMcuLogCard(context, mcuState),
              ],
              const SizedBox(height: 14),
              _buildRecentCard(context, state),
              const SizedBox(height: 14),
              _buildLogsCard(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    StressLabState state,
    StockState stockState,
    McuSerialState mcuState,
    int caseCount,
  ) {
    final isMcu = _runnerMode == StressRunnerMode.mcu;
    final usesFeatureTransition =
        _sweepPlan == StressSweepPlan.featureTransition9;
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
                  'STRESS MATRIX',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                ),
                const Spacer(),
                _StatusBadge(
                  label: state.statusText,
                  color: _runStatusColor(state.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isMcu
                  ? 'MCU Power Runner waits for UNO state events, then Android connects to Stock A/B inside each power window.'
                  : 'Android keeps the existing BLE LED protocol and sweeps COLOR / SYNCRO / HEARTBEAT / RAINBOW across Stock A/B.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('MCU Power Runner'),
                  selected: _runnerMode == StressRunnerMode.mcu,
                  onSelected: state.isRunning
                      ? null
                      : (_) =>
                          setState(() => _runnerMode = StressRunnerMode.mcu),
                ),
                ChoiceChip(
                  label: const Text('PC BLE Control'),
                  selected: _runnerMode == StressRunnerMode.pc,
                  onSelected: state.isRunning
                      ? null
                      : (_) =>
                          setState(() => _runnerMode = StressRunnerMode.pc),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Matrix Sweep'),
                  selected: _sweepPlan == StressSweepPlan.matrix73,
                  onSelected: state.isRunning
                      ? null
                      : (_) => setState(
                            () => _sweepPlan = StressSweepPlan.matrix73,
                          ),
                ),
                ChoiceChip(
                  label: const Text('Feature Transition'),
                  selected: usesFeatureTransition,
                  onSelected: state.isRunning
                      ? null
                      : (_) => setState(
                            () => _sweepPlan =
                                StressSweepPlan.featureTransition9,
                          ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Planned cases per cycle: $caseCount',
              style: const TextStyle(
                color: Color(0xFF8ECAE6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _sweepPlan.description,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            if (isMcu) ...[
              _buildMcuSerialControls(context, state, mcuState),
              const SizedBox(height: 12),
              _buildMcuPowerControls(context, state, mcuState),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _LabeledInput(
                  label: 'Cycles',
                  controller: _cyclesController,
                  width: 100,
                  enabled: !state.isRunning,
                ),
                _LabeledInput(
                  label: 'Post Connect Delay (ms)',
                  controller: _settleController,
                  width: 150,
                  enabled: !state.isRunning,
                ),
                _LabeledInput(
                  label: 'Case Hold (ms)',
                  controller: _holdController,
                  width: 140,
                  enabled: !state.isRunning,
                ),
                _LabeledInput(
                  label: 'Case Gap (ms)',
                  controller: _gapController,
                  width: 130,
                  enabled: !state.isRunning,
                ),
              ],
            ),
            if (isMcu) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _LabeledInput(
                    label: 'MCU Off Guard (ms)',
                    controller: _mcuOffGuardController,
                    width: 150,
                    enabled: !state.isRunning,
                  ),
                  _LabeledInput(
                    label: 'MCU PWR->D5 (ms)',
                    controller: _mcuPowerToD5Controller,
                    width: 150,
                    enabled: !state.isRunning,
                  ),
                  _LabeledInput(
                    label: 'MCU D5 Pulse (ms)',
                    controller: _mcuD5PulseController,
                    width: 150,
                    enabled: !state.isRunning,
                  ),
                  _LabeledInput(
                    label: 'MCU Connect Window (ms)',
                    controller: _mcuConnectWindowController,
                    width: 180,
                    enabled: !state.isRunning,
                  ),
                  _LabeledInput(
                    label: 'MCU Disconnect Wait (ms)',
                    controller: _mcuDisconnectWindowController,
                    width: 180,
                    enabled: !state.isRunning,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildToggle(
                  label: 'Scan Before Connect',
                  value: _scanBeforeConnect,
                  enabled: !state.isRunning,
                  onChanged: (value) =>
                      setState(() => _scanBeforeConnect = value),
                ),
                _buildToggle(
                  label: 'Reconnect Each Cycle',
                  value: _reconnectEachCycle,
                  enabled: !state.isRunning && !isMcu,
                  onChanged: (value) =>
                      setState(() => _reconnectEachCycle = value),
                ),
                _buildToggle(
                  label: 'Strict GATT Verify',
                  value: _verifyGattOnConnect,
                  enabled: !state.isRunning,
                  onChanged: (value) =>
                      setState(() => _verifyGattOnConnect = value),
                ),
                _buildToggle(
                  label: 'Battery Read Each Case',
                  value: _readBatteryEachCase,
                  enabled: !state.isRunning,
                  onChanged: (value) =>
                      setState(() => _readBatteryEachCase = value),
                ),
                _buildToggle(
                  label: 'Stop On First Failure',
                  value: _stopOnFail,
                  enabled: !state.isRunning,
                  onChanged: (value) => setState(() => _stopOnFail = value),
                ),
                if (isMcu)
                  _buildToggle(
                    label: 'MCU Sensor ON Check',
                    value: _mcuSensorOnCheck,
                    enabled: !state.isRunning,
                    onChanged: (value) =>
                        setState(() => _mcuSensorOnCheck = value),
                  ),
                if (isMcu)
                  _buildToggle(
                    label: 'MCU Sensor OFF Check',
                    value: _mcuSensorOffCheck,
                    enabled: !state.isRunning,
                    onChanged: (value) =>
                        setState(() => _mcuSensorOffCheck = value),
                  ),
                _buildToggle(
                  label: 'Include Color',
                  value: _includeColor,
                  enabled: !state.isRunning && !usesFeatureTransition,
                  onChanged: (value) => setState(() => _includeColor = value),
                ),
                _buildToggle(
                  label: 'Include Heartbeat',
                  value: _includeHeartbeat,
                  enabled: !state.isRunning && !usesFeatureTransition,
                  onChanged: (value) =>
                      setState(() => _includeHeartbeat = value),
                ),
                _buildToggle(
                  label: 'Include Rainbow',
                  value: _includeRainbow,
                  enabled: !state.isRunning && !usesFeatureTransition,
                  onChanged: (value) => setState(() => _includeRainbow = value),
                ),
                _buildToggle(
                  label: 'Include Syncro Cases',
                  value: _includeSyncroCases,
                  enabled: !state.isRunning && !usesFeatureTransition,
                  onChanged: (value) =>
                      setState(() => _includeSyncroCases = value),
                ),
              ],
            ),
            if (usesFeatureTransition) ...[
              const SizedBox(height: 8),
              const Text(
                'Feature Transition uses a fixed 9-case order: STOCK_A -> STOCK_B -> SYNCRO, each switching COLOR -> HEARTBEAT -> RAINBOW without cutting power inside the cycle.',
                style: TextStyle(color: Colors.amberAccent),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: state.isRunning
                      ? null
                      : () => _startRun(context, fixedCycles: 1),
                  child: const Text('Start 1 Sweep'),
                ),
                FilledButton.tonal(
                  onPressed: state.isRunning ? null : () => _startRun(context),
                  child: const Text('Start Custom'),
                ),
                OutlinedButton(
                  onPressed: state.isRunning
                      ? () => ref.read(stressLabProvider.notifier).stop()
                      : null,
                  child: const Text('Stop'),
                ),
                OutlinedButton(
                  onPressed: state.reportPath == null
                      ? null
                      : () => _copyPath(
                            context,
                            state.reportPath!,
                            'Report path copied',
                          ),
                  child: const Text('Copy Report Path'),
                ),
                OutlinedButton(
                  onPressed: state.summaryPath == null
                      ? null
                      : () => _copyPath(
                            context,
                            state.summaryPath!,
                            'Summary path copied',
                          ),
                  child: const Text('Copy Summary Path'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              state.reportPath == null
                  ? 'Report: --'
                  : 'Report: ${state.reportPath}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            if (state.summaryPath != null)
              SelectableText(
                'Summary: ${state.summaryPath}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(
                state.message!,
                style: TextStyle(
                  color: state.status == StressRunStatus.error ||
                          state.status == StressRunStatus.failed
                      ? Colors.redAccent
                      : Colors.white70,
                ),
              ),
            ],
            if (!stockState.registered) ...[
              const SizedBox(height: 8),
              const Text(
                'Assign Stock A/B first in Bluetooth Setup before starting.',
                style: TextStyle(color: Colors.amberAccent),
              ),
            ],
            if (isMcu && !mcuState.connected) ...[
              const SizedBox(height: 4),
              Text(
                _mcuTransportMode == McuTransportMode.bridge
                    ? 'Start can auto-connect the PC bridge, but confirming the bridge first is safer.'
                    : 'Start will auto-connect the first MCU USB device, but manual connect is safer.',
                style: const TextStyle(color: Colors.amberAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, StressLabState state) {
    final plannedTotal = state.totalCycles * state.totalCasesPerCycle;
    final passRate = state.executedCases == 0
        ? 0.0
        : (state.passCount / state.executedCases) * 100.0;
    return Card(
      color: const Color(0xFF121921),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(
                  label: 'Cycles',
                  value: '${state.doneCycles}/${state.totalCycles}',
                  color: Colors.white,
                ),
                _MetricChip(
                  label: 'Cases',
                  value: '${state.executedCases}/$plannedTotal',
                  color: const Color(0xFF8ECAE6),
                ),
                _MetricChip(
                  label: 'PASS',
                  value: '${state.passCount}',
                  color: const Color(0xFF60D394),
                ),
                _MetricChip(
                  label: 'FAIL',
                  value: '${state.failCount}',
                  color: const Color(0xFFFF6B6B),
                ),
                _MetricChip(
                  label: 'Pass Rate',
                  value: '${passRate.toStringAsFixed(1)}%',
                  color: const Color(0xFFF4D35E),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 12,
                value: state.progress,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  state.failCount == 0
                      ? const Color(0xFF60D394)
                      : const Color(0xFFFF6B6B),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.activeCycle == null
                  ? 'Active: --'
                  : 'Active: Cycle ${state.activeCycle} / Case ${state.activeCaseIndex ?? 0} ${state.activeCaseLabel ?? ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              'Last: ${state.lastOutcome ?? '--'}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcuSerialControls(
    BuildContext context,
    StressLabState stressState,
    McuSerialState mcuState,
  ) {
    final serial = ref.read(mcuSerialProvider.notifier);
    final devices = mcuState.devices;
    final selectedId = mcuState.selectedDeviceId;
    final isBridge = _mcuTransportMode == McuTransportMode.bridge;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121920),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MCU Serial', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('PC Bridge'),
                selected: isBridge,
                onSelected: stressState.isRunning || mcuState.connected
                    ? null
                    : (_) {
                        setState(
                          () => _mcuTransportMode = McuTransportMode.bridge,
                        );
                        serial.setTransportMode(McuTransportMode.bridge);
                      },
              ),
              ChoiceChip(
                label: const Text('USB OTG'),
                selected: !isBridge,
                onSelected: stressState.isRunning || mcuState.connected
                    ? null
                    : (_) {
                        setState(() => _mcuTransportMode = McuTransportMode.usb);
                        serial.setTransportMode(McuTransportMode.usb);
                        serial.refreshDevices();
                      },
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
                _LabeledInput(
                  label: 'Bridge Host',
                  controller: _mcuBridgeHostController,
                  width: 180,
                  enabled: !stressState.isRunning && !mcuState.connected,
                  numericOnly: false,
                ),
                _LabeledInput(
                  label: 'Bridge Port',
                  controller: _mcuBridgePortController,
                  width: 120,
                  enabled: !stressState.isRunning && !mcuState.connected,
                ),
                FilledButton(
                  onPressed: stressState.isRunning
                      ? null
                      : () {
                          final port = int.tryParse(
                            _mcuBridgePortController.text.trim(),
                          );
                          serial.setBridgeEndpoint(
                            host: _mcuBridgeHostController.text.trim(),
                            port: port,
                          );
                          serial.connect();
                        },
                  child: const Text('Connect MCU'),
                ),
                OutlinedButton(
                  onPressed: mcuState.connected && !stressState.isRunning
                      ? () => serial.disconnect()
                      : null,
                  child: const Text('Disconnect MCU'),
                ),
                _StatusBadge(
                  label: mcuState.statusText,
                  color: mcuState.connected
                      ? const Color(0xFF2A9D8F)
                      : const Color(0xFF616161),
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
                  initialValue: selectedId != null &&
                          devices.any(
                            (device) => '${device.deviceId}' == selectedId,
                          )
                      ? selectedId
                      : null,
                  items: devices
                      .map(
                        (device) => DropdownMenuItem<String>(
                          value: '${device.deviceId}',
                          child: Text(_usbDeviceLabel(device)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: stressState.isRunning
                      ? null
                      : (value) => serial.selectDeviceId(value),
                  decoration: const InputDecoration(
                    labelText: 'USB Device',
                    filled: true,
                    fillColor: Color(0xFF11161D),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: stressState.isRunning
                    ? null
                    : () => serial.refreshDevices(),
                child: const Text('Refresh'),
              ),
              FilledButton(
                onPressed: stressState.isRunning
                    ? null
                    : () => serial.connect(),
                child: const Text('Connect MCU'),
              ),
              OutlinedButton(
                onPressed: mcuState.connected && !stressState.isRunning
                    ? () => serial.disconnect()
                    : null,
                child: const Text('Disconnect MCU'),
              ),
              _StatusBadge(
                label: mcuState.statusText,
                color: mcuState.connected
                    ? const Color(0xFF2A9D8F)
                    : const Color(0xFF616161),
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
                onPressed: _mcuBusy || stressState.isRunning
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
                onPressed: _mcuBusy || stressState.isRunning
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
          const SizedBox(height: 8),
          const Text(
            'UNO serial protocol is the same as gui_c3_state_check_dual.py MCU runner: CONFIG_UPDATED / ENDURANCE_START / CYCLE_START / CONNECT_WINDOW_BEGIN / DISCONNECT_WINDOW_BEGIN.',
            style: TextStyle(color: Colors.white70),
          ),
          if (isBridge) ...[
            const SizedBox(height: 6),
            const SelectableText(
              'PC Bridge: run scripts\\start_mcu_android_bridge.ps1 -ComPort COM4, then keep adb connected. The script sets adb reverse so the app can use 127.0.0.1:9876.',
              style: TextStyle(color: Colors.amberAccent),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'USB OTG: Android only lists the MCU when the phone is the USB host for the UNO. A phone connected to a PC for adb is in device mode, so the MCU will not appear.',
              style: TextStyle(color: Colors.amberAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMcuPowerControls(
    BuildContext context,
    StressLabState stressState,
    McuSerialState mcuState,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121920),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual MCU Power',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Use this before the endurance run to power the target and perform Bluetooth setup.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _mcuBusy || stressState.isRunning
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
                onPressed: _mcuBusy || stressState.isRunning
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
              if (_mcuBusy) const _StatusBadge(label: 'BUSY', color: Color(0xFFE9C46A)),
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
          if (!mcuState.connected) ...[
            const SizedBox(height: 8),
            const Text(
              'Connect MCU first, or the button will auto-connect using the current PC Bridge / USB OTG settings.',
              style: TextStyle(color: Colors.amberAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    StockState stockState,
    LedUiState ledUiState,
  ) {
    return Card(
      color: const Color(0xFF10161D),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _buildRecentCard(BuildContext context, StressLabState state) {
    final recent = state.records.reversed.take(12).toList(growable: false);
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Cases',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              const Text(
                'No cases yet.',
                style: TextStyle(color: Colors.white54),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recent.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12, height: 12),
                itemBuilder: (context, index) {
                  final record = recent[index];
                  final ok = record.result == 'PASS';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'C${record.cycle} #${record.caseIndex} ${record.summary}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Text(
                            record.result,
                            style: TextStyle(
                              color: ok
                                  ? const Color(0xFF60D394)
                                  : const Color(0xFFFF6B6B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${record.failureClass} / ${record.duration.inMilliseconds}ms / A=${record.batteryA?.toStringAsFixed(3) ?? '--'}V / B=${record.batteryB?.toStringAsFixed(3) ?? '--'}V',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard(BuildContext context, StressLabState state) {
    final logs = state.logs.reversed.take(40).toList(growable: false);
    return Card(
      color: const Color(0xFF0C1015),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 180),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: logs.isEmpty
                  ? const Text(
                      'Logs will appear here.',
                      style: TextStyle(color: Colors.white54),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: logs
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcuLogCard(BuildContext context, McuSerialState mcuState) {
    final logs = mcuState.logs.reversed.take(30).toList(growable: false);
    return Card(
      color: const Color(0xFF0E141A),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MCU Logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: logs.isEmpty
                  ? const Text(
                      'MCU serial logs will appear here.',
                      style: TextStyle(color: Colors.white54),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: logs
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                line,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      selected: value,
      onSelected: enabled ? onChanged : null,
      label: Text(label),
      selectedColor: const Color(0xFF184A31),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(color: enabled ? Colors.white : Colors.white54),
      side: const BorderSide(color: Colors.white12),
      backgroundColor: const Color(0xFF121920),
    );
  }

  StressSettings _previewSettings() {
    final defaults = StressSettings.defaults();
    return StressSettings(
      sweepPlan: _sweepPlan,
      runnerMode: _runnerMode,
      cycles: int.tryParse(_cyclesController.text.trim()) ?? defaults.cycles,
      settleMs:
          int.tryParse(_settleController.text.trim()) ?? defaults.settleMs,
      caseHoldMs:
          int.tryParse(_holdController.text.trim()) ?? defaults.caseHoldMs,
      caseGapMs: int.tryParse(_gapController.text.trim()) ?? defaults.caseGapMs,
      mcuOffGuardMs: int.tryParse(_mcuOffGuardController.text.trim()) ??
          defaults.mcuOffGuardMs,
      mcuPowerToD5Ms: int.tryParse(_mcuPowerToD5Controller.text.trim()) ??
          defaults.mcuPowerToD5Ms,
      mcuD5PulseMs: int.tryParse(_mcuD5PulseController.text.trim()) ??
          defaults.mcuD5PulseMs,
      mcuConnectWindowMs:
          int.tryParse(_mcuConnectWindowController.text.trim()) ??
              defaults.mcuConnectWindowMs,
      mcuDisconnectWindowMs:
          int.tryParse(_mcuDisconnectWindowController.text.trim()) ??
              defaults.mcuDisconnectWindowMs,
      scanBeforeConnect: _scanBeforeConnect,
      reconnectEachCycle: _reconnectEachCycle,
      verifyGattOnConnect: _verifyGattOnConnect,
      readBatteryEachCase: _readBatteryEachCase,
      stopOnFail: _stopOnFail,
      mcuSensorOnCheck: _mcuSensorOnCheck,
      mcuSensorOffCheck: _mcuSensorOffCheck,
      includeColor: _includeColor,
      includeHeartbeat: _includeHeartbeat,
      includeRainbow: _includeRainbow,
      includeSyncroCases: _includeSyncroCases,
    );
  }

  Future<void> _startRun(BuildContext context, {int? fixedCycles}) async {
    final cycles = fixedCycles ?? int.tryParse(_cyclesController.text.trim());
    final settle = int.tryParse(_settleController.text.trim());
    final hold = int.tryParse(_holdController.text.trim());
    final gap = int.tryParse(_gapController.text.trim());
    final mcuOffGuard = int.tryParse(_mcuOffGuardController.text.trim());
    final mcuPowerToD5 = int.tryParse(_mcuPowerToD5Controller.text.trim());
    final mcuD5Pulse = int.tryParse(_mcuD5PulseController.text.trim());
    final mcuConnectWindow =
        int.tryParse(_mcuConnectWindowController.text.trim());
    final mcuDisconnectWindow =
        int.tryParse(_mcuDisconnectWindowController.text.trim());
    final mcuBridgePort = int.tryParse(_mcuBridgePortController.text.trim());
    if (cycles == null ||
        settle == null ||
        hold == null ||
        gap == null ||
        mcuOffGuard == null ||
        mcuPowerToD5 == null ||
        mcuD5Pulse == null ||
        mcuConnectWindow == null ||
        mcuDisconnectWindow == null ||
        (_mcuTransportMode == McuTransportMode.bridge && mcuBridgePort == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid integer timing values.')),
      );
      return;
    }

    ref.read(mcuSerialProvider.notifier).setTransportMode(_mcuTransportMode);
    ref.read(mcuSerialProvider.notifier).setBridgeEndpoint(
          host: _mcuBridgeHostController.text.trim(),
          port: mcuBridgePort,
        );

    await ref.read(stressLabProvider.notifier).start(
          sweepPlan: _sweepPlan,
          runnerMode: _runnerMode,
          cycles: cycles,
          settleMs: settle,
          caseHoldMs: hold,
          caseGapMs: gap,
          mcuOffGuardMs: mcuOffGuard,
          mcuPowerToD5Ms: mcuPowerToD5,
          mcuD5PulseMs: mcuD5Pulse,
          mcuConnectWindowMs: mcuConnectWindow,
          mcuDisconnectWindowMs: mcuDisconnectWindow,
          scanBeforeConnect: _scanBeforeConnect,
          reconnectEachCycle: _reconnectEachCycle,
          verifyGattOnConnect: _verifyGattOnConnect,
          readBatteryEachCase: _readBatteryEachCase,
          stopOnFail: _stopOnFail,
          mcuSensorOnCheck: _mcuSensorOnCheck,
          mcuSensorOffCheck: _mcuSensorOffCheck,
          includeColor: _includeColor,
          includeHeartbeat: _includeHeartbeat,
          includeRainbow: _includeRainbow,
          includeSyncroCases: _includeSyncroCases,
        );
  }

  Future<void> _applyMcuConfig() async {
    final port = int.tryParse(_mcuBridgePortController.text.trim());
    ref.read(mcuSerialProvider.notifier).setTransportMode(_mcuTransportMode);
    ref.read(mcuSerialProvider.notifier).setBridgeEndpoint(
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
      await _applyMcuConfig();
      final serial = ref.read(mcuSerialProvider.notifier);
      final connected = ref.read(mcuSerialProvider).connected
          ? true
          : await serial.connect();
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

  Future<void> _copyPath(
    BuildContext context,
    String path,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.width,
    required this.enabled,
    this.numericOnly = true,
  });

  final String label;
  final TextEditingController controller;
  final double width;
  final bool enabled;
  final bool numericOnly;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType:
            numericOnly ? TextInputType.number : TextInputType.text,
        inputFormatters: numericOnly
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ]
            : null,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF11161D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.cyanAccent),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(sideState.device?.name ?? 'Not assigned'),
          const SizedBox(height: 4),
          Text(
            'Status: ${sideState.status.name}',
            style: TextStyle(color: _connectionColor(sideState.status)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Battery: ${batteryVoltage?.toStringAsFixed(3) ?? '--'} V',
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
          const SizedBox(height: 4),
          Text(
            'N:${sideState.pairNumber ?? '?'} Role:${sideState.role ?? '?'}',
            style: const TextStyle(color: Colors.white70),
          ),
          if (sideState.message != null) ...[
            const SizedBox(height: 6),
            Text(
              sideState.message!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}

Color _runStatusColor(StressRunStatus status) {
  switch (status) {
    case StressRunStatus.idle:
      return const Color(0xFF3A506B);
    case StressRunStatus.running:
      return const Color(0xFF2A9D8F);
    case StressRunStatus.stopped:
      return const Color(0xFFE9C46A);
    case StressRunStatus.done:
      return const Color(0xFF4CAF50);
    case StressRunStatus.failed:
      return const Color(0xFFE76F51);
    case StressRunStatus.error:
      return const Color(0xFFD62828);
  }
}

Color _connectionColor(DeviceConnectionState state) {
  switch (state) {
    case DeviceConnectionState.connected:
      return const Color(0xFF60D394);
    case DeviceConnectionState.connecting:
      return const Color(0xFFF4D35E);
    case DeviceConnectionState.disconnected:
      return const Color(0xFFFF6B6B);
    case DeviceConnectionState.disconnecting:
      return const Color(0xFF8ECAE6);
  }
}

String _usbDeviceLabel(UsbDevice device) {
  final name = (device.productName ?? '').trim();
  if (name.isNotEmpty) {
    return '$name (${device.deviceId})';
  }
  return 'USB ${device.deviceId}';
}
