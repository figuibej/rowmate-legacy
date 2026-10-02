// test/simulated_heart_rate_service_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';

void main() {
  test('startScan emite el sensor sintético y connect emite bpm cada segundo', () {
    fakeAsync((async) {
      final sim = RowingSimulator(noise: false);
      final hrm = SimulatedHeartRateService(sim);
      final statuses = <HrmStatus>[];
      final devices = <List<ScanResult>>[];
      final bpm = <int>[];
      hrm.statusStream.listen(statuses.add);
      hrm.devicesStream.listen(devices.add);
      hrm.bpmStream.listen(bpm.add);

      expect(hrm.status, HrmStatus.disconnected);
      expect(hrm.rememberedDeviceName, isNull);

      hrm.startScan();
      async.flushMicrotasks();
      expect(statuses, [HrmStatus.scanning]);
      final result = devices.single.single;
      expect(result.advertisementData.advName, SimulatedHeartRateService.deviceName);
      expect(result.device.remoteId.str, SimulatedHeartRateService.deviceId);

      hrm.connect(result.device);
      async.flushMicrotasks();
      expect(hrm.status, HrmStatus.connected);
      expect(hrm.connectedDeviceName, SimulatedHeartRateService.deviceName);

      sim.tick();
      sim.tick();
      async.elapse(const Duration(seconds: 3));
      expect(bpm, hasLength(3));
      expect(bpm.last, sim.heartRate);
      expect(bpm.last, greaterThan(0));
      expect(hrm.bpm, bpm.last);

      hrm.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('el escaneo expira a disconnected si no se conecta', () {
    fakeAsync((async) {
      final hrm = SimulatedHeartRateService(RowingSimulator(noise: false));
      hrm.startScan();
      async.elapse(const Duration(seconds: 9));
      expect(hrm.status, HrmStatus.scanning);
      async.elapse(const Duration(seconds: 1));
      expect(hrm.status, HrmStatus.disconnected);
      hrm.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('simulateDisconnect cae y reconecta a los 3 s; disconnect no reconecta', () {
    fakeAsync((async) {
      final hrm = SimulatedHeartRateService(RowingSimulator(noise: false));
      final statuses = <HrmStatus>[];
      final bpm = <int>[];
      hrm.statusStream.listen(statuses.add);
      hrm.bpmStream.listen(bpm.add);
      hrm.connect(BluetoothDevice.fromId(SimulatedHeartRateService.deviceId));
      async.elapse(const Duration(seconds: 1));
      expect(bpm, hasLength(1));

      hrm.simulateDisconnect();
      async.flushMicrotasks(); // los broadcast controllers entregan en microtask
      expect(hrm.isRetrying, isTrue);
      expect(hrm.rememberedDeviceName, SimulatedHeartRateService.deviceName,
          reason: 'mientras reconecta la tarjeta muestra "reconectando…"');
      expect(bpm.last, 0, reason: 'al caer se emite 0');
      async.elapse(const Duration(seconds: 2));
      expect(statuses, [HrmStatus.connected, HrmStatus.disconnected]);
      async.elapse(const Duration(seconds: 1));
      expect(statuses.last, HrmStatus.connected);
      expect(hrm.isRetrying, isFalse);
      expect(hrm.rememberedDeviceName, isNull);

      hrm.disconnect();
      async.elapse(const Duration(seconds: 10));
      expect(hrm.status, HrmStatus.disconnected);
      expect(hrm.connectedDeviceName, isNull);

      hrm.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
