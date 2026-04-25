import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/models.dart';
import '../ble/scan_controller.dart';
import '../ble/stock_controller.dart';
import 'sceptronic_ui.dart';

class BluetoothSettingScreen extends ConsumerStatefulWidget {
  const BluetoothSettingScreen({
    super.key,
    this.allowBackNavigation = true,
    this.showStartupGuide = false,
    this.onSetupComplete,
  });

  final bool allowBackNavigation;
  final bool showStartupGuide;
  final VoidCallback? onSetupComplete;

  @override
  ConsumerState<BluetoothSettingScreen> createState() =>
      _BluetoothSettingScreenState();
}

class _BluetoothSettingScreenState
    extends ConsumerState<BluetoothSettingScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(stockProvider.notifier).ensureLoaded();
      if (!mounted) {
        return;
      }
      await ref.read(scanProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    ref.read(scanProvider.notifier).stop();
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
    final wide = MediaQuery.of(context).size.width >= 940;
    final canCompleteSetup =
        widget.onSetupComplete != null && stockState.registered;

    return Scaffold(
      backgroundColor: SceptronicPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leadingWidth: widget.allowBackNavigation ? 44 : 0,
        leading: widget.allowBackNavigation
            ? IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        titleSpacing: widget.allowBackNavigation ? 4 : 18,
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
              child: Text(
                'BLUETOOTH SETTING',
                overflow: TextOverflow.ellipsis,
                style: sceptronicDisplayStyle(
                  context,
                  size: 17,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Information',
            onPressed: () => _showInformationSheet(stockState),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          if (widget.onSetupComplete != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: canCompleteSetup ? widget.onSetupComplete : null,
                child: const Text('CONTINUE'),
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
                SceptronicPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SceptronicSectionTitle(title: 'BLUETOOTH SETTING'),
                      if (widget.showStartupGuide) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tap the info icon in the top-right corner for setup instructions.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: SceptronicPalette.muted,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _canConnectBoth(stockState)
                                ? _connectBoth
                                : null,
                            child: const Text('CONNECT BOTH'),
                          ),
                          OutlinedButton(
                            onPressed: _canDisconnectBoth(stockState)
                                ? () => ref
                                    .read(stockProvider.notifier)
                                    .disconnectBoth()
                                : null,
                            child: const Text('DISCONNECT BOTH'),
                          ),
                          SizedBox(
                            width: wide ? 260 : double.infinity,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Auto reconnect'),
                              value: stockState.autoReconnect,
                              onChanged: (value) {
                                ref
                                    .read(stockProvider.notifier)
                                    .setAutoReconnect(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (stockState.hasPairMismatch ||
                    stockState.roleMismatchA ||
                    stockState.roleMismatchB ||
                    stockState.message != null) ...[
                  const SizedBox(height: 18),
                  SceptronicPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (stockState.hasPairMismatch)
                          const Text(
                            'N mismatch: A and B must use the same pair number.',
                            style: TextStyle(color: SceptronicPalette.danger),
                          ),
                        if (stockState.roleMismatchA ||
                            stockState.roleMismatchB)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Role mismatch: odd device number = A, even = B.',
                              style: TextStyle(color: SceptronicPalette.danger),
                            ),
                          ),
                        if (stockState.message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              stockState.message!,
                              style: const TextStyle(
                                color: SceptronicPalette.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildSideCard(
                              context,
                              stockState: stockState,
                              side: StockSide.a,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _buildSideCard(
                              context,
                              stockState: stockState,
                              side: StockSide.b,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildSideCard(
                            context,
                            stockState: stockState,
                            side: StockSide.a,
                          ),
                          const SizedBox(height: 18),
                          _buildSideCard(
                            context,
                            stockState: stockState,
                            side: StockSide.b,
                          ),
                        ],
                      ),
                const SizedBox(height: 18),
                SceptronicPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    'SCAN RESULTS',
                                    style: sceptronicDisplayStyle(
                                      context,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _buildScanActions(),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SCAN RESULTS',
                                  style: sceptronicDisplayStyle(
                                    context,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildScanActions(),
                              ],
                            ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap SCAN, then assign one device to STOCK A and the matching pair to STOCK B.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SceptronicPalette.muted,
                            ),
                      ),
                      const SizedBox(height: 14),
                      if (scanState.isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (scanError != null)
                        Text(
                          'Scan error: $scanError',
                          style:
                              const TextStyle(color: SceptronicPalette.danger),
                        )
                      else if (devices.isEmpty)
                        const SizedBox(height: 12)
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: devices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final device = devices[index];
                            final info = DeviceNameInfo.fromName(device.name);
                            final canAssignA =
                                info.role == null || info.role == 'A';
                            final canAssignB =
                                info.role == null || info.role == 'B';
                            final assignedToA =
                                stockState.a.device?.id == device.id;
                            final assignedToB =
                                stockState.b.device?.id == device.id;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name ?? 'Unknown',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${device.id}${device.rssi != null ? '  RSSI ${device.rssi}' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: SceptronicPalette.muted,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      assignedToA
                                          ? const Chip(label: Text('SET A'))
                                          : TextButton(
                                              onPressed: canAssignA
                                                  ? () => ref
                                                      .read(
                                                        stockProvider.notifier,
                                                      )
                                                      .selectDevice(
                                                        StockSide.a,
                                                        device,
                                                      )
                                                  : null,
                                              child: const Text('SET A'),
                                            ),
                                      assignedToB
                                          ? const Chip(label: Text('SET B'))
                                          : TextButton(
                                              onPressed: canAssignB
                                                  ? () => ref
                                                      .read(
                                                        stockProvider.notifier,
                                                      )
                                                      .selectDevice(
                                                        StockSide.b,
                                                        device,
                                                      )
                                                  : null,
                                              child: const Text('SET B'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInformationSheet(StockState stockState) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: SingleChildScrollView(
              child: _buildInformationPanel(
                context,
                stockState: stockState,
                highlightStartup: widget.showStartupGuide,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => ref.read(scanProvider.notifier).start(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('SCAN'),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.read(scanProvider.notifier).stop(),
          icon: const Icon(Icons.stop_rounded),
          label: const Text('STOP'),
        ),
      ],
    );
  }

  Widget _buildInformationPanel(
    BuildContext context, {
    required StockState stockState,
    required bool highlightStartup,
  }) {
    final subtitle = highlightStartup
        ? 'No registered devices were found. Complete this one-time setup before using the main screen.'
        : 'Follow these steps when assigning STOCK A and STOCK B after a scan.';

    return SceptronicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SceptronicSectionTitle(
            title: highlightStartup ? 'FIRST SETUP' : 'INFORMATION',
            subtitle: subtitle,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildInfoStepCard(
                context,
                icon: Icons.radar_rounded,
                title: '1. Scan',
                detail: 'Press SCAN to refresh nearby BLE devices.',
              ),
              _buildInfoStepCard(
                context,
                icon: Icons.looks_one_rounded,
                title: '2. Set A',
                detail: 'Choose the odd-number device and tap SET A.',
              ),
              _buildInfoStepCard(
                context,
                icon: Icons.looks_two_rounded,
                title: '3. Set B',
                detail: 'Choose the matching even-number device and tap SET B.',
              ),
              _buildInfoStepCard(
                context,
                icon: Icons.link_rounded,
                title: '4. Connect',
                detail: stockState.registered
                    ? 'Both devices are stored. You can connect now.'
                    : 'When both cards show SET, connect the pair.',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Pair rule: odd number = A, even number = B, and both must share the same pair number.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SceptronicPalette.muted,
                ),
          ),
          if (highlightStartup && widget.onSetupComplete != null) ...[
            const SizedBox(height: 10),
            Text(
              stockState.registered
                  ? 'Registration is complete. Tap CONTINUE in the top-right corner.'
                  : 'Register both devices to enable CONTINUE.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: stockState.registered
                        ? SceptronicPalette.success
                        : SceptronicPalette.warning,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoStepCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final maxCardWidth =
        MediaQuery.of(context).size.width > 320 ? 260.0 : double.infinity;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxCardWidth),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: SceptronicPalette.panelAlt,
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: SceptronicPalette.primary, size: 20),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SceptronicPalette.muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideCard(
    BuildContext context, {
    required StockState stockState,
    required StockSide side,
  }) {
    final sideState = side == StockSide.a ? stockState.a : stockState.b;
    final isConnected = sideState.status == DeviceConnectionState.connected;
    final roleLabel = side == StockSide.a ? 'A' : 'B';
    final statusColor = switch (sideState.status) {
      DeviceConnectionState.connected => SceptronicPalette.success,
      DeviceConnectionState.connecting => SceptronicPalette.primary,
      DeviceConnectionState.disconnecting => SceptronicPalette.warning,
      DeviceConnectionState.disconnected => SceptronicPalette.danger,
    };

    return SceptronicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'STOCK $roleLabel',
                style: sceptronicDisplayStyle(context, size: 20),
              ),
              const Spacer(),
              SceptronicStatusPill(
                label: sideState.status.name.toUpperCase(),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            sideState.device?.name ?? 'Not assigned',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          if (sideState.device?.id != null)
            Text(
              sideState.device!.id,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SceptronicPalette.muted,
                  ),
            ),
          if (sideState.message != null) ...[
            const SizedBox(height: 10),
            Text(
              sideState.message!,
              style: const TextStyle(color: SceptronicPalette.danger),
            ),
          ],
          if (sideState.device != null) ...[
            const SizedBox(height: 10),
            const SceptronicStatusPill(
              label: 'SET',
              color: SceptronicPalette.primary,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: sideState.device != null && !isConnected
                    ? () => _connectSide(side)
                    : null,
                child: const Text('CONNECT'),
              ),
              OutlinedButton(
                onPressed: isConnected
                    ? () => ref.read(stockProvider.notifier).disconnect(side)
                    : null,
                child: const Text('DISCONNECT'),
              ),
              TextButton(
                onPressed: sideState.device != null
                    ? () => ref.read(stockProvider.notifier).clearDevice(side)
                    : null,
                child: const Text('CLEAR'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canConnectBoth(StockState state) {
    return state.a.device != null &&
        state.b.device != null &&
        !state.hasPairMismatch &&
        !state.roleMismatchA &&
        !state.roleMismatchB &&
        (state.a.status != DeviceConnectionState.connected ||
            state.b.status != DeviceConnectionState.connected);
  }

  bool _canDisconnectBoth(StockState state) {
    return state.a.status == DeviceConnectionState.connected ||
        state.b.status == DeviceConnectionState.connected;
  }
}
