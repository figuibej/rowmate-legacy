// lib/core/bluetooth/heart_rate_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'heart_rate_parser.dart';
import 'reconnect_loop.dart';

enum HrmStatus { scanning, connecting, connected, disconnected }

/// Un intento de conexión fue reemplazado por otra acción (interno).
class _SupersededException implements Exception {
  const _SupersededException();
  @override
  String toString() => 'Intento de conexión reemplazado';
}

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

  /// Generación de conexión: connect(), startScan(), disconnect(), forget() y
  /// dispose() la incrementan; un `_connectTo` de una generación anterior se
  /// aborta en su próximo await sin tocar el estado compartido.
  int _connectGen = 0;

  StreamSubscription<List<ScanResult>>? _scanSub;
  Completer<void>? _scanDone;
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
    // Antes del primer await: que ningún reintento se cuele en el hueco.
    _connectGen++;
    _cancelLoops();
    _abortPendingConnect();
    if (!await FlutterBluePlus.isSupported) return;
    _endScanWait(); // un escaneo anterior aún esperando su plazo termina ya
    final done = Completer<void>();
    _scanDone = done;
    _setStatus(HrmStatus.scanning);
    if (!_devicesController.isClosed) _devicesController.add(const []);
    final found = <String, ScanResult>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(HeartRateParser.serviceUuid)],
        timeout: timeout,
      );
      if (!done.isCompleted) {
        // Suscribirse DESPUÉS de startScan: la librería ya vació la lista cacheada
        // (que reemite a cada listener nuevo). Antes recibiríamos el escaneo anterior.
        await _scanSub?.cancel();
        _scanSub = sub = FlutterBluePlus.scanResults.listen(
          (results) {
            for (final r in results) {
              found[r.device.remoteId.str] = r;
            }
            if (!_devicesController.isClosed) _devicesController.add(found.values.toList());
          },
          // Un fallo nativo detiene el escaneo: terminar ya, sin error de zona.
          onError: (Object e) {
            debugPrint('[HRM] Error en el escaneo: $e');
            if (!done.isCompleted) done.complete();
          },
        );
      }
      await Future.any([done.future, Future.delayed(timeout)]);
    } catch (e) {
      debugPrint('[HRM] Error escaneando: $e');
      rethrow;
    } finally {
      await sub?.cancel();
      // Si tras un stopScan() se lanzó otro escaneo, ese es el dueño de
      // _scanSub, _scanDone y del estado: no tocarlos al terminar este.
      if (identical(_scanDone, done)) {
        _scanSub = null;
        _scanDone = null;
        if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
      }
    }
  }

  Future<void> stopScan() async {
    // Solo si el escaneo es nuestro: el activo podría ser el del remo.
    if (_status == HrmStatus.scanning) await FlutterBluePlus.stopScan();
    _endScanWait();
    await _scanSub?.cancel();
    _scanSub = null;
    if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
  }

  /// Hace que el `startScan()` en curso deje de esperar su plazo.
  void _endScanWait() {
    final done = _scanDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  // ── Conexión ─────────────────────────────────────────────────────────────

  /// Conexión manual (desde la lista de escaneo). Lanza si falla.
  Future<void> connect(BluetoothDevice device) async {
    if (_status == HrmStatus.connecting) {
      debugPrint('[HRM] connect ignorado: ya hay una conexión en curso');
      return;
    }
    _connectGen++;
    _cancelLoops();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _endScanWait();
    try {
      await _connectTo(device);
    } on _SupersededException {
      // El propio usuario la reemplazó (otro connect, escaneo, desconectar…).
      debugPrint('[HRM] Conexión manual reemplazada por otra acción');
    }
  }

  /// Al arrancar la app (y desde "Conectar" en la UI): reconectar al sensor
  /// recordado sin escanear, con la cadencia de arranque.
  Future<void> autoConnect() async {
    await _loadRemembered();
    if (_rememberedId == null) return;
    if (_status != HrmStatus.disconnected) return;
    if (_scanDone != null) return; // un escaneo del usuario tiene prioridad
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
    final gen = _connectGen;
    // Tras cada await: si otra acción tomó el control, abortar sin tocar estado.
    void ensureCurrent() {
      if (gen != _connectGen) throw const _SupersededException();
    }

    _isDisconnecting = false;
    _setStatus(HrmStatus.connecting);
    _device = device;
    StreamSubscription<List<int>>? notifySub;
    try {
      await device.connect(
        license: _fbpLicense,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      ensureCurrent();
      final measurement = await _findMeasurement(device);
      ensureCurrent();
      if (measurement == null) {
        await device.disconnect();
        throw const HrmIncompatibleException();
      }
      await measurement.setNotifyValue(true);
      ensureCurrent();
      await _notifySub?.cancel();
      ensureCurrent();
      _notifySub = notifySub = measurement.lastValueStream.listen(_onMeasurement);
      await _remember(device);
      ensureCurrent();

      // Registrar el listener DESPUÉS de conectar para no capturar estados residuales.
      await _connSub?.cancel();
      ensureCurrent();
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
      // Reemplazado (o falló porque lo cancelamos): otra acción es dueña del
      // estado; solo soltar lo propio y desconectar en silencio.
      if (e is _SupersededException || gen != _connectGen) {
        debugPrint('[HRM] Intento de conexión reemplazado: ${device.remoteId.str}');
        if (notifySub != null && identical(_notifySub, notifySub)) {
          notifySub.cancel();
          _notifySub = null;
        }
        // Si el nuevo dueño apunta al mismo sensor, no cortar su intento.
        final owner = _device;
        if (identical(owner, device)) _device = null;
        if (owner == null || identical(owner, device) || owner.remoteId != device.remoteId) {
          await _quietDisconnect(device);
        }
        throw const _SupersededException();
      }
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
    _connectGen++;
    _cancelLoops();
    _isDisconnecting = true;
    final device = _device;
    _cleanupConnection();
    // queue: false salta la cola de FBP: cancela también un connect pendiente
    // (con la cola esperaría hasta el timeout de 15 s del connect).
    if (device != null) await _quietDisconnect(device);
    _isDisconnecting = false;
    await forget();
    _setStatus(HrmStatus.disconnected);
  }

  /// Olvida el sensor recordado y corta reintentos, sin tocar una conexión activa
  /// (un intento de conexión en curso sí se aborta).
  Future<void> forget() async {
    _connectGen++;
    _cancelLoops();
    _abortPendingConnect();
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

  /// Si hay un intento de conexión en vuelo (ya reemplazado vía `_connectGen`),
  /// lo cancela en FBP y deja el estado en `disconnected`.
  void _abortPendingConnect() {
    if (_status != HrmStatus.connecting) return;
    final pending = _device;
    _device = null;
    _setStatus(HrmStatus.disconnected);
    if (pending != null) unawaited(_quietDisconnect(pending));
  }

  Future<void> _quietDisconnect(BluetoothDevice device) async {
    try {
      await device.disconnect(queue: false);
    } catch (e) {
      debugPrint('[HRM] Error al desconectar: $e');
    }
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
    // Sin id no hay sensor: un nombre huérfano (forget() cruzado con
    // _remember()) no debe heredarse al próximo sensor.
    _rememberedName =
        _rememberedId == null ? null : prefs.getString(prefDeviceName);
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
    _connectGen++;
    _cancelLoops();
    _abortPendingConnect();
    _endScanWait();
    _watchdog.stop();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _statusController.close();
    _bpmController.close();
    _devicesController.close();
  }
}
