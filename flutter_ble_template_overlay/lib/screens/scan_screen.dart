
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble/scan_controller.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan BLE Devices')),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'start',
            onPressed: () => ref.read(scanProvider.notifier).start(),
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'stop',
            onPressed: () => ref.read(scanProvider.notifier).stop(),
            child: const Icon(Icons.stop),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (devices) => ListView.separated(
          itemCount: devices.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = devices[i];
            return ListTile(
              title: Text(d.name ?? 'Unknown'),
              subtitle: Text('${d.id}${d.rssi != null ? '  RSSI: ${d.rssi}' : ''}'),
              onTap: () => _openDetail(context, d.id, d.name),
            );
          },
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, String id, String? name) {
    final q = Uri(queryParameters: {'id': id, 'name': name}).query;
    Navigator.of(context).pushNamed('/device?$q');
  }
}
