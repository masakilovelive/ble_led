import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/led_ui_state.dart';
import '../ble/models.dart';

final bothSyncroProvider = StateProvider<bool>((ref) => false);
final productStartupSequenceEnabledProvider =
    StateProvider<bool>((ref) => false);
const sceptronicScreenshotMode = bool.fromEnvironment(
  'SCEPTRONIC_SCREENSHOT',
  defaultValue: false,
);
final demoModeProvider = StateProvider<bool>(
  (ref) =>
      sceptronicScreenshotMode ||
      const bool.fromEnvironment(
        'SCEPTRONIC_DEMO',
        defaultValue: false,
      ),
);

Future<void> enableDemoMode(WidgetRef ref) async {
  ref.read(demoModeProvider.notifier).state = true;
  ref.read(bothSyncroProvider.notifier).state = false;

  final ui = ref.read(ledUiProvider.notifier);
  await ui.ensureLoaded();
  _seedDemoSide(
    ui,
    StockSide.a,
    top: const Color(0xFF24D8FF),
    bottom: const Color(0xFF7CFF6B),
    batteryVoltage: 4.04,
    batteryPercent: 0.86,
  );
  _seedDemoSide(
    ui,
    StockSide.b,
    top: const Color(0xFFFFB75D),
    bottom: const Color(0xFFFF6B9A),
    batteryVoltage: 3.96,
    batteryPercent: 0.72,
  );
}

void disableDemoMode(WidgetRef ref) {
  ref.read(demoModeProvider.notifier).state = false;
  ref.read(bothSyncroProvider.notifier).state = false;
}

void _seedDemoSide(
  LedUiController ui,
  StockSide side, {
  required Color top,
  required Color bottom,
  required double batteryVoltage,
  required double batteryPercent,
}) {
  ui.setOutputEnabled(side, true, persist: false);
  ui.setBrightness(side, 210, persist: false);
  ui.setSegmentColor(side, ColorZone.top, top, persist: false);
  ui.setSegmentColor(side, ColorZone.bottom, bottom, persist: false);
  ui.setSegmentMode(side, ColorZone.both, LedMode.color, persist: false);
  ui.setBatteryVoltage(side, batteryVoltage, batteryPercent);
}
