import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ftms_parser.dart';
import '../models/rowing_data.dart';

enum BleStatus { off, scanning, connecting, connected, disconnected }

/// Servicio BLE que maneja la conexión con el rower AMS-670B (módulo Kinomap-XG/H201)
class BleService {
  /// Licencia de flutter_blue_plus 2.x: nonprofit = uso personal/ONG/educativo.
  /// Uso por una organización con fines de lucro requiere License.commercial (pago).
  static const _fbpLicense = License.nonprofit;

  BluetoothDevice? _device;
  BluetoothDevice? _lastDevice; // para auto-reconexión
  BluetoothCharacteristic? _rowerDataChar;
  BluetoothCharacteristic? _controlPointChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  bool _isDisconnecting = false; // evita reconexión durante desconexión manual/watchdog

  final _statusController = StreamController<BleStatus>.broadcast();
  final _dataController = StreamController<RowingData>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();
  final _rawBytesController = StreamController<List<int>>.broadcast();
  final _adapterStateController = StreamController<BluetoothAdapterState>.broadcast();

  Stream<BleStatus> get statusStream => _statusController.stream;
  Stream<RowingData> get dataStream => _dataController.stream;
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;
  Stream<List<int>> get rawBytesStream => _rawBytesController.stream;
  Stream<BluetoothAdapterState> get adapterStateStream => _adapterStateController.stream;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BluetoothAdapterState get adapterState => _adapterState;

  BleStatus _status = BleStatus.disconnected;
  BleStatus get status => _status;

