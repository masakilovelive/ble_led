import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:usb_serial/usb_serial.dart';

import '../ble/mcu_serial_controller.dart';
import '../ble/models.dart';
import '../ble/scan_controller.dart';
import '../ble/stock_controller.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final TextEditingController _mcuBridgeHostController;
  late final TextEditingController _mcuBridgePortController;
  McuTransportMode _mcuTransportMode = McuTransportMode.bridge;
  bool _mcuBusy = false;
  String? _mcuActionMessage;

  @override
  void initState() {
    super.initState();
    final mcuDefaults = McuSerialState.initial();
    _mcuBridgeHostController = TextEditingController(
      text: mcuDefaults.bridgeHost,
    );
    _mcuBridgePortController = TextEditingController(
      text: '${mcuDefaults.bridgePort}',
    );
    _mcuTransportMode = mcuDefaults.transportMode;
    final stock = ref.read(stockProvider.notifier);
    final scan = ref.read(scanProvider.notifier);
    final mcuSerial = ref.read(mcuSerialProvider.notifier);
    Future<void>.microtask(() async {
      if (!mounted) {
        return;
      }
      await stock.ensureLoaded();
      if (!mounted) {
        return;
      }
      await scan.start();
      if (!mounted) {
        return;
      }
      await mcuSerial.refreshDevices();
    });
  }

  @override
  void dispose() {
    ref.read(scanProvider.notifier).stop();
    _mcuBridgeHostController.dispose();
    _mcuBridgePortController.dispose();
    super.dispose();
  }

  Future<void> _connectBoth() async {
    await ref.read(scanProvider.notifier).stop();
    if (!mounted) {
      return;
    }
    await ref.read(stockProvider.notifier).connectBoth();
  }

  Future<void> _connectSide(StockSide side) async {
    await ref.read(scanProvider.notifier).stop();
    if (!mounted) {
      return;
    }
    await ref.read(stockProvider.notifier).connect(side);
  }

  @override
  Widget build(BuildContext context) {
    final stockState = ref.watch(stockProvider);
    final scanState = ref.watch(scanProvider);
    final devices = scanState.maybeWhen(
      data: (value) => value,
      orElse: () => const <BleDevice>[],
    );
    final scanError = scanState.maybeWhen(
      error: (error, stackTrace) => error.toString(),
      orElse: () => null,
    );
    final mcuState = ref.watch(mcuSerialProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Bluetooth Setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryCard(context, stockState),
              const SizedBox(height: 12),
              _buildMcuAssistCard(context, mcuState),
              const SizedBox(height: 12),
              _buildSideCard(context, stockState, StockSide.a),
              const SizedBox(height: 12),
              _buildSideCard(context, stockState, StockSide.b),
              if (stockState.hasPairMismatch)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'N mismatch: A/B must use the same N.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (stockState.roleMismatchA || stockState.roleMismatchB)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Role mismatch: odd device number = A, even = B.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (stockState.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    stockState.message!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto reconnect'),
                subtitle:
                    const Text('Retry A/B automatically when the link drops'),
                value: stockState.autoReconnect,
                onChanged: (value) {
                  ref.read(stockProvider.notifier).setAutoReconnect(value);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => ref.read(scanProvider.notifier).start(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Scan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(scanProvider.notifier).stop(),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Scan Results',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (scanState.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (scanError != null)
                Text(
                  'Scan error: $scanError',
                  style: const TextStyle(color: Colors.redAccent),
                )
              else if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No devices yet. Start a scan to assign A/B.'),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final info = DeviceNameInfo.fromName(device.name);
                    final canAssignA = info.role == null || info.role == 'A';
                    final canAssignB = info.role == null || info.role == 'B';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name ?? 'Unknown',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${device.id}${device.rssi != null ? '  RSSI ${device.rssi}' : ''}\nN:${info.pairNumber ?? '?'} Role:${info.role ?? '?'}',
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: canAssignA
                                    ? () => ref
                                        .read(stockProvider.notifier)
                                        .selectDevice(StockSide.a, device)
                                    : null,
                                child: const Text('Set A'),
                              ),
                              TextButton(
                                onPressed: canAssignB
                                    ? () => ref
                                        .read(stockProvider.notifier)
                                        .selectDevice(StockSide.b, device)
                                    : null,
                                child: const Text('Set B'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, StockState state) {
    final canConnectBoth = state.a.device != null &&
        state.b.device != null &&
        !state.hasPairMismatch &&
        !state.roleMismatchA &&
        !state.roleMismatchB &&
        (state.a.status != DeviceConnectionState.connected ||
            state.b.status != DeviceConnectionState.connected);
    final canDisconnectBoth =
        state.a.status == DeviceConnectionState.connected ||
            state.b.status == DeviceConnectionState.connected;

    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection Status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('A: ${state.a.status.name}'),
            Text('B: ${state.b.status.name}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: canConnectBoth ? _connectBoth : null,
                  child: const Text('Connect Both'),
                ),
                OutlinedButton(
                  onPressed: canDisconnectBoth
                      ? () => ref.read(stockProvider.notifier).disconnectBoth()
                      : null,
                  child: const Text('Disconnect Both'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMcuAssistCard(BuildContext context, McuSerialState mcuState) {
    final serial = ref.read(mcuSerialProvider.notifier);
    final devices = mcuState.devices;
    final selectedId = mcuState.selectedDeviceId;
    final isBridge = _mcuTransportMode == McuTransportMode.bridge;
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCU Power Assist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Use this before endurance to power the target and set up Bluetooth connections.',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('PC Bridge'),
                  selected: isBridge,
                  onSelected: _mcuBusy || mcuState.connected
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
                  onSelected: _mcuBusy || mcuState.connected
                      ? null
                      : (_) {
                          setState(
                              () => _mcuTransportMode = McuTransportMode.usb);
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
                  _SetupInput(
                    label: 'Bridge Host',
                    controller: _mcuBridgeHostController,
                    width: 170,
                    enabled: !_mcuBusy && !mcuState.connected,
                    numericOnly: false,
                  ),
                  _SetupInput(
                    label: 'Bridge Port',
                    controller: _mcuBridgePortController,
                    width: 120,
                    enabled: !_mcuBusy && !mcuState.connected,
                  ),
                  FilledButton(
                    onPressed: _mcuBusy
                        ? null
                        : () => _connectMcu(serial, refreshUsb: false),
                    child: const Text('Connect MCU'),
                  ),
                  OutlinedButton(
                    onPressed: !_mcuBusy && mcuState.connected
                        ? () => serial.disconnect()
                        : null,
                    child: const Text('Disconnect MCU'),
                  ),
                  Chip(label: Text(mcuState.statusText)),
                ],
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
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
                      onChanged: _mcuBusy
                          ? null
                          : (value) => serial.selectDeviceId(value),
                      decoration: const InputDecoration(
                        labelText: 'USB Device',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _mcuBusy ? null : () => serial.refreshDevices(),
                    child: const Text('Refresh'),
                  ),
                  FilledButton(
                    onPressed: _mcuBusy
                        ? null
                        : () => _connectMcu(serial, refreshUsb: true),
                    child: const Text('Connect MCU'),
                  ),
                  OutlinedButton(
                    onPressed: !_mcuBusy && mcuState.connected
                        ? () => serial.disconnect()
                        : null,
                    child: const Text('Disconnect MCU'),
                  ),
                  Chip(label: Text(mcuState.statusText)),
                ],
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _mcuBusy
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
                  onPressed: _mcuBusy
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
                      : Colors.white,
                ),
              ),
            ],
            if (mcuState.message != null) ...[
              const SizedBox(height: 6),
              Text(
                mcuState.message!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              isBridge
                  ? 'PC Bridge: run scripts\\start_mcu_android_bridge.ps1 -ComPort COM4, then use Connect MCU.'
                  : 'USB OTG: connect the phone directly to the UNO.',
              style: const TextStyle(color: Colors.amberAccent),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectMcu(
    McuSerialController serial, {
    required bool refreshUsb,
  }) async {
    await _applyMcuConfig(serial);
    if (refreshUsb) {
      await serial.refreshDevices();
    }
    await serial.connect();
  }

  Future<void> _applyMcuConfig(McuSerialController serial) async {
    final bridgePort = int.tryParse(_mcuBridgePortController.text.trim());
    serial.setTransportMode(_mcuTransportMode);
    serial.setBridgeEndpoint(
      host: _mcuBridgeHostController.text.trim(),
      port: bridgePort,
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
      final serial = ref.read(mcuSerialProvider.notifier);
      await _applyMcuConfig(serial);
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

  Widget _buildSideCard(
    BuildContext context,
    StockState state,
    StockSide side,
  ) {
    final sideState = side == StockSide.a ? state.a : state.b;
    final roleLabel = side == StockSide.a ? 'A' : 'B';
    final isConnected = sideState.status == DeviceConnectionState.connected;

    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device $roleLabel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(sideState.device?.name ?? 'Not assigned'),
            if (sideState.device != null) ...[
              Text(
                sideState.device!.id,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'N:${sideState.pairNumber ?? '?'} Role:${sideState.role ?? '?'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text('Status: ${sideState.status.name}'),
            if (sideState.message != null)
              Text(
                sideState.message!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: sideState.device != null && !isConnected
                      ? () => _connectSide(side)
                      : null,
                  child: const Text('Connect'),
                ),
                OutlinedButton(
                  onPressed: isConnected
                      ? () => ref.read(stockProvider.notifier).disconnect(side)
                      : null,
                  child: const Text('Disconnect'),
                ),
                TextButton(
                  onPressed: sideState.device != null
                      ? () => ref.read(stockProvider.notifier).clearDevice(side)
                      : null,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupInput extends StatelessWidget {
  const _SetupInput({
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
        keyboardType: numericOnly ? TextInputType.number : TextInputType.text,
        inputFormatters: numericOnly
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ]
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

String _usbDeviceLabel(UsbDevice device) {
  final name = (device.productName ?? '').trim();
  if (name.isNotEmpty) {
    return '$name (${device.deviceId})';
  }
  return 'USB ${device.deviceId}';
}
