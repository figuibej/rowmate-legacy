import 'dart:typed_data';

/// Lectura del characteristic Heart Rate Measurement (0x2A37).
class HeartRateReading {
  final int bpm;

  /// null = el sensor no informa contacto; false = sin contacto; true = con contacto.
  final bool? sensorContact;

  const HeartRateReading({required this.bpm, this.sensorContact});
}

/// Parser del Heart Rate Profile (Bluetooth SIG).
///
/// Byte 0 = flags:
///   Bit 0    – formato del bpm: 0 = uint8 (byte 1), 1 = uint16 LE (bytes 1-2)
///   Bits 1-2 – contacto del sensor: 0b0x = no soportado, 0b10 = sin contacto, 0b11 = con contacto
///   Bit 3    – Energy Expended presente (uint16), se ignora
///   Bit 4    – intervalos RR presentes (uint16 cada uno), se ignoran
class HeartRateParser {
  static const String serviceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String measurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  static HeartRateReading? parse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final is16 = (flags & 0x01) != 0;
    if (bytes.length < (is16 ? 3 : 2)) return null;

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final bpm = is16 ? data.getUint16(1, Endian.little) : data.getUint8(1);

    final contactBits = (flags >> 1) & 0x03;
    final bool? contact = switch (contactBits) {
      2 => false,
      3 => true,
      _ => null,
    };
    return HeartRateReading(bpm: bpm, sensorContact: contact);
  }
}
