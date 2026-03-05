import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/app_root.dart';

void main() {
  runApp(const ProviderScope(child: SkiLedApp()));
}

class SkiLedApp extends StatelessWidget {
  const SkiLedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SKI LED',
      theme: base.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF28A745),
          secondary: const Color(0xFF4DD0E1),
          surface: const Color(0xFF111111),
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const AppRoot(),
    );
  }
}
