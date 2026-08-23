import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStore {
  LocalStore._(this._file, this._data);

  static Future<LocalStore>? _pending;

  final File _file;
  final Map<String, dynamic> _data;

  static Future<LocalStore> instance() {
    return _pending ??= _load();
  }

  static Future<LocalStore> _load() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}app_state.json',
    );
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('{}');
      return LocalStore._(file, <String, dynamic>{});
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return LocalStore._(file, Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      await file.writeAsString('{}');
    }
    return LocalStore._(file, <String, dynamic>{});
  }

  String? getString(String key) {
    final value = _data[key];
    return value is String ? value : null;
  }

  bool? getBool(String key) {
    final value = _data[key];
    return value is bool ? value : null;
  }

  Future<void> setString(String key, String value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> setBool(String key, bool value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _save();
  }

  Future<void> _save() async {
    await _file.writeAsString(jsonEncode(_data));
  }
}
