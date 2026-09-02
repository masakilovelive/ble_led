import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/product_ui_state.dart';
import '../ble/stock_controller.dart';
import 'bluetooth_setting_screen.dart';
import 'splash_screen.dart';
import 'stock_select_screen.dart';

enum AppStage { splash, bluetoothSetup, stockSelect }

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  AppStage _stage = AppStage.splash;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) {
        return;
      }
      ref.read(productStartupSequenceEnabledProvider.notifier).state = true;
    });
  }

  void _handleSplashComplete() {
    unawaited(_finishLaunch());
  }

  Future<void> _finishLaunch() async {
    await ref.read(stockProvider.notifier).ensureLoaded();
    if (ref.read(demoModeProvider)) {
      unawaited(enableDemoMode(ref));
    }
    if (!mounted) {
      return;
    }
    final nextStage =
        (ref.read(demoModeProvider) || ref.read(stockProvider).registered)
            ? AppStage.stockSelect
            : AppStage.bluetoothSetup;
    setState(() => _stage = nextStage);
  }

  void _handleStartupSetupComplete() {
    if (!mounted) {
      return;
    }
    setState(() => _stage = AppStage.stockSelect);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case AppStage.splash:
        return SplashScreen(onFinished: _handleSplashComplete);
      case AppStage.bluetoothSetup:
        return BluetoothSettingScreen(
          allowBackNavigation: false,
          showStartupGuide: true,
          onSetupComplete: _handleStartupSetupComplete,
        );
      case AppStage.stockSelect:
        return const StockSelectScreen();
    }
  }
}
