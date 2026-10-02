// lib/core/bluetooth/heart_rate_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'heart_rate_parser.dart';
import 'reconnect_loop.dart';

enum HrmStatus { scanning, connecting, connected, disconnected }

/// El dispositivo conectó pero no expone el servicio Heart Rate (0x180D).
class HrmIncompatibleException implements Exception {
  const HrmIncompatibleException();
  @override
  String toString() => 'El dispositivo no expone el servicio Heart Rate (0x180D)';
}

/// Cliente BLE genérico para sensores de frecuencia cardíaca (Heart Rate Profile).
/// Mismo patrón que [BleService], acotado a un sensor: escaneo, conexión,
/// suscripción a 0x2A37, reconexión automática y memoria del último sensor.
/// El teléfono mantiene esta conexión en paralelo a la del remo.
class HeartRateService {
  /// Misma licencia que BleService (uso personal / sin fines de lucro).
  static const _fbpLicense = License.nonprofit;

  static const prefDeviceId = 'hrm.deviceId';
  static const prefDeviceName = 'hrm.deviceName';

  /// Sin notificaciones durante este tiempo → bpm 0 (reloj apagado / fuera de la muñeca).
  static const staleTimeout = Duration(seconds: 10);

  /// Reintentos al arrancar la app: cada 10 s durante 1 minuto.
  static const startupRetryInterval = Duration(seconds: 10);
  static const startupMaxAttempts = 6;

  /// Reintentos tras una caída estando conectado: cada 3 s, sin límite.
  static const dropRetryInterval = Duration(seconds: 3);

  final _statusController = StreamController<HrmStatus>.broadcast();
  final _bpmController = StreamController<int>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();

  Stream<HrmStatus> get statusStream => _statusController.stream;
  Stream<int> get bpmStream => _bpmController.stream;
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;

  HrmStatus _status = HrmStatus.disconnected;
  HrmStatus get status => _status;

  int _bpm = 0;
  int get bpm => _bpm;

  BluetoothDevice? _device;
  String? _rememberedId;
  String? _rememberedName;
  bool _isDisconnecting = false;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  late final ReconnectLoop _startupLoop = ReconnectLoop(
    interval: startupRetryInterval,
    maxAttempts: startupMaxAttempts,
    attempt: _tryRemembered,
    onGiveUp: _reemitStatus,
  );
  late final ReconnectLoop _dropLoop = ReconnectLoop(
    interval: dropRetryInterval,
    attempt: _tryRemembered,
  );
  late final StaleWatchdog _watchdog = StaleWatchdog(
    timeout: staleTimeout,
    onStale: () => _emitBpm(0),
  );

  String? get connectedDeviceName {
    if (_status != HrmStatus.connected) return null;
    final name = _device?.platformName ?? '';
    return name.isNotEmpty ? name : (_rememberedName ?? _rememberedId);
  }

  String? get rememberedDeviceName =>
      _rememberedId == null ? null : (_rememberedName ?? _rememberedId);

  bool get isRetrying => _startupLoop.isRunning || _dropLoop.isRunning;

  // ── Escaneo ──────────────────────────────────────────────────────────────

