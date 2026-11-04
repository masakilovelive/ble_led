import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:logger/logger.dart' as app_logger;
import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureBlePermissions(app_logger.Logger log) async {
  final permissions = <Permission>[];
  if (Platform.isAndroid) {
    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    permissions.addAll(
      sdkInt >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse],
    );
  } else if (Platform.isIOS) {
    permissions.add(Permission.bluetooth);
  }

  if (permissions.isEmpty) {
    return true;
  }

  final statuses = await permissions.request();
  final granted = statuses.values.every(
    (status) => status.isGranted || status.isLimited,
  );
  if (!granted) {
    log.w('BLE permission denied: $statuses');
  }
  return granted;
}
