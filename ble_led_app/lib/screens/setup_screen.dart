import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/models.dart';
import '../ble/scan_controller.dart';
import '../ble/stock_controller.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(stockProvider.notifier).ensureLoaded();
      await ref.read(scanProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    ref.read(scanProvider.notifier).stop();
    super.dispose();
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
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(device.name ?? 'Unknown'),
                      subtitle: Text(
                        '${device.id}${device.rssi != null ? '  RSSI ${device.rssi}' : ''}\nN:${info.pairNumber ?? '?'} Role:${info.role ?? '?'}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 8,
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
                  onPressed: canConnectBoth
                      ? () => ref.read(stockProvider.notifier).connectBoth()
                      : null,
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
                      ? () => ref.read(stockProvider.notifier).connect(side)
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
