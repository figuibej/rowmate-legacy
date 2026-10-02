import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../dev/rowing_simulator.dart';
import '../models/rowing_data.dart';
import 'ble_service.dart';

/// Reemplazo de [BleService] para modo desarrollo (`kSimulator`):
/// simula un remo FTMS conectado que emite datos cada segundo.
class SimulatedBleService implements BleService {
  static const deviceName = 'Remo simulado';

  SimulatedBleService({RowingSimulator? simulator})
      : simulator = simulator ?? RowingSimulator() {
    // DeviceProvider no lee el estado inicial, solo escucha los streams:
    // emitir recién cuando aparece el primer listener.
    _statusController = StreamController<BleStatus>.broadcast(onListen: () {
      if (_autoConnected) return;
      _autoConnected = true;
      scheduleMicrotask(_connect);
    });
    _adapterStateController =
        StreamController<BluetoothAdapterState>.broadcast(onListen: () {
      scheduleMicrotask(
          () => _adapterStateController.add(BluetoothAdapterState.on));
    });
  }

  final RowingSimulator simulator;

  late final StreamController<BleStatus> _statusController;
  late final StreamController<BluetoothAdapterState> _adapterStateController;
  final _dataController = StreamController<RowingData>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();
  final _rawBytesController = StreamController<List<int>>.broadcast();

  BleStatus _status = BleStatus.disconnected;
  bool _autoConnected = false;
  Timer? _dataTimer;
  Timer? _reconnectTimer;

  @override
  Stream<BleStatus> get statusStream => _statusController.stream;
  @override
  Stream<RowingData> get dataStream => _dataController.stream;
  @override
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;
  @override
  Stream<List<int>> get rawBytesStream => _rawBytesController.stream;
  @override
  Stream<BluetoothAdapterState> get adapterStateStream =>
      _adapterStateController.stream;

  @override
  BluetoothAdapterState get adapterState => BluetoothAdapterState.on;
  @override
  BleStatus get status => _status;
  @override
  String? get connectedDeviceName =>
      _status == BleStatus.connected ? deviceName : null;

  /// No hay dispositivos que escanear: "Buscar" reconecta al remo simulado.
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async =>
      _connect();

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(BluetoothDevice device) async => _connect();

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stop();
  }

  /// Simula que se corta la conexión y vuelve, como la auto-reconexión real.
  void simulateDisconnect({Duration reconnectAfter = const Duration(seconds: 3)}) {
    if (_status != BleStatus.connected) return;
    debugPrint('[SIM] Desconexión simulada, reconectando en ${reconnectAfter.inSeconds}s');
    _stop();
    _reconnectTimer = Timer(reconnectAfter, _connect);
  }

  void _connect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_status == BleStatus.connected) return;
    _setStatus(BleStatus.connected);
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _dataController.add(simulator.tick());
    });
  }

  void _stop() {
    _dataTimer?.cancel();
    _dataTimer = null;
    if (_status != BleStatus.disconnected) _setStatus(BleStatus.disconnected);
  }

  void _setStatus(BleStatus s) {
    _status = s;
    _statusController.add(s);
  }

  @override
  void dispose() {
    _dataTimer?.cancel();
    _reconnectTimer?.cancel();
    _statusController.close();
    _dataController.close();
    _devicesController.close();
    _rawBytesController.close();
    _adapterStateController.close();
  }
}
