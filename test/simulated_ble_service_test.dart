import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/models/rowing_data.dart';

void main() {
  SimulatedBleService build() =>
      SimulatedBleService(simulator: RowingSimulator(noise: false));

  test('emite connected y adapter on al primer listener, y datos cada segundo', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      final adapter = <BluetoothAdapterState>[];
      final data = <RowingData>[];
      ble.statusStream.listen(statuses.add);
      ble.adapterStateStream.listen(adapter.add);
      ble.dataStream.listen(data.add);

      async.flushMicrotasks();
      expect(statuses, [BleStatus.connected]);
      expect(adapter, [BluetoothAdapterState.on]);
      expect(ble.status, BleStatus.connected);
      expect(ble.connectedDeviceName, SimulatedBleService.deviceName);

      async.elapse(const Duration(seconds: 3));
      expect(data, hasLength(3));
      expect(data.last.distanceMeters, greaterThan(data.first.distanceMeters));

      ble.dispose();
    });
  });

  test('simulateDisconnect emite disconnected y reconecta a los 3 s', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      final data = <RowingData>[];
      ble.statusStream.listen(statuses.add);
      ble.dataStream.listen(data.add);
      async.flushMicrotasks();

      ble.simulateDisconnect();
      async.elapse(const Duration(seconds: 2));
      expect(statuses, [BleStatus.connected, BleStatus.disconnected]);
      expect(data, isEmpty, reason: 'no hay datos mientras está desconectado');

      async.elapse(const Duration(seconds: 1));
      expect(statuses, [
        BleStatus.connected,
        BleStatus.disconnected,
        BleStatus.connected,
      ]);

      ble.dispose();
    });
  });

  test('disconnect no reconecta solo; startScan reconecta', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      ble.statusStream.listen(statuses.add);
      async.flushMicrotasks();

      ble.disconnect();
      async.elapse(const Duration(seconds: 10));
      expect(ble.status, BleStatus.disconnected);
      expect(ble.connectedDeviceName, isNull);

      ble.startScan();
      async.flushMicrotasks();
      expect(ble.status, BleStatus.connected);
      expect(statuses.last, BleStatus.connected);

      ble.dispose();
    });
  });
}