  /// Busca sensores con el servicio 0x180D. El filtro lo aplica el sistema.
  /// Nota: flutter_blue_plus corta cualquier escaneo en curso (el del remo):
  /// la UI no permite escanear ambos a la vez. Un escaneo iniciado por el
  /// usuario reemplaza a la reconexión automática.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (!await FlutterBluePlus.isSupported) return;
    _cancelLoops();
    _setStatus(HrmStatus.scanning);
    _devicesController.add(const []);
    final found = <String, ScanResult>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(HeartRateParser.serviceUuid)],
        timeout: timeout,
      );
      // Suscribirse DESPUÉS de startScan: la librería ya vació la lista cacheada
      // (que reemite a cada listener nuevo). Antes recibiríamos el escaneo anterior.
      await _scanSub?.cancel();
      _scanSub = sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          found[r.device.remoteId.str] = r;
        }
        if (!_devicesController.isClosed) _devicesController.add(found.values.toList());
      });
      await Future.delayed(timeout);
    } catch (e) {
      debugPrint('[HRM] Error escaneando: $e');
      rethrow;
    } finally {
      await sub?.cancel();
      // Si tras un stopScan() se lanzó otro escaneo, ese es el dueño de
      // _scanSub y del estado: no tocarlos al vencer el plazo de este.
      if (sub == null || identical(_scanSub, sub)) {
        _scanSub = null;
        if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
      }
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
  }

  // ── Conexión ─────────────────────────────────────────────────────────────

  /// Conexión manual (desde la lista de escaneo). Lanza si falla.
  Future<void> connect(BluetoothDevice device) async {
    if (_status == HrmStatus.connecting) {
      debugPrint('[HRM] connect ignorado: ya hay una conexión en curso');
      return;
    }
    _cancelLoops();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    await _connectTo(device);
  }

  /// Al arrancar la app (y desde "Conectar" en la UI): reconectar al sensor
  /// recordado sin escanear, con la cadencia de arranque.
  Future<void> autoConnect() async {
    await _loadRemembered();
    if (_rememberedId == null) return;
    if (_status != HrmStatus.disconnected) return;
    _dropLoop.cancel();
    _startupLoop.start();
    _reemitStatus(); // isRetrying cambió
  }

  Future<bool> _tryRemembered() async {
    final id = _rememberedId;
    if (id == null) return true; // nada que reintentar
    try {
      await _connectTo(BluetoothDevice.fromId(id));
      return true;
    } catch (e) {
      debugPrint('[HRM] Reintento fallido: $e');
      return false;
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _isDisconnecting = false;
    _setStatus(HrmStatus.connecting);
    _device = device;
    try {
      await device.connect(
        license: _fbpLicense,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      final measurement = await _findMeasurement(device);
      if (measurement == null) {
        await device.disconnect();
        throw const HrmIncompatibleException();
      }
      await measurement.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = measurement.lastValueStream.listen(_onMeasurement);
      await _remember(device);

      // Registrar el listener DESPUÉS de conectar para no capturar estados residuales.
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_isDisconnecting) {
          debugPrint('[HRM] Conexión perdida, reintentando cada ${dropRetryInterval.inSeconds}s');
          _cleanupConnection();
          _setStatus(HrmStatus.disconnected);
          _dropLoop.start();
        }
      });

      _watchdog.touch();
      _setStatus(HrmStatus.connected);
      debugPrint('[HRM] Conectado a ${connectedDeviceName ?? device.remoteId.str}');
    } catch (e) {
      debugPrint('[HRM] Error al conectar: $e');
      _cleanupConnection();
      _setStatus(HrmStatus.disconnected);
      rethrow;
    }
  }

  Future<BluetoothCharacteristic?> _findMeasurement(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final svc = Guid(HeartRateParser.serviceUuid);
    final chr = Guid(HeartRateParser.measurementUuid);
    for (final s in services) {
      if (s.uuid != svc) continue;
      for (final c in s.characteristics) {
        if (c.uuid == chr) return c;
      }
    }
    return null;
  }

  void _onMeasurement(List<int> bytes) {
    final reading = HeartRateParser.parse(bytes);
    if (reading == null) return;
    _watchdog.touch();
    _emitBpm(reading.sensorContact == false ? 0 : reading.bpm);
  }

  void _emitBpm(int value) {
    _bpm = value;
    if (!_bpmController.isClosed) _bpmController.add(value);
  }

  // ── Desconexión ──────────────────────────────────────────────────────────

  /// Desconexión manual: corta reintentos, desconecta y olvida el sensor
  /// (si no, la reconexión automática lo volvería a enganchar).
  Future<void> disconnect() async {
    _cancelLoops();
    _isDisconnecting = true;
    final device = _device;
    _cleanupConnection();
    try {
      await device?.disconnect();
    } catch (e) {
      debugPrint('[HRM] Error al desconectar: $e');
    }
    _isDisconnecting = false;
    await forget();
    _setStatus(HrmStatus.disconnected);
  }

  /// Olvida el sensor recordado y corta reintentos, sin tocar una conexión activa.
  Future<void> forget() async {
    _cancelLoops();
    _rememberedId = null;
    _rememberedName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefDeviceId);
    await prefs.remove(prefDeviceName);
    _reemitStatus();
  }

  void _cancelLoops() {
    _startupLoop.cancel();
    _dropLoop.cancel();
  }

  void _cleanupConnection() {
    _notifySub?.cancel();
    _notifySub = null;
    _watchdog.stop();
    _connSub?.cancel();
    _connSub = null;
    _device = null;
    if (_bpm != 0) _emitBpm(0);
  }

  // ── Memoria ──────────────────────────────────────────────────────────────

  Future<void> _remember(BluetoothDevice device) async {
    _rememberedId = device.remoteId.str;
    final name = device.platformName.isNotEmpty ? device.platformName : device.advName;
    if (name.isNotEmpty) _rememberedName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefDeviceId, _rememberedId!);
    if (_rememberedName != null) await prefs.setString(prefDeviceName, _rememberedName!);
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedId = prefs.getString(prefDeviceId);
    _rememberedName = prefs.getString(prefDeviceName);
  }

  // ── Estado ───────────────────────────────────────────────────────────────

  void _setStatus(HrmStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Reemite el estado actual para que la UI relea `isRetrying` / `rememberedDeviceName`.
  void _reemitStatus() {
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  void dispose() {
    _cancelLoops();
    _watchdog.stop();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _statusController.close();
    _bpmController.close();
    _devicesController.close();
  }
}
