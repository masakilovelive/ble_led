import 'package:flutter_riverpod/flutter_riverpod.dart';

final bothSyncroProvider = StateProvider<bool>((ref) => false);
final productStartupSequenceEnabledProvider =
    StateProvider<bool>((ref) => false);
