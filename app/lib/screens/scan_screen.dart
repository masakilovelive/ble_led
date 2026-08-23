import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ble/scan_controller.dart';
import 'pair_test_screen.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BLE Tools'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Scan'),
              Tab(text: 'Collision Test'),
            ],
          ),
        ),
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
        body: TabBarView(
          children: [
            state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (devices) => ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = devices[i];
                  return ListTile(
                    title: Text(d.name ?? 'Unknown'),
                    subtitle: Text(
                      d.rssi != null ? 'RSSI: ${d.rssi}' : 'RSSI: --',
                    ),
                    onTap: () => _openDetail(context, d.id, d.name),
                  );
                },
              ),
            ),
            const PairTestScreen(),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, String id, String? name) {
    context.pushNamed(
      'device',
      queryParameters: {
        'id': id,
        if (name != null) 'name': name,
      },
    );
  }
}
