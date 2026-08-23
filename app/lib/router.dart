import 'package:go_router/go_router.dart';
import 'screens/scan_screen.dart';
import 'screens/device_detail_screen.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ScanScreen(),
      routes: [
        GoRoute(
          path: 'device',
          name: 'device',
          builder: (context, state) {
            final id = state.uri.queryParameters['id']!;
            final name = state.uri.queryParameters['name'];
            return DeviceDetailScreen(deviceId: id, deviceName: name);
          },
        )
      ],
    ),
  ],
);
