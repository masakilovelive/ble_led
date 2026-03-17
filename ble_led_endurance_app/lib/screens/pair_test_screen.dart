import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/models.dart';
import '../ble/pair_test_controller.dart' hide DeviceNameInfo;
import '../ble/scan_controller.dart';

class PairTestScreen extends ConsumerWidget {
  const PairTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scanProvider);
    final pairState = ref.watch(pairTestProvider);
    final devices = scanState.maybeWhen(
      data: (d) => d,
      orElse: () => const <BleDevice>[],
    );
    final scanError = scanState.maybeWhen(
      error: (e, _) => e.toString(),
      orElse: () => null,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCard(context, ref, pairState),
          const SizedBox(height: 10),
          _buildSideCard(context, ref, pairState, PairSide.a),
          const SizedBox(height: 10),
          _buildSideCard(context, ref, pairState, PairSide.b),
          if (pairState.hasPairMismatch)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'N mismatch: A/B must use the same N.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (pairState.roleMismatchA || pairState.roleMismatchB)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Role mismatch: odd number = A, even number = B.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (pairState.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                pairState.message!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Auto reconnect when advertising'),
            value: pairState.autoReconnect,
            onChanged: (v) =>
                ref.read(pairTestProvider.notifier).setAutoReconnect(v),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: pairState.isTesting
                    ? null
                    : () =>
                        ref.read(pairTestProvider.notifier).runCollisionTest(),
                child: Text(pairState.isTesting ? 'Testing...' : 'Run Test'),
              ),
              OutlinedButton(
                onPressed: pairState.logs.isEmpty
                    ? null
                    : () => ref.read(pairTestProvider.notifier).clearLogs(),
                child: const Text('Clear Logs'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildLogView(pairState.logs),
          const Divider(height: 24),
          Text('Scan Results', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (scanError != null)
            Text('Scan error: $scanError',
                style: const TextStyle(color: Colors.red))
          else
            _buildDeviceList(ref, devices),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    WidgetRef ref,
    PairTestState pairState,
  ) {
    final theme = Theme.of(context);
    final aName = pairState.a.device?.name ?? 'Not assigned';
    final bName = pairState.b.device?.name ?? 'Not assigned';
    final canConnectBoth = pairState.a.device != null &&
        pairState.b.device != null &&
        !pairState.hasPairMismatch &&
        !pairState.roleMismatchA &&
        !pairState.roleMismatchB &&
        (pairState.a.status != DeviceConnectionState.connected ||
            pairState.b.status != DeviceConnectionState.connected);
    final canDisconnectBoth =
        pairState.a.status == DeviceConnectionState.connected ||
            pairState.b.status == DeviceConnectionState.connected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection Status', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('A ($aName): ${pairState.a.status.name}'),
            Text('B ($bName): ${pairState.b.status.name}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: canConnectBoth
                      ? () => ref.read(pairTestProvider.notifier).connectBoth()
                      : null,
                  child: const Text('Connect Both'),
                ),
                OutlinedButton(
                  onPressed: canDisconnectBoth
                      ? () =>
                          ref.read(pairTestProvider.notifier).disconnectBoth()
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
    WidgetRef ref,
    PairTestState pairState,
    PairSide side,
  ) {
    final theme = Theme.of(context);
    final sideState = side == PairSide.a ? pairState.a : pairState.b;
    final device = sideState.device;
    final isConnected = sideState.status == DeviceConnectionState.connected;
    final roleLabel = side == PairSide.a ? 'A' : 'B';
    final roleMismatch =
        side == PairSide.a ? pairState.roleMismatchA : pairState.roleMismatchB;
    final pairMismatch = pairState.hasPairMismatch &&
        pairState.a.device != null &&
        pairState.b.device != null;
    final canConnect = device != null && !roleMismatch && !pairMismatch;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device $roleLabel', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(device?.name ?? 'Not assigned'),
            if (device != null) ...[
              Text(device.id, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                'N: ${sideState.pairNumber ?? '?'}  Role: ${sideState.role ?? '?'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text('Status: ${sideState.status.name}'),
            if (sideState.message != null)
              Text(
                sideState.message!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: canConnect && !isConnected
                      ? () => ref.read(pairTestProvider.notifier).connect(side)
                      : null,
                  child: const Text('Connect'),
                ),
                OutlinedButton(
                  onPressed: isConnected
                      ? () =>
                          ref.read(pairTestProvider.notifier).disconnect(side)
                      : null,
                  child: const Text('Disconnect'),
                ),
                TextButton(
                  onPressed: device != null
                      ? () =>
                          ref.read(pairTestProvider.notifier).clearDevice(side)
                      : null,
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogView(List<String> logs) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: logs.isEmpty
          ? const Center(child: Text('Logs will appear here'))
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, i) => Text(logs[i]),
            ),
    );
  }

  Widget _buildDeviceList(
    WidgetRef ref,
    List<BleDevice> devices,
  ) {
    if (devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No devices yet. Tap play to scan.'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = devices[i];
        final info = DeviceNameInfo.fromName(d.name);
        final canAssignA = info.role == null || info.role == 'A';
        final canAssignB = info.role == null || info.role == 'B';
        return ListTile(
          title: Text(d.name ?? 'Unknown'),
          subtitle: Text(
            '${d.id}  N:${info.pairNumber ?? '?'}  Role:${info.role ?? '?'}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: canAssignA
                    ? () => ref
                        .read(pairTestProvider.notifier)
                        .selectDevice(PairSide.a, d)
                    : null,
                child: const Text('Set A'),
              ),
              TextButton(
                onPressed: canAssignB
                    ? () => ref
                        .read(pairTestProvider.notifier)
                        .selectDevice(PairSide.b, d)
                    : null,
                child: const Text('Set B'),
              ),
            ],
          ),
        );
      },
    );
  }
}
