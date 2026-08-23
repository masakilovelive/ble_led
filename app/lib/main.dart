import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/app_root.dart';
import 'screens/sceptronic_ui.dart';

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
      title: 'ScepTRONIC',
      theme: base.copyWith(
        scaffoldBackgroundColor: SceptronicPalette.background,
        colorScheme: base.colorScheme.copyWith(
          primary: SceptronicPalette.primary,
          secondary: SceptronicPalette.secondary,
          surface: SceptronicPalette.panel,
        ),
        textTheme: GoogleFonts.rajdhaniTextTheme(
          base.textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: const AppBarTheme(
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        splashFactory: InkRipple.splashFactory,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: SceptronicPalette.primary),
          ),
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const AppRoot(),
    );
  }
}
