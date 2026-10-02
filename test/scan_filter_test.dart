import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_parser.dart';
import 'package:rowmate/core/bluetooth/scan_filter.dart';

ScanResult _result(List<Guid> uuids) => ScanResult(
      device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
      advertisementData: AdvertisementData(
        advName: '',
        txPowerLevel: null,
        appearance: null,
        connectable: true,
        manufacturerData: const {},
        serviceData: const {},
        serviceUuids: uuids,
      ),
      rssi: -50,
      timeStamp: DateTime.now(),
    );

void main() {
  final hrs = Guid(HeartRateParser.serviceUuid);

  test('con filtro en el cliente solo pasan los que anuncian el servicio', () {
    expect(acceptScanResult(_result([]), hrs, clientSide: true), isFalse);
    expect(acceptScanResult(_result([Guid('febe')]), hrs, clientSide: true), isFalse);
    expect(acceptScanResult(_result([Guid('180d')]), hrs, clientSide: true), isTrue,
        reason: 'el UUID de 16 bits equivale al de 128');
    expect(acceptScanResult(_result([Guid('febe'), hrs]), hrs, clientSide: true), isTrue);
  });

  test('sin filtro en el cliente (el sistema ya filtró) pasa todo', () {
    expect(acceptScanResult(_result([]), hrs, clientSide: false), isTrue);
    expect(acceptScanResult(_result([Guid('febe')]), hrs, clientSide: false), isTrue);
  });
}
