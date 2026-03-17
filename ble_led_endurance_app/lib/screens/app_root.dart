import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' hide Logger;

import '../ble/stock_controller.dart';
import 'splash_screen.dart';
import 'stress_lab_screen.dart';

enum AppStage { splash, stress }

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> with WidgetsBindingObserver {
  AppStage _stage = AppStage.splash;
  Future<void>? _resumeReconnect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleSplashComplete() {
    if (!mounted) {
      return;
    }
    setState(() => _stage = AppStage.stress);
    Future<void>.microtask(() async {
      final controller = ref.read(stockProvider.notifier);
      await controller.ensureLoaded();
      if (!mounted) {
        return;
      }
      try {
        await controller.autoConnectStored(timeout: const Duration(seconds: 4));
      } catch (_) {
        // Keep UI alive even if BLE stack throws during startup.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _stage != AppStage.stress) {
      return;
    }
    _resumeReconnect ??= _restoreConnections().whenComplete(() {
      _resumeReconnect = null;
    });
  }

  Future<void> _restoreConnections() async {
    final controller = ref.read(stockProvider.notifier);
    await controller.ensureLoaded();
    if (!mounted) {
      return;
    }
    final stock = ref.read(stockProvider);
    if (!stock.registered) {
      return;
    }
    final needsReconnect =
        stock.a.status != DeviceConnectionState.connected ||
        stock.b.status != DeviceConnectionState.connected;
    if (needsReconnect) {
      try {
        final ok = await controller.autoConnectStored(
          timeout: const Duration(seconds: 4),
        );
        if (!ok) {
          await controller.disconnectBoth();
        }
      } catch (_) {
        await controller.disconnectBoth();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 1.1, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: _buildStage(),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case AppStage.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onFinished: _handleSplashComplete,
        );
      case AppStage.stress:
        return const StressLabScreen(key: ValueKey('stress_lab'));
    }
  }
}
