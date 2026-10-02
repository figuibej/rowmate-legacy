import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/features/device/heart_rate_provider.dart';

void main() {
  test('refleja escaneo, conexión, bpm y desconexión del servicio', () {
    fakeAsync((async) {
      final sim = RowingSimulator(noise: false);
      final hrm = SimulatedHeartRateService(sim);
      final p = HeartRateProvider(hrm);
      var notifications = 0;
      p.addListener(() => notifications++);

      expect(p.status, HrmStatus.disconnected);
      expect(p.hasRemembered, isFalse);
      expect(p.scanResults, isEmpty);

      p.startScan();
      async.flushMicrotasks();
      expect(p.isScanning, isTrue);
      expect(p.scanResults, hasLength(1));

      final r = p.scanResults.single;
      p.connect(r.device, name: r.advertisementData.advName);
      async.flushMicrotasks();
      expect(p.isConnected, isTrue);
      expect(p.connectedDeviceName, SimulatedHeartRateService.deviceName);
      expect(p.connectingName, SimulatedHeartRateService.deviceName);

      sim.tick();
      async.elapse(const Duration(seconds: 1));
      expect(p.bpm, sim.heartRate);
      expect(p.bpm, greaterThan(0));

      p.disconnect();
      async.flushMicrotasks();
      expect(p.isConnected, isFalse);
      expect(p.bpm, 0);
      expect(notifications, greaterThan(3));

      p.dispose();
      hrm.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('isIncompatible distingue el sensor incompatible', () {
    const incompatible = HrmIncompatibleException();
    expect(HeartRateProvider.isIncompatible(incompatible), isTrue);
    expect(HeartRateProvider.isIncompatible(StateError('x')), isFalse);
  });
}
