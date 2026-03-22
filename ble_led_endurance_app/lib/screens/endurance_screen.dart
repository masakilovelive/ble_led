import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/endurance_controller.dart';
import '../ble/led_ui_state.dart';
import '../ble/models.dart';
import '../ble/stock_controller.dart';

class EnduranceScreen extends ConsumerStatefulWidget {
  const EnduranceScreen({super.key});

  @override
  ConsumerState<EnduranceScreen> createState() => _EnduranceScreenState();
}

class _EnduranceScreenState extends ConsumerState<EnduranceScreen> {
  late final TextEditingController _cyclesController;
  late final TextEditingController _connectWaitController;
  late final TextEditingController _disconnectWaitController;
  bool _scanBeforeConnect = true;
  bool _runStartupWave = true;
  bool _runGattCheck = true;
  bool _stopOnFail = false;

  @override
  void initState() {
    super.initState();
    final defaults = EnduranceSettings.defaults();
    _cyclesController = TextEditingController(text: '${defaults.cycles}');
    _connectWaitController = TextEditingController(
      text: defaults.connectWaitSeconds.toStringAsFixed(1),
    );
    _disconnectWaitController = TextEditingController(
      text: defaults.disconnectWaitSeconds.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _cyclesController.dispose();
    _connectWaitController.dispose();
    _disconnectWaitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enduranceState = ref.watch(enduranceProvider);
    final stockState = ref.watch(stockProvider);
    final ledUiState = ref.watch(ledUiProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSettingsCard(context, enduranceState, stockState),
            const SizedBox(height: 14),
            _buildSummaryCard(context, enduranceState),
            const SizedBox(height: 14),
            _buildDeviceStatusCard(context, stockState, ledUiState),
            const SizedBox(height: 14),
            _buildFailureCard(context, enduranceState),
            const SizedBox(height: 14),
            _buildRecentCyclesCard(context, enduranceState),
            const SizedBox(height: 14),
            _buildLogsCard(context, enduranceState),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    EnduranceState enduranceState,
    StockState stockState,
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
                  'ENDURANCE',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                ),
                const Spacer(),
                _StatusBadge(
                  label: enduranceState.statusText,
                  color: _runStatusColor(enduranceState.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Repeats Scan -> Connect -> LED/GATT -> Disconnect to verify A/B stability.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _LabeledInput(
                  label: 'Cycles',
                  controller: _cyclesController,
                  width: 110,
                  enabled: !enduranceState.isRunning,
                ),
                _LabeledInput(
                  label: 'Connect Wait (s)',
                  controller: _connectWaitController,
                  width: 140,
                  enabled: !enduranceState.isRunning,
                ),
                _LabeledInput(
                  label: 'Disconnect Wait (s)',
                  controller: _disconnectWaitController,
                  width: 150,
                  enabled: !enduranceState.isRunning,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _buildToggle(
                  label: 'Scan Before Connect',
                  value: _scanBeforeConnect,
                  enabled: !enduranceState.isRunning,
                  onChanged: (value) =>
                      setState(() => _scanBeforeConnect = value),
                ),
                _buildToggle(
                  label: 'Run Startup Wave',
                  value: _runStartupWave,
                  enabled: !enduranceState.isRunning,
                  onChanged: (value) =>
                      setState(() => _runStartupWave = value),
                ),
                _buildToggle(
                  label: 'Run GATT/Battery',
                  value: _runGattCheck,
                  enabled: !enduranceState.isRunning,
                  onChanged: (value) =>
                      setState(() => _runGattCheck = value),
                ),
                _buildToggle(
                  label: 'Stop on First Failure',
                  value: _stopOnFail,
                  enabled: !enduranceState.isRunning,
                  onChanged: (value) => setState(() => _stopOnFail = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: enduranceState.isRunning
                      ? null
                      : () => _startRun(context, fixedCycles: 100),
                  child: const Text('Start 100 Cycles'),
                ),
                FilledButton.tonal(
                  onPressed:
                      enduranceState.isRunning ? null : () => _startRun(context),
                  child: const Text('Start Custom'),
                ),
                OutlinedButton(
                  onPressed: enduranceState.isRunning
                      ? () => ref.read(enduranceProvider.notifier).stop()
                      : null,
                  child: const Text('Stop'),
                ),
                OutlinedButton(
                  onPressed: enduranceState.reportPath == null
                      ? null
                      : () => _copyPath(
                            context,
                            enduranceState.reportPath!,
                            'Report path copied',
                          ),
                  child: const Text('Copy Report Path'),
                ),
                OutlinedButton(
                  onPressed: enduranceState.summaryPath == null
                      ? null
                      : () => _copyPath(
                            context,
                            enduranceState.summaryPath!,
                            'Summary path copied',
                          ),
                  child: const Text('Copy Summary Path'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              enduranceState.reportPath == null
                  ? 'Report: --'
                  : 'Report: ${enduranceState.reportPath}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
            if (enduranceState.summaryPath != null)
              SelectableText(
                'Summary: ${enduranceState.summaryPath}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            if (enduranceState.message != null) ...[
              const SizedBox(height: 8),
              Text(
                enduranceState.message!,
                style: TextStyle(
                  color: enduranceState.status == EnduranceRunStatus.error ||
                          enduranceState.status == EnduranceRunStatus.failed
                      ? Colors.redAccent
                      : Colors.white70,
                ),
              ),
            ],
            if (!stockState.registered) ...[
              const SizedBox(height: 8),
              const Text(
                'Assign A/B first in Bluetooth Setup before starting.',
                style: TextStyle(color: Colors.amberAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, EnduranceState state) {
    final passRate = state.doneCycles == 0
        ? 0.0
        : (state.passCount / state.doneCycles) * 100.0;
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
                  color: const Color(0xFF8ECAE6),
                ),
                _MetricChip(
                  label: 'Last',
                  value: state.lastOutcome ?? '--',
                  color: const Color(0xFFF4D35E),
                  wide: true,
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
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard(
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
            Text('A / B Status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DeviceStatusPane(
                          side: StockSide.a,
                          sideState: stockState.a,
                          sideUi: ledUiState.a,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DeviceStatusPane(
                          side: StockSide.b,
                          sideState: stockState.b,
                          sideUi: ledUiState.b,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DeviceStatusPane(
                      side: StockSide.a,
                      sideState: stockState.a,
                      sideUi: ledUiState.a,
                    ),
                    const SizedBox(height: 12),
                    _DeviceStatusPane(
                      side: StockSide.b,
                      sideState: stockState.b,
                      sideUi: ledUiState.b,
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

  Widget _buildFailureCard(BuildContext context, EnduranceState state) {
    final failures = state.failureCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      color: const Color(0xFF121920),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Failure Breakdown',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (failures.isEmpty)
              const Text(
                'No cycle data yet.',
                style: TextStyle(color: Colors.white70),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: failures
                    .map(
                      (entry) => Container(
                        constraints: const BoxConstraints(minWidth: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.value}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCyclesCard(BuildContext context, EnduranceState state) {
    final recent = state.records.reversed.take(8).toList();
    return Card(
      color: const Color(0xFF0E141A),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Cycles', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              const Text(
                'Results will appear here after the first cycle.',
                style: TextStyle(color: Colors.white70),
              )
            else
              Column(
                children: recent
                    .map(
                      (record) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: record.result == 'PASS'
                                ? const Color(0xFF60D394)
                                : const Color(0xFFFF6B6B),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Cycle ${record.cycle}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                _StatusBadge(
                                  label: record.result,
                                  color: record.result == 'PASS'
                                      ? const Color(0xFF60D394)
                                      : const Color(0xFFFF6B6B),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Class: ${record.failureClass}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (record.failureDetail.isNotEmpty)
                              Text(
                                record.failureDetail,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'scan ${record.scanDuration.inMilliseconds}ms / '
                              'connect ${record.connectDuration.inMilliseconds}ms / '
                              'gatt ${record.gattDuration.inMilliseconds}ms / '
                              'disconnect ${record.disconnectDuration.inMilliseconds}ms',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard(BuildContext context, EnduranceState state) {
    final logs = state.logs.reversed.take(80).toList();
    return Card(
      color: const Color(0xFF0C1015),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              height: 220,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Logs will appear here.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12, height: 12),
                      itemBuilder: (context, index) => Text(
                        logs[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
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
      label: Text(label),
      selected: value,
      onSelected: enabled ? onChanged : null,
      selectedColor: const Color(0xFF1F6F78),
      checkmarkColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
    );
  }

  Future<void> _startRun(
    BuildContext context, {
    int? fixedCycles,
  }) async {
    final cycles = fixedCycles ?? int.tryParse(_cyclesController.text.trim());
    final connectWait = double.tryParse(_connectWaitController.text.trim());
    final disconnectWait =
        double.tryParse(_disconnectWaitController.text.trim());
    if (cycles == null || connectWait == null || disconnectWait == null) {
      _showSnack(context, 'Enter numeric values for cycles and wait time.');
      return;
    }

    await ref.read(enduranceProvider.notifier).start(
          cycles: cycles,
          connectWaitSeconds: connectWait,
          disconnectWaitSeconds: disconnectWait,
          scanBeforeConnect: _scanBeforeConnect,
          runStartupWave: _runStartupWave,
          runGattCheck: _runGattCheck,
          stopOnFail: _stopOnFail,
        );
  }

  Future<void> _copyPath(
    BuildContext context,
    String path,
    String message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Color _runStatusColor(EnduranceRunStatus status) {
    switch (status) {
      case EnduranceRunStatus.idle:
        return Colors.blueGrey;
      case EnduranceRunStatus.running:
        return const Color(0xFF2A9D8F);
      case EnduranceRunStatus.stopped:
        return const Color(0xFFF4A261);
      case EnduranceRunStatus.done:
        return const Color(0xFF60D394);
      case EnduranceRunStatus.failed:
        return const Color(0xFFFF6B6B);
      case EnduranceRunStatus.error:
        return const Color(0xFFE63946);
    }
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.width,
    required this.enabled,
  });

  final String label;
  final TextEditingController controller;
  final double width;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          disabledBorder: OutlineInputBorder(
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
    this.wide = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: wide ? 280 : 120),
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
            maxLines: wide ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusPane extends StatelessWidget {
  const _DeviceStatusPane({
    required this.side,
    required this.sideState,
    required this.sideUi,
  });

  final StockSide side;
  final StockSideState sideState;
  final LedUiSideState sideUi;

  @override
  Widget build(BuildContext context) {
    final batteryPercent = (sideUi.batteryPercent * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Stock ${side.name.toUpperCase()}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              _StatusBadge(
                label: sideState.status.name.toUpperCase(),
                color: _connectionColor(sideState.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(sideState.device?.name ?? 'Not assigned'),
          const SizedBox(height: 4),
          Text(
            sideState.device?.id ?? '--',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'N:${sideState.pairNumber ?? '?'} Role:${sideState.role ?? '?'}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: sideUi.batteryPercent.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF8ECAE6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$batteryPercent%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (sideUi.charging) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.bolt_rounded,
                  color: Colors.amberAccent,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Voltage: ${sideUi.batteryVoltage?.toStringAsFixed(3) ?? '--'} V',
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
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

Color _connectionColor(DeviceConnectionState state) {
  switch (state) {
    case DeviceConnectionState.connected:
      return const Color(0xFF60D394);
    case DeviceConnectionState.connecting:
      return const Color(0xFFF4A261);
    case DeviceConnectionState.disconnected:
      return Colors.blueGrey;
    case DeviceConnectionState.disconnecting:
      return const Color(0xFFE9C46A);
  }
}
