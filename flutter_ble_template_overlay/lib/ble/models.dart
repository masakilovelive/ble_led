
class BleDevice {
  final String id;
  final String? name;
  final int? rssi;
  const BleDevice({required this.id, this.name, this.rssi});
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
