
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../ble/connection_controller.dart';
import '../ble/led_controller.dart';
import '../ble/voltage_controller.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;
  final String? deviceName;
  const DeviceDetailScreen({super.key, required this.deviceId, this.deviceName});

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  VoltageSample? _latestVoltage;
  StreamSubscription<VoltageSample>? _voltageSub;
  bool _voltageStreaming = false;
  String? _voltageError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(connectionProvider.notifier).connect(widget.deviceId));
  }

  @override
  void dispose() {
    _voltageSub?.cancel();
    ref.read(connectionProvider.notifier).disconnect();
    super.dispose();
  }

  Future<void> _readVoltage() async {
    final controller = ref.read(voltageControllerProvider);
    try {
      final sample = await controller.readSample(widget.deviceId);
      if (!mounted) return;
      setState(() {
        _latestVoltage = sample;
        _voltageError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voltageError = e.toString();
      });
    }
  }

  Future<void> _setVoltageStreaming(bool enable) async {
    if (enable == _voltageStreaming && enable == (_voltageSub != null)) {
      return;
    }
    await _voltageSub?.cancel();
    _voltageSub = null;

    if (!enable) {
      if (!mounted) return;
      setState(() {
        _voltageStreaming = false;
      });
      return;
    }

    final controller = ref.read(voltageControllerProvider);
    try {
      StreamSubscription<VoltageSample>? sub;
      sub = controller.monitor(widget.deviceId).listen(
        (sample) {
          if (!mounted) return;
          setState(() {
            _latestVoltage = sample;
            _voltageError = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          sub?.cancel();
          if (!mounted) return;
          setState(() {
            _voltageError = error.toString();
            _voltageStreaming = false;
            _voltageSub = null;
          });
        },
      );
      if (!mounted) {
        await sub.cancel();
        return;
      }
      setState(() {
        _voltageSub = sub;
        _voltageStreaming = true;
        _voltageError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voltageStreaming = false;
        _voltageSub = null;
        _voltageError = e.toString();
      });
    }
  }

  String _formatVoltage(VoltageSample sample) {
    final volts = (sample.millivolts / 1000.0).toStringAsFixed(3);
    final ts = sample.timestamp.toLocal();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    return "$volts V (raw ${sample.raw}) @ $hh:$mm:$ss";
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(connectionProvider);
    final led = ref.watch(ledControllerProvider);
    final isConnected = st.status == DeviceConnectionState.connected;
    if (!isConnected && _voltageStreaming) {
      Future.microtask(() => _setVoltageStreaming(false));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceName ?? widget.deviceId)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Status: '),
              Text(st.status.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton(
                onPressed: isConnected
                    ? null
                    : () => ref.read(connectionProvider.notifier).connect(widget.deviceId),
                child: const Text('Connect'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: isConnected
                    ? () => ref.read(connectionProvider.notifier).disconnect()
                    : null,
                child: const Text('Disconnect'),
              ),
            ]),
            const SizedBox(height: 24),
            const Text('LED control (0x2A06):'),
            const SizedBox(height: 8),
            Wrap(spacing: 12, children: [
              FilledButton(
                onPressed: isConnected ? () => led.writeLevel(widget.deviceId, 0x00) : null,
                child: const Text('OFF'),
              ),
              FilledButton(
                onPressed: isConnected ? () => led.writeLevel(widget.deviceId, 0x01) : null,
                child: const Text('Mild'),
              ),
              FilledButton(
                onPressed: isConnected ? () => led.writeLevel(widget.deviceId, 0x02) : null,
                child: const Text('High'),
              ),
            ]),
            const SizedBox(height: 24),
            const Text('D3 voltage (custom service):'),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(
                onPressed: isConnected ? _readVoltage : null,
                child: const Text('Read once'),
              ),
              const SizedBox(width: 16),
              Row(children: [
                Switch(
                  value: _voltageStreaming,
                  onChanged: isConnected ? (v) => _setVoltageStreaming(v) : null,
                ),
                const Text('Live monitor'),
              ]),
            ]),
            const SizedBox(height: 8),
            if (_latestVoltage != null)
              Text(_formatVoltage(_latestVoltage!)),
            if (_voltageError != null)
              Text(_voltageError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            const Text('Discovered GATT:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: st.services.length,
                itemBuilder: (context, i) {
                  final s = st.services[i];
                  return ExpansionTile(
                    title: Text(s.uuid),
                    children: s.characteristics.map((c) => ListTile(
                      dense: true,
                      title: Text(c.uuid),
                      subtitle: Text([
                        if (c.canRead) "R",
                        if (c.canWrite) "W",
                        if (c.canNotify) "N",
                        if (c.canIndicate) "I",
                      ].join(" ")),
                    )).toList(),
                  );
                },
              ),
            ),
            if (st.message != null) Text(st.message!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