  BleService() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      debugPrint('[BLE] Adapter state: $state');
      _adapterState = state;
      _adapterStateController.add(state);
      if (state == BluetoothAdapterState.off) {
        _setStatus(BleStatus.off);
      }
    });
  }

  String? get connectedDeviceName => _device?.platformName;

  void _setStatus(BleStatus s) {
    _status = s;
    _statusController.add(s);
  }

  /// Inicia el escaneo BLE buscando dispositivos con servicio FTMS
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) return;

    // Esperar a que el adaptador Bluetooth esté encendido (máx 5 segundos)
    // En iOS la primera llamada BLE dispara el diálogo de permisos del sistema
    if (_adapterState != BluetoothAdapterState.on) {
      debugPrint('[BLE] Adaptador no listo ($_adapterState), esperando...');
      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
        debugPrint('[BLE] Adaptador listo');
      } on TimeoutException {
        debugPrint('[BLE] Timeout esperando adaptador');
        _setStatus(BleStatus.off);
        return;
      }
    }

    _setStatus(BleStatus.scanning);
    final found = <String, ScanResult>{};


    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(FtmsParser.ftmsServiceUuid)],
        timeout: timeout,
      );
      // Suscribirse DESPUÉS de startScan: la librería ya vació la lista cacheada
      // (que reemite a cada listener nuevo). Antes recibiríamos resultados del
      // escaneo anterior, por ejemplo el del pulsómetro.
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          found[r.device.remoteId.str] = r;
        }
        _devicesController.add(found.values.toList());
      });
      await Future.delayed(timeout);
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
    }
    // Solo volver a disconnected si seguimos en scanning.
    // Si el usuario ya conectó durante el scan, no sobreescribir el estado.
    if (_status == BleStatus.scanning) {
      _setStatus(BleStatus.disconnected);
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _setStatus(BleStatus.disconnected);
  }

  /// Conecta al dispositivo y suscribe al characteristic de Rower Data
  Future<void> connect(BluetoothDevice device) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setStatus(BleStatus.connecting);
    _device = device;
    _lastDevice = device; // guardar para auto-reconexión

    _isDisconnecting = false;
    try {
      await device.connect(license: _fbpLicense, autoConnect: false, timeout: const Duration(seconds: 15));
      await _discoverFtms(device);
      // Registrar el listener DESPUÉS de conectar para no capturar estados residuales.
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected && !_isDisconnecting) {
          _setStatus(BleStatus.disconnected);
          await _cleanup();
          _scheduleReconnect(); // intentar reconectar automáticamente
        }
      });
      _setStatus(BleStatus.connected);
    } catch (e) {
      _setStatus(BleStatus.disconnected);
      rethrow;
    }
  }

  /// Intenta reconectar al último dispositivo cada 3 segundos hasta lograrlo
  void _scheduleReconnect() {
    final device = _lastDevice;
    if (device == null) return;
    debugPrint('[BLE] Reconexión automática programada...');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_status == BleStatus.connected || _status == BleStatus.connecting) {
        _reconnectTimer?.cancel();
        return;
      }
      debugPrint('[BLE] Intentando reconectar a ${device.platformName}...');
      try {
        _setStatus(BleStatus.connecting);
        _device = device;
        _isDisconnecting = false;
        await device.connect(license: _fbpLicense, autoConnect: false, timeout: const Duration(seconds: 10));
        await _discoverFtms(device);
        // Registrar el listener DESPUÉS de conectar para no capturar estados residuales.
        await _connSub?.cancel();
        _connSub = device.connectionState.listen((state) async {
          if (state == BluetoothConnectionState.disconnected && !_isDisconnecting) {
            _setStatus(BleStatus.disconnected);
            await _cleanup();
            _scheduleReconnect();
          }
        });
        _setStatus(BleStatus.connected);
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        debugPrint('[BLE] Reconexión exitosa');
      } catch (e) {
        debugPrint('[BLE] Reconexión fallida: $e');
        _setStatus(BleStatus.disconnected);
        await _cleanup();
      }
    });
  }

  // Subscriptions to all notifiable characteristics for debugging
  final List<StreamSubscription<List<int>>> _allNotifySubs = [];

  Future<void> _discoverFtms(BluetoothDevice device) async {
    final services = await device.discoverServices();

    debugPrint('[BLE] ===== SERVICIOS DESCUBIERTOS =====');
    for (final service in services) {
      debugPrint('[BLE] Servicio: ${service.uuid}');
      for (final char in service.characteristics) {
        final props = <String>[];
        if (char.properties.read) props.add('READ');
        if (char.properties.write) props.add('WRITE');
        if (char.properties.notify) props.add('NOTIFY');
        if (char.properties.indicate) props.add('INDICATE');
        debugPrint('[BLE]   Char: ${char.uuid} [${props.join(',')}]');

        // Suscribirse a TODOS los que soporten notify/indicate
        if (char.properties.notify || char.properties.indicate) {
          try {
            await char.setNotifyValue(true);
            final uuid = char.uuid.toString().toUpperCase();
            final sub = char.lastValueStream.listen((bytes) {
              if (bytes.isEmpty) return;
              final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
              debugPrint('[BLE-CHAR:$uuid] len=${bytes.length} → $hex');
            });
            _allNotifySubs.add(sub);
            debugPrint('[BLE]   → Suscrito a ${char.uuid}');
          } catch (e) {
            debugPrint('[BLE]   → Error suscribiendo ${char.uuid}: $e');
          }
        }

        // Identificar el Control Point
        if (char.uuid == Guid(FtmsParser.controlPointUuid)) {
          _controlPointChar = char;
        }

        // Identificar Rower Data
        if (char.uuid == Guid(FtmsParser.rowerDataUuid)) {
          _rowerDataChar = char;
          // La suscripción para parsear se hace también
          _notifySub = char.lastValueStream.listen(_onRowerData);
        }
      }
    }

    debugPrint('[BLE] ===================================');

    if (_rowerDataChar == null) {
      debugPrint('[BLE] AVISO: No se encontró 0x2AD1 – continuando de todas formas');
    }

    // Handshake FTMS: solicitar control e iniciar sesión
    await _requestFtmsControl();
  }

  Future<void> _requestFtmsControl() async {
    final cp = _controlPointChar;
    if (cp == null) {
      debugPrint('[BLE] Control Point no encontrado, omitiendo handshake');
      return;
    }
    try {
      // Op code 0x00 = Request Control
      debugPrint('[BLE] Control Point: solicitando control (0x00)');
      await cp.write([0x00], withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 300));
      // Op code 0x07 = Start or Resume
      debugPrint('[BLE] Control Point: iniciando sesión (0x07)');
      await cp.write([0x07], withoutResponse: false);
      debugPrint('[BLE] Handshake FTMS completado');
    } catch (e) {
      debugPrint('[BLE] Control Point error (puede ser ignorado): $e');
    }

    // Keepalive: enviar 0x07 cada 2 segundos para que el monitor no salga del modo BT.
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final cp = _controlPointChar;
      if (cp == null) return;
      try {
        await cp.write([0x07], withoutResponse: false);
      } catch (e) {
        debugPrint('[BLE] Keepalive error: $e');
      }
    });
  }

  void _onRowerData(List<int> bytes) {
    if (bytes.isEmpty) return;
    debugPrint('[BLE] Raw bytes (${bytes.length}): ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _rawBytesController.add(List<int>.from(bytes));
    final parsed = FtmsParser.parseRowerData(bytes);
    if (parsed != null) {
      debugPrint('[BLE] Parsed → SPM:${parsed.strokeRate} W:${parsed.powerWatts} dist:${parsed.distanceMeters}m elapsed:${parsed.elapsedSeconds}s');
      _dataController.add(parsed);
    } else {
      debugPrint('[BLE] Parser returned null');
    }
  }

  Future<void> disconnect() async {
    _isDisconnecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lastDevice = null; // desconexión manual: no reconectar
    await _device?.disconnect();
    await _cleanup();
    _isDisconnecting = false;
    _setStatus(BleStatus.disconnected);
  }

  Future<void> _cleanup() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _notifySub?.cancel();
    await _connSub?.cancel();
    // Copiar la lista antes de iterar para evitar ConcurrentModificationError
    final subsToCancel = List<StreamSubscription<List<int>>>.from(_allNotifySubs);
    _allNotifySubs.clear();
    for (final sub in subsToCancel) {
      await sub.cancel();
    }
    _notifySub = null;
    _connSub = null;
    _rowerDataChar = null;
    _controlPointChar = null;
    _device = null;
  }

  void dispose() {
    _cleanup();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _statusController.close();
    _dataController.close();
    _devicesController.close();
    _rawBytesController.close();
    _adapterStateController.close();
  }
}
