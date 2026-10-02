// lib/core/bluetooth/simulated_heart_rate_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../dev/rowing_simulator.dart';
import 'heart_rate_parser.dart';
import 'heart_rate_service.dart';

/// Reemplazo de [HeartRateService] en modo simulador (`kSimulator`):
/// un único sensor sintético que emite el pulso calculado por [RowingSimulator].
/// No persiste nada: la tarjeta siempre arranca en "sin sensor".
class SimulatedHeartRateService implements HeartRateService {
  static const deviceName = 'Pulsómetro simulado';
  static const deviceId = 'SIM:HRM';

  SimulatedHeartRateService(this.simulator);

  final RowingSimulator simulator;

  final _statusController = StreamController<HrmStatus>.broadcast();
  final _bpmController = StreamController<int>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();

  HrmStatus _status = HrmStatus.disconnected;
  int _bpm = 0;
  Timer? _dataTimer;
  Timer? _scanTimer;
  Timer? _reconnectTimer;

  @override
  Stream<HrmStatus> get statusStream => _statusController.stream;
  @override
  Stream<int> get bpmStream => _bpmController.stream;
  @override
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;
  @override
  HrmStatus get status => _status;
  @override
  int get bpm => _bpm;
  @override
  String? get connectedDeviceName =>
      _status == HrmStatus.connected ? deviceName : null;
  @override
  String? get rememberedDeviceName => null;
  @override
  bool get isRetrying => _reconnectTimer != null;

  static ScanResult fakeScanResult() => ScanResult(
        device: BluetoothDevice.fromId(deviceId),
        advertisementData: AdvertisementData(
          advName: deviceName,
          txPowerLevel: null,
          appearance: null,
          connectable: true,
          manufacturerData: const {},
          serviceData: const {},
          serviceUuids: [Guid(HeartRateParser.serviceUuid)],
        ),
        rssi: -50,
        timeStamp: DateTime.now(),
      );

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    _scanTimer?.cancel();
    _setStatus(HrmStatus.scanning);
    _devicesController.add([fakeScanResult()]);
    _scanTimer = Timer(timeout, () {
      _scanTimer = null;
      if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
  }

  @override
  Future<void> connect(BluetoothDevice device) async => _connect();

  /// Sin sensor recordado en modo simulador: no conecta solo.
  @override
  Future<void> autoConnect() async {}

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stop();
  }

  @override
  Future<void> forget() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _statusController.add(_status);
  }

  /// Simula una caída y la reconexión automática.
  void simulateDisconnect({Duration reconnectAfter = const Duration(seconds: 3)}) {
    if (_status != HrmStatus.connected) return;
    debugPrint('[SIM] Pulsómetro desconectado, reconectando en ${reconnectAfter.inSeconds}s');
    _reconnectTimer = Timer(reconnectAfter, () {
      _reconnectTimer = null;
      _connect();
    });
    _stop(); // emite disconnected ya con isRetrying == true
  }

  void _connect() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_status == HrmStatus.connected) return;
    _setStatus(HrmStatus.connected);
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _bpm = simulator.heartRate;
      _bpmController.add(_bpm);
    });
  }

  void _stop() {
    _dataTimer?.cancel();
    _dataTimer = null;
    if (_bpm != 0) {
      _bpm = 0;
      _bpmController.add(0);
    }
    if (_status != HrmStatus.disconnected) _setStatus(HrmStatus.disconnected);
  }

  void _setStatus(HrmStatus s) {
    _status = s;
    _statusController.add(s);
  }

  @override
  void dispose() {
    _dataTimer?.cancel();
    _scanTimer?.cancel();
    _reconnectTimer?.cancel();
    _statusController.close();
    _bpmController.close();
    _devicesController.close();
  }
}
