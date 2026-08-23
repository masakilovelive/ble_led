class BleDevice {
  final String id;
  final String? name;
  final int? rssi;

  const BleDevice({
    required this.id,
    this.name,
    this.rssi,
  });
}

enum StockSide { a, b }

class DeviceNameInfo {
  final int? deviceNumber;
  final int? pairNumber;
  final String? role;

  const DeviceNameInfo({
    this.deviceNumber,
    this.pairNumber,
    this.role,
  });

  static DeviceNameInfo fromName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return const DeviceNameInfo();
    }
    final match = RegExp(r'(\d+)\s*$').firstMatch(name.trim());
    if (match == null) {
      return const DeviceNameInfo();
    }
    final number = int.tryParse(match.group(1)!);
    if (number == null || number <= 0) {
      return const DeviceNameInfo();
    }
    final pairNumber = ((number - 1) ~/ 2) + 1;
    final role = number.isOdd ? 'A' : 'B';
    return DeviceNameInfo(
      deviceNumber: number,
      pairNumber: pairNumber,
      role: role,
    );
  }
}

class GattCharacteristic {
  final String uuid;
  final bool canRead;
  final bool canWrite;
  final bool canNotify;
  final bool canIndicate;

  const GattCharacteristic({
    required this.uuid,
    this.canRead = false,
    this.canWrite = false,
    this.canNotify = false,
    this.canIndicate = false,
  });
}

class GattService {
  final String uuid;
  final List<GattCharacteristic> characteristics;

  const GattService(this.uuid, this.characteristics);
}
