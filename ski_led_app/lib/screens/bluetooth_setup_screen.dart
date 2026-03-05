import 'package:app_settings/app_settings.dart';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/stock_controller.dart';

class BluetoothSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onRegistered;
  const BluetoothSetupScreen({super.key, required this.onRegistered});

  @override
  ConsumerState<BluetoothSetupScreen> createState() =>
      _BluetoothSetupScreenState();
}

class _BluetoothSetupScreenState extends ConsumerState<BluetoothSetupScreen> {
  Future<void> _openBluetoothSettings({required bool anyConnected}) async {
    if (anyConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Disconnect A/B before opening Bluetooth settings.'),
          ),
        );
      }
      return;
    }
    ref.read(stockProvider.notifier).markSettingsRoundTripPending();
    const tag = '[BLE_UI] action=open_bt_settings';
    debugPrint(tag);
    // ignore: avoid_print
    print(tag);
    dev.log(tag, name: 'SKI_BLE');
    await AppSettings.openAppSettings(type: AppSettingsType.bluetooth);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stockProvider);
    final canConnect = state.a.device != null &&
        state.b.device != null &&
        !state.hasPairMismatch &&
        !state.roleMismatchA &&
        !state.roleMismatchB;
    final bothConnected =
        state.a.status == DeviceConnectionState.connected &&
            state.b.status == DeviceConnectionState.connected;
    final anyConnected = state.a.status == DeviceConnectionState.connected ||
        state.b.status == DeviceConnectionState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Bluetooth Setting',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Connection Status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Stock1: ${_statusLabel(state.a.status)}    Stock2: ${_statusLabel(state.b.status)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: state.connecting
                        ? null
                        : () => ref.read(stockProvider.notifier).scanAndConnect(),
                    child: Text(state.connecting ? 'Scanning...' : 'Connect'),
                  ),
                  OutlinedButton(
                    onPressed: anyConnected
                        ? () => ref.read(stockProvider.notifier).disconnectBoth()
                        : null,
                    child: const Text('Disconnected'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        _openBluetoothSettings(anyConnected: anyConnected),
                    child: const Text('Open Bluetooth'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: bothConnected
                      ? () async {
                          await ref.read(stockProvider.notifier).registerDevices();
                          if (!mounted) return;
                          widget.onRegistered();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF2B2B2B),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('LED STOCK CONNECTION'),
                ),
              ),
              if (!canConnect &&
                  (state.a.device != null || state.b.device != null))
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'A/B must be same N (A=2N-1, B=2N).',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.message!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              if (state.a.device != null || state.b.device != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'A: ${state.a.device?.name ?? '-'}   B: ${state.b.device?.name ?? '-'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              const Spacer(),
              Center(
                child: Text(
                  'XIAO-MG24-LED-STOCK connection',
                  style: TextStyle(
                    color: bothConnected ? Colors.white70 : Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(DeviceConnectionState status) {
    switch (status) {
      case DeviceConnectionState.connected:
        return 'connected';
      case DeviceConnectionState.connecting:
        return 'connecting';
      case DeviceConnectionState.disconnecting:
        return 'disconnecting';
      case DeviceConnectionState.disconnected:
        return 'disconnected';
    }
  }
}
