class BleDevice {
  final String id;
  final String? name;
  const BleDevice({required this.id, this.name});
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
    // Accept names like:
    // - XIAO-ESP32C3-LED-1
    // - XIAO-ESP32C3-LED_STOCK2
    // - XIAO-ESP32C3-LED-STOCK1
    // Any trailing number is treated as the device number.
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
