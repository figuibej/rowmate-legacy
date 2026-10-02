// test/workout_provider_hr_test.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/database/database_service.dart';
import 'package:rowmate/core/models/rowing_data.dart';
import 'package:rowmate/features/workout/workout_provider.dart';

class _FakeBle implements BleService {
  final data = StreamController<RowingData>.broadcast();
  @override
  Stream<RowingData> get dataStream => data.stream;
  @override
  Stream<BleStatus> get statusStream => const Stream.empty();
  @override
  Stream<List<ScanResult>> get devicesStream => const Stream.empty();
  @override
  Stream<List<int>> get rawBytesStream => const Stream.empty();
  @override
  Stream<BluetoothAdapterState> get adapterStateStream => const Stream.empty();
  @override
  BluetoothAdapterState get adapterState => BluetoothAdapterState.on;
  @override
  BleStatus get status => BleStatus.connected;
  @override
  String? get connectedDeviceName => 'fake';
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BluetoothDevice device) async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() => data.close();
}

class _FakeHrm implements HeartRateService {
  final bpmCtrl = StreamController<int>.broadcast();
  final statusCtrl = StreamController<HrmStatus>.broadcast();
  @override
  Stream<int> get bpmStream => bpmCtrl.stream;
  @override
  Stream<HrmStatus> get statusStream => statusCtrl.stream;
  @override
  Stream<List<ScanResult>> get devicesStream => const Stream.empty();
  @override
  HrmStatus get status => HrmStatus.connected;
  @override
  int get bpm => 0;
  @override
  String? get connectedDeviceName => null;
  @override
  String? get rememberedDeviceName => null;
  @override
  bool get isRetrying => false;
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BluetoothDevice device) async {}
  @override
  Future<void> autoConnect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> forget() async {}
  @override
  void dispose() {
    bpmCtrl.close();
    statusCtrl.close();
  }
}

void main() {
  test('el pulsómetro manda sobre el FTMS y se actualiza sin paquetes del remo', () async {
    final ble = _FakeBle();
    final hrm = _FakeHrm();
    final wp = WorkoutProvider(ble, hrm, DatabaseService());
    var notifications = 0;
    wp.addListener(() => notifications++);

    // Sin pulsómetro se respeta lo que diga el monitor
    ble.data.add(const RowingData(powerWatts: 100, heartRate: 90));
    await pumpEventQueue();
    expect(wp.data.heartRate, 90);

    // El bpm llega aunque el remo no mande nada
    hrm.bpmCtrl.add(142);
    await pumpEventQueue();
    expect(wp.data.heartRate, 142);
    expect(wp.data.powerWatts, 100);
    expect(notifications, 2);

    // El siguiente paquete del remo no pisa el pulso del sensor
    ble.data.add(const RowingData(powerWatts: 120, heartRate: 90));
    await pumpEventQueue();
    expect(wp.data.heartRate, 142);
    expect(wp.data.powerWatts, 120);

    // Un 0 del sensor (sin contacto) también manda
    hrm.bpmCtrl.add(0);
    await pumpEventQueue();
    expect(wp.data.heartRate, 0);

    // Al desconectarse el sensor vuelve a 0 y el FTMS repone su valor
    hrm.bpmCtrl.add(130);
    await pumpEventQueue();
    hrm.statusCtrl.add(HrmStatus.disconnected);
    await pumpEventQueue();
    expect(wp.data.heartRate, 0);
    ble.data.add(const RowingData(powerWatts: 120, heartRate: 90));
    await pumpEventQueue();
    expect(wp.data.heartRate, 90);

    wp.dispose();
    ble.dispose();
    hrm.dispose();
  });

  test('orden real de caída: bpm 0 y después disconnected', () async {
    final ble = _FakeBle();
    final hrm = _FakeHrm();
    final wp = WorkoutProvider(ble, hrm, DatabaseService());
    ble.data.add(const RowingData(heartRate: 90));
    hrm.bpmCtrl.add(140);
    await pumpEventQueue();
    expect(wp.data.heartRate, 140);

    hrm.bpmCtrl.add(0); // _cleanupConnection emite 0 antes de disconnected
    hrm.statusCtrl.add(HrmStatus.disconnected);
    await pumpEventQueue();
    expect(wp.data.heartRate, 0);

    ble.data.add(const RowingData(heartRate: 90));
    await pumpEventQueue();
    expect(wp.data.heartRate, 90, reason: 'el FTMS repone su valor');

    wp.dispose();
    ble.dispose();
    hrm.dispose();
  });

  test('un bpm recibido durante connecting se conserva al pasar a connected', () async {
    final ble = _FakeBle();
    final hrm = _FakeHrm();
    final wp = WorkoutProvider(ble, hrm, DatabaseService());
    hrm.statusCtrl.add(HrmStatus.connecting);
    hrm.bpmCtrl.add(120);
    hrm.statusCtrl.add(HrmStatus.connected);
    await pumpEventQueue();
    expect(wp.data.heartRate, 120);

    ble.data.add(const RowingData(heartRate: 90));
    await pumpEventQueue();
    expect(wp.data.heartRate, 120, reason: 'el sensor sigue mandando');

    wp.dispose();
    ble.dispose();
    hrm.dispose();
  });

  test('connected del sensor sin bpm previo no toca los datos', () async {
    final ble = _FakeBle();
    final hrm = _FakeHrm();
    final wp = WorkoutProvider(ble, hrm, DatabaseService());
    var notifications = 0;
    wp.addListener(() => notifications++);
    hrm.statusCtrl.add(HrmStatus.connected);
    hrm.statusCtrl.add(HrmStatus.disconnected);
    await pumpEventQueue();
    expect(notifications, 0);
    wp.dispose();
    ble.dispose();
    hrm.dispose();
  });
}
