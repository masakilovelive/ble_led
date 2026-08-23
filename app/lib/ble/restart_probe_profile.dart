import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum RestartProbeFeature { color, rainbow, heartbeat }

class RestartProbeProfile {
  static const String fileName = 'restart_probe_profile.json';

  final bool enabled;
  final bool syncro;
  final RestartProbeFeature feature;
  final Color color;
  final int brightness;
  final int heartbeatIntervalMs;
  final int rainbowIntervalMs;
  final String scenarioLabel;

  const RestartProbeProfile({
    required this.enabled,
    required this.syncro,
    required this.feature,
    required this.color,
    required this.brightness,
    required this.heartbeatIntervalMs,
    required this.rainbowIntervalMs,
    required this.scenarioLabel,
  });

  String get featureName {
    switch (feature) {
      case RestartProbeFeature.color:
        return 'color';
      case RestartProbeFeature.rainbow:
        return 'rainbow';
      case RestartProbeFeature.heartbeat:
        return 'heartbeat';
    }
  }

  String get colorHex =>
      color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

  static Future<File> resolveFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  static Future<RestartProbeProfile?> load() async {
    final file = await resolveFile();
    if (!await file.exists()) {
      return null;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static RestartProbeProfile? fromJson(Map<String, dynamic> json) {
    final feature = _parseFeature(json['feature']?.toString());
    if (feature == null) {
      return null;
    }
    return RestartProbeProfile(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      syncro: json['syncro'] is bool ? json['syncro'] as bool : true,
      feature: feature,
      color:
          _parseColor(json['color_hex']?.toString()) ?? const Color(0xFFFF0000),
      brightness: _parseInt(json['brightness'], 255).clamp(0, 255),
      heartbeatIntervalMs:
          _parseInt(json['heartbeat_interval_ms'], 600).clamp(150, 10000),
      rainbowIntervalMs:
          _parseInt(json['rainbow_interval_ms'], 40).clamp(1, 65535),
      scenarioLabel:
          json['scenario_label']?.toString().trim().isNotEmpty == true
              ? json['scenario_label'].toString().trim()
              : feature.name,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'syncro': syncro,
      'feature': featureName,
      'color_hex': colorHex,
      'brightness': brightness,
      'heartbeat_interval_ms': heartbeatIntervalMs,
      'rainbow_interval_ms': rainbowIntervalMs,
      'scenario_label': scenarioLabel,
    };
  }

  static RestartProbeFeature? _parseFeature(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'color':
        return RestartProbeFeature.color;
      case 'rainbow':
        return RestartProbeFeature.rainbow;
      case 'heartbeat':
        return RestartProbeFeature.heartbeat;
      default:
        return null;
    }
  }

  static int _parseInt(Object? raw, int fallback) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse('${raw ?? ''}') ?? fallback;
  }

  static Color? _parseColor(String? raw) {
    if (raw == null) {
      return null;
    }
    final compact = raw.replaceAll('#', '').trim();
    final normalized = compact.length == 6 ? 'FF$compact' : compact;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(value);
  }
}
