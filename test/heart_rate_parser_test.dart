import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_parser.dart';

void main() {
  test('bpm en uint8 sin información de contacto', () {
    final r = HeartRateParser.parse([0x00, 72])!;
    expect(r.bpm, 72);
    expect(r.sensorContact, isNull);
  });

  test('bpm en uint16 little-endian', () {
    final r = HeartRateParser.parse([0x01, 0x2C, 0x01])!; // 0x012C = 300
    expect(r.bpm, 300);
  });

  test('bits de contacto: 01 = no soportado, 10 = sin contacto, 11 = con contacto', () {
    expect(HeartRateParser.parse([0x02, 70])!.sensorContact, isNull);
    expect(HeartRateParser.parse([0x04, 0])!.sensorContact, isFalse);
    expect(HeartRateParser.parse([0x06, 65])!.sensorContact, isTrue);
    expect(HeartRateParser.parse([0x06, 65])!.bpm, 65);
  });

  test('ignora Energy Expended y RR intervals', () {
    // flags 0x18 = bit3 (energía) + bit4 (RR); bpm 80; energía 0x0010; RR 0x0400
    final r = HeartRateParser.parse([0x18, 80, 0x10, 0x00, 0x00, 0x04])!;
    expect(r.bpm, 80);
  });

  test('bytes vacíos o truncados devuelven null', () {
    expect(HeartRateParser.parse([]), isNull);
    expect(HeartRateParser.parse([0x00]), isNull);
    expect(HeartRateParser.parse([0x01, 72]), isNull, reason: 'uint16 necesita 3 bytes');
  });

  test('UUIDs del perfil', () {
    expect(HeartRateParser.serviceUuid, '0000180d-0000-1000-8000-00805f9b34fb');
    expect(HeartRateParser.measurementUuid, '00002a37-0000-1000-8000-00805f9b34fb');
  });
}
