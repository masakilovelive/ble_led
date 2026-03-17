import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/app_root.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        Zone.current.handleUncaughtError(
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught platform error: $error');
        debugPrintStack(stackTrace: stack);
        return true;
      };

      ErrorWidget.builder = (details) {
        FlutterError.presentError(details);
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'Unexpected error',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ),
        );
      };

      runApp(const ProviderScope(child: BleLedApp()));
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

class BleLedApp extends StatelessWidget {
  const BleLedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BLE LED STRESS',
      theme: base.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF28A745),
          secondary: const Color(0xFF4DD0E1),
          surface: const Color(0xFF111111),
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme(
          base.textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const AppRoot(),
    );
  }
}
