import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/bluetooth/heart_rate_service.dart';

/// Estado del pulsómetro para la tarjeta de la pestaña Dispositivo.
class HeartRateProvider extends ChangeNotifier {
  final HeartRateService _hrm;

  HrmStatus _status;
  int _bpm;
  List<ScanResult> _scanResults = const [];
  Object? _error;
  String? _connectingName;

  StreamSubscription<HrmStatus>? _statusSub;
  StreamSubscription<int>? _bpmSub;
  StreamSubscription<List<ScanResult>>? _devicesSub;

  HeartRateProvider(this._hrm)
      : _status = _hrm.status,
        _bpm = _hrm.bpm {
    _statusSub = _hrm.statusStream.listen((s) {
      _status = s;
      if (s == HrmStatus.connected) _error = null;
      // El nombre elegido en la lista solo vale para ese intento; los
      // reintentos automáticos muestran el sensor recordado.
      if (s != HrmStatus.connecting) _connectingName = null;
      notifyListeners();
    });
    _bpmSub = _hrm.bpmStream.listen((b) {
      _bpm = b;
      notifyListeners();
    });
    _devicesSub = _hrm.devicesStream.listen((r) {
      _scanResults = r;
      notifyListeners();
    });
  }

  HrmStatus get status => _status;
  bool get isConnected => _status == HrmStatus.connected;
  bool get isScanning => _status == HrmStatus.scanning;
  bool get isConnecting => _status == HrmStatus.connecting;
  bool get isRetrying => _hrm.isRetrying;
  int get bpm => _bpm;
  List<ScanResult> get scanResults => _scanResults;
  String? get connectedDeviceName => _hrm.connectedDeviceName;
  String? get rememberedDeviceName => _hrm.rememberedDeviceName;
  bool get hasRemembered => _hrm.rememberedDeviceName != null;
  Object? get error => _error;

  /// Nombre a mostrar mientras conecta: el elegido en la lista o el recordado.
  String get connectingName => _connectingName ?? rememberedDeviceName ?? '';

  static bool isIncompatible(Object error) => error is HrmIncompatibleException;

  Future<void> startScan() async {
    _error = null;
    _scanResults = const [];
    notifyListeners();
    await _run(() => _hrm.startScan());
  }

  Future<void> connect(BluetoothDevice device, {String? name}) async {
    _error = null;
    _connectingName = name;
    notifyListeners();
    await _run(() => _hrm.connect(device));
  }

  /// Reintenta con el sensor recordado (misma cadencia que al arrancar).
  Future<void> retry() async {
    _error = null;
    _connectingName = null;
    notifyListeners();
    await _run(() => _hrm.autoConnect());
  }

  Future<void> disconnect() async {
    _error = null;
    await _run(() => _hrm.disconnect());
  }

  Future<void> forget() async {
    _error = null;
    await _run(() => _hrm.forget());
    _notifyIfAlive();
  }

  /// Ejecuta una acción del servicio y deja su excepción en [error].
  /// Una conexión real puede tardar 15 s: si el provider ya fue descartado
  /// no se notifica.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _error = e;
      _notifyIfAlive();
    }
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _statusSub?.cancel();
    _bpmSub?.cancel();
    _devicesSub?.cancel();
    super.dispose();
  }
}
