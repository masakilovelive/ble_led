import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/stock_controller.dart';
import 'auto_connect_screen.dart';
import 'bluetooth_setup_screen.dart';
import 'splash_screen.dart';
import 'stock_select_screen.dart';

enum AppStage { splash, autoConnect, bluetoothSetup, stockSelect }

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> with WidgetsBindingObserver {
  AppStage _stage = AppStage.splash;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(stockProvider.notifier).handleAppResumed());
    }
  }

  void _handleSplashComplete() async {
    final controller = ref.read(stockProvider.notifier);
    await controller.ensureLoaded();
    if (!mounted) return;
    if (ref.read(stockProvider).registered) {
      setState(() => _stage = AppStage.autoConnect);
      final success = await controller.autoConnectStored();
      if (!mounted) return;
      setState(
        () => _stage = success ? AppStage.stockSelect : AppStage.bluetoothSetup,
      );
    } else {
      setState(() => _stage = AppStage.bluetoothSetup);
    }
  }

  void _goToStockSelect() {
    setState(() => _stage = AppStage.stockSelect);
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
      child: _buildStage(context),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case AppStage.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onFinished: _handleSplashComplete,
        );
      case AppStage.autoConnect:
        return const AutoConnectScreen(key: ValueKey('auto_connect'));
      case AppStage.bluetoothSetup:
        return BluetoothSetupScreen(
          key: const ValueKey('bluetooth_setup'),
          onRegistered: _goToStockSelect,
        );
      case AppStage.stockSelect:
        return const StockSelectScreen(key: ValueKey('stock_select'));
    }
  }
}
