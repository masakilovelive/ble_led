import 'package:flutter/material.dart';

import 'shipment_inspection_screen.dart';
import 'splash_screen.dart';

enum AppStage { splash, shipment }

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  AppStage _stage = AppStage.splash;

  void _handleSplashComplete() {
    if (!mounted) {
      return;
    }
    setState(() => _stage = AppStage.shipment);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case AppStage.splash:
        return SplashScreen(onFinished: _handleSplashComplete);
      case AppStage.shipment:
        return const ShipmentInspectionScreen();
    }
  }
}
