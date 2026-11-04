import 'package:flutter_riverpod/flutter_riverpod.dart';

final bothSyncroProvider = StateProvider<bool>((ref) => false);
final productStartupSequenceEnabledProvider =
    StateProvider<bool>((ref) => false);
const sceptronicScreenshotMode = bool.fromEnvironment(
  'SCEPTRONIC_SCREENSHOT',
  defaultValue: false,
);
final demoModeProvider = StateProvider<bool>((ref) => false);
