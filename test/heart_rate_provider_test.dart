import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/features/device/heart_rate_provider.dart';

/// Servicio que falla en toda acción, para probar el manejo de errores.
class _ThrowingHrm implements HeartRateService {
  final _status = StreamController<HrmStatus>.broadcast();
  final _bpm = StreamController<int>.broadcast();
  final _devices = StreamController<List<ScanResult>>.broadcast();
  @override
  Stream<HrmStatus> get statusStream => _status.stream;
  @override
  Stream<int> get bpmStream => _bpm.stream;
  @override
  Stream<List<ScanResult>> get devicesStream => _devices.stream;
  @override
  HrmStatus get status => HrmStatus.disconnected;
  @override
  int get bpm => 0;
  @override
  String? get connectedDeviceName => null;
  @override
  String? get rememberedDeviceName => null;
  @override
  bool get isRetrying => false;
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async =>
      throw StateError('scan');
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BluetoothDevice device) async =>
      throw const HrmIncompatibleException();
  @override
  Future<void> autoConnect() async {}
  @override
  Future<void> disconnect() async => throw StateError('disconnect');
  @override
  Future<void> forget() async {}
  @override
  void dispose() {
    _status.close();
    _bpm.close();
    _devices.close();
  }
}

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
      expect(p.connectingName, SimulatedHeartRateService.deviceName,
          reason: 'mientras conecta se muestra el nombre elegido');
      async.flushMicrotasks();
      expect(p.isConnected, isTrue);
      expect(p.connectedDeviceName, SimulatedHeartRateService.deviceName);
      expect(p.connectingName, '', reason: 'al conectar se descarta el nombre elegido');

      sim.tick();
      async.elapse(const Duration(seconds: 1));
      expect(p.bpm, sim.heartRate);
      expect(p.bpm, greaterThan(0));

      // Caída simulada: la tarjeta ve "recordado · reconectando…" y vuelve sola
      hrm.simulateDisconnect();
      async.flushMicrotasks();
      expect(p.isConnected, isFalse);
      expect(p.isRetrying, isTrue);
      expect(p.hasRemembered, isTrue);
      async.elapse(const Duration(seconds: 3));
      expect(p.isConnected, isTrue);
      expect(p.isRetrying, isFalse);

      p.disconnect();
      async.flushMicrotasks();
      expect(p.isConnected, isFalse);
      expect(p.bpm, 0);
      expect(notifications, greaterThan(3));

      p.dispose();
      expect(async.pendingTimers, isEmpty, reason: 'el flujo no deja timers vivos');
      hrm.dispose();
    });
  });

  test('una excepción del servicio queda en error y se limpia al reintentar', () async {
    final hrm = _ThrowingHrm();
    final p = HeartRateProvider(hrm);
    await p.connect(BluetoothDevice.fromId('AA:BB'), name: 'X');
    expect(p.error, isA<HrmIncompatibleException>());
    expect(HeartRateProvider.isIncompatible(p.error!), isTrue);

    await p.retry();
    expect(p.error, isNull);

    await p.disconnect(); // no lanza aunque el servicio falle
    p.dispose();
    hrm.dispose();
  });

  test('isIncompatible distingue el sensor incompatible', () {
    const incompatible = HrmIncompatibleException();
    expect(HeartRateProvider.isIncompatible(incompatible), isTrue);
    expect(HeartRateProvider.isIncompatible(StateError('x')), isFalse);
  });
}
