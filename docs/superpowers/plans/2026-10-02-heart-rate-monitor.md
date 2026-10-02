# Pulsómetro BLE genérico: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Conectar cualquier sensor BLE con el servicio Heart Rate (`0x180D`), mostrar el pulso en vivo, guardarlo en `data_points`, y mostrar promedio/máximo en el historial. Probable con el simulador y con un Galaxy Watch 7 + app de broadcast.

**Architecture:** `HeartRateService` (nuevo, mismo patrón que `BleService`) escanea, conecta, parsea `0x2A37` con `HeartRateParser` y reconecta con `ReconnectLoop`. `WorkoutProvider` fusiona el bpm en `RowingData.heartRate` con `copyWith`, así todo lo que ya lee `heartRate` (muestreo, TCX, gráficos, tarjetas) funciona sin cambios. `HeartRateProvider` + `HeartRateCard` son la UI en la pestaña Dispositivo. `SimulatedHeartRateService` reemplaza al servicio real con `SIMULATOR=true`.

**Tech Stack:** Flutter 3.x, flutter_blue_plus 2.3.13, provider, shared_preferences, fake_async, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-02-heart-rate-monitor-design.md`

**Rama:** `feature/heart-rate-monitor` (ya creada desde `main`).

**Comandos útiles:**
- Tests: `flutter test` (todo) o `flutter test test/<archivo>_test.dart`.
- Lint: `flutter analyze`.
- Regenerar l10n tras tocar los `.arb`: `flutter gen-l10n` (los archivos generados en `lib/l10n/app_localizations*.dart` están versionados: commitearlos).
- Correr con simulador en Windows: `flutter run -d windows --dart-define=SIMULATOR=true`.

---

## Estructura de archivos

**Crear**

| Archivo | Responsabilidad |
|---|---|
| `lib/core/bluetooth/heart_rate_parser.dart` | `HeartRateParser.parse(bytes)` → `HeartRateReading`. Puro. UUIDs del perfil. |
| `lib/core/bluetooth/reconnect_loop.dart` | `ReconnectLoop` (reintentos con intervalo y tope) y `StaleWatchdog` (timeout rearmable). Puros, con timers. |
| `lib/core/bluetooth/heart_rate_service.dart` | `HrmStatus`, `HrmIncompatibleException`, `HeartRateService` (cliente BLE real). |
| `lib/core/bluetooth/simulated_heart_rate_service.dart` | `SimulatedHeartRateService implements HeartRateService`. |
| `lib/features/device/heart_rate_provider.dart` | `HeartRateProvider` (`ChangeNotifier`) para la UI. |
| `lib/features/device/heart_rate_card.dart` | `HeartRateCard`: la tarjeta con sus estados. (El spec la llama `_HeartRateCard` dentro de `device_screen.dart`; va en archivo propio porque `device_screen.dart` ya tiene 450 líneas.) |
| `test/heart_rate_parser_test.dart` | |
| `test/reconnect_loop_test.dart` | |
| `test/simulated_heart_rate_service_test.dart` | |
| `test/workout_provider_hr_test.dart` | |
| `test/session_stats_test.dart` | |
| `test/heart_rate_provider_test.dart` | |
| `test/heart_rate_card_test.dart` | |

**Modificar**

| Archivo | Cambio |
|---|---|
| `lib/core/models/workout_session.dart` | `SessionStats.avgHeartRate`, `maxHeartRate`, `hasHeartRate`. |
| `lib/core/database/database_service.dart` | `getStatsForSessions` carga `heart_rate`. |
| `lib/core/dev/rowing_simulator.dart` | `int get heartRate`. |
| `lib/core/bluetooth/simulated_ble_service.dart` | Emite `heartRate: 0`. |
| `lib/features/workout/workout_provider.dart` | Constructor con `HeartRateService`; fusión del bpm. |
| `lib/l10n/app_es.arb`, `lib/l10n/app_en.arb` (+ generados) | Textos nuevos. |
| `lib/features/device/device_screen.dart` | Monta `HeartRateCard`; deshabilita el escaneo cruzado. |
| `lib/main.dart` | Crea y registra `HeartRateService`, `HeartRateProvider`; nuevo constructor de `WorkoutProvider`. |
| `lib/core/dev/simulator_overlay.dart` | Botón "Simular caída del pulsómetro". |
| `lib/features/history/history_screen.dart`, `session_detail_screen.dart` | Chip de pulso. |
| `lib/core/bluetooth/ble_service.dart` | Arreglo del listener de escaneo. |
| `test/rowing_simulator_test.dart`, `test/simulated_ble_service_test.dart`, `test/simulator_overlay_test.dart` | Ajustes. |
| `CLAUDE.md` | Documentar los componentes nuevos. |

---

### Task 1: `HeartRateParser`

**Files:**
- Create: `lib/core/bluetooth/heart_rate_parser.dart`
- Test: `test/heart_rate_parser_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
// test/heart_rate_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/heart_rate_parser.dart';

void main() {
  test('bpm en uint8 sin información de contacto', () {
    final r = HeartRateParser.parse([0x00, 72])!;
    expect(r.bpm, 72);
    expect(r.sensorContact, isNull);
  });

  test('bpm en uint16 little-endian', () {
    final r = HeartRateParser.parse([0x01, 0x2C, 0x01])!; // 0x012C = 300
    expect(r.bpm, 300);
  });

  test('bits de contacto: 01 = no soportado, 10 = sin contacto, 11 = con contacto', () {
    expect(HeartRateParser.parse([0x02, 70])!.sensorContact, isNull);
    expect(HeartRateParser.parse([0x04, 0])!.sensorContact, isFalse);
    expect(HeartRateParser.parse([0x06, 65])!.sensorContact, isTrue);
    expect(HeartRateParser.parse([0x06, 65])!.bpm, 65);
  });

  test('ignora Energy Expended y RR intervals', () {
    // flags 0x18 = bit3 (energía) + bit4 (RR); bpm 80; energía 0x0010; RR 0x0400
    final r = HeartRateParser.parse([0x18, 80, 0x10, 0x00, 0x00, 0x04])!;
    expect(r.bpm, 80);
  });

  test('bytes vacíos o truncados devuelven null', () {
    expect(HeartRateParser.parse([]), isNull);
    expect(HeartRateParser.parse([0x00]), isNull);
    expect(HeartRateParser.parse([0x01, 72]), isNull, reason: 'uint16 necesita 3 bytes');
  });

  test('UUIDs del perfil', () {
    expect(HeartRateParser.serviceUuid, '0000180d-0000-1000-8000-00805f9b34fb');
    expect(HeartRateParser.measurementUuid, '00002a37-0000-1000-8000-00805f9b34fb');
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/heart_rate_parser_test.dart`
Expected: error de compilación "Target of URI doesn't exist: 'package:rowmate/core/bluetooth/heart_rate_parser.dart'".

- [ ] **Step 3: Implementar el parser**

```dart
// lib/core/bluetooth/heart_rate_parser.dart
import 'dart:typed_data';

/// Lectura del characteristic Heart Rate Measurement (0x2A37).
class HeartRateReading {
  final int bpm;

  /// null = el sensor no informa contacto; false = sin contacto; true = con contacto.
  final bool? sensorContact;

  const HeartRateReading({required this.bpm, this.sensorContact});
}

/// Parser del Heart Rate Profile (Bluetooth SIG).
///
/// Byte 0 = flags:
///   Bit 0    – formato del bpm: 0 = uint8 (byte 1), 1 = uint16 LE (bytes 1-2)
///   Bits 1-2 – contacto del sensor: 0b0x = no soportado, 0b10 = sin contacto, 0b11 = con contacto
///   Bit 3    – Energy Expended presente (uint16), se ignora
///   Bit 4    – intervalos RR presentes (uint16 cada uno), se ignoran
class HeartRateParser {
  static const String serviceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String measurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  static HeartRateReading? parse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final is16 = (flags & 0x01) != 0;
    if (bytes.length < (is16 ? 3 : 2)) return null;

    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final bpm = is16 ? data.getUint16(1, Endian.little) : data.getUint8(1);

    final contactBits = (flags >> 1) & 0x03;
    final bool? contact = switch (contactBits) {
      2 => false,
      3 => true,
      _ => null,
    };
    return HeartRateReading(bpm: bpm, sensorContact: contact);
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/heart_rate_parser_test.dart`
Expected: `All tests passed!` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/bluetooth/heart_rate_parser.dart test/heart_rate_parser_test.dart
git commit -m "feat(hrm): add HeartRateParser for 0x2A37 measurements"
```

---

### Task 2: `SessionStats` con pulso promedio y máximo

**Files:**
- Modify: `lib/core/models/workout_session.dart` (clase `SessionStats`)
- Modify: `lib/core/database/database_service.dart` (`getStatsForSessions`, ~línea 289)
- Test: `test/session_stats_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
// test/session_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/workout_session.dart';

DataPoint _p(int hr) => DataPoint(sessionId: 1, elapsedSeconds: 0, heartRate: hr);

void main() {
  test('avgHeartRate y maxHeartRate ignoran los ceros', () {
    final s = SessionStats.compute([_p(0), _p(120), _p(150), _p(0), _p(141)]);
    expect(s.avgHeartRate, 137); // (120 + 150 + 141) / 3
    expect(s.maxHeartRate, 150);
    expect(s.hasHeartRate, isTrue);
  });

  test('sin pulso quedan en 0', () {
    final s = SessionStats.compute([_p(0), _p(0)]);
    expect(s.avgHeartRate, 0);
    expect(s.maxHeartRate, 0);
    expect(s.hasHeartRate, isFalse);
  });

  test('sin puntos quedan en 0', () {
    expect(SessionStats.compute(const []).hasHeartRate, isFalse);
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/session_stats_test.dart`
Expected: error "The getter 'avgHeartRate' isn't defined for the type 'SessionStats'".

- [ ] **Step 3: Agregar los campos a `SessionStats`**

En `lib/core/models/workout_session.dart`, dentro de `class SessionStats`:

```dart
  final int totalCalories;
  final int avgHeartRate; // bpm, media de los puntos con pulso > 0 (0 si no hubo)
  final int maxHeartRate; // bpm (0 si no hubo)

  const SessionStats({
    this.p99Watts = 0,
    this.p99Spm = 0,
    this.p99SplitSeconds = 0,
    this.totalDistance = 0,
    this.totalTimeSeconds = 0,
    this.totalCalories = 0,
    this.avgHeartRate = 0,
    this.maxHeartRate = 0,
  });

  bool get hasHeartRate => maxHeartRate > 0;
```

Y en `compute`, después de `final splits = ...`:

```dart
    final hrs = points.map((p) => p.heartRate).where((v) => v > 0).toList();

    return SessionStats(
      p99Watts: _percentile99(watts).round(),
      p99Spm: _percentile99(spms),
      p99SplitSeconds: _percentile99(splits).round(),
      totalDistance: points.map((p) => p.distanceMeters).reduce((a, b) => a > b ? a : b),
      totalTimeSeconds: points.map((p) => p.elapsedSeconds).reduce((a, b) => a > b ? a : b),
      totalCalories: points.map((p) => p.calories).reduce((a, b) => a > b ? a : b),
      avgHeartRate: hrs.isEmpty ? 0 : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
      maxHeartRate: hrs.isEmpty ? 0 : hrs.reduce((a, b) => a > b ? a : b),
    );
```

- [ ] **Step 4: Cargar `heart_rate` en `getStatsForSessions`**

En `lib/core/database/database_service.dart`, en `getStatsForSessions`:

```dart
      columns: [
        'session_id', 'power_watts', 'stroke_rate',
        'pace_500m_seconds', 'distance_meters', 'elapsed_seconds', 'calories',
        'heart_rate',
      ],
```

y al construir el `DataPoint`:

```dart
        calories: row['calories'] as int,
        heartRate: row['heart_rate'] as int? ?? 0,
      ));
```

- [ ] **Step 5: Correr el test y verificar que pasa**

Run: `flutter test test/session_stats_test.dart`
Expected: `All tests passed!` (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/models/workout_session.dart lib/core/database/database_service.dart test/session_stats_test.dart
git commit -m "feat(hrm): average and max heart rate in SessionStats"
```

---

### Task 3: `ReconnectLoop` y `StaleWatchdog`

**Files:**
- Create: `lib/core/bluetooth/reconnect_loop.dart`
- Test: `test/reconnect_loop_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
// test/reconnect_loop_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/reconnect_loop.dart';

void main() {
  group('ReconnectLoop', () {
    test('intenta de inmediato, reintenta cada intervalo y para al tener éxito', () {
      fakeAsync((async) {
        var calls = 0;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 3),
          attempt: () async => ++calls >= 3,
        );
        loop.start();
        async.flushMicrotasks();
        expect(calls, 1);
        expect(loop.isRunning, isTrue);

        async.elapse(const Duration(seconds: 3));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 3));
        expect(calls, 3);
        expect(loop.isRunning, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(calls, 3, reason: 'no sigue intentando tras el éxito');
      });
    });

    test('se rinde tras maxAttempts y avisa', () {
      fakeAsync((async) {
        var calls = 0;
        var gaveUp = false;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 10),
          maxAttempts: 3,
          attempt: () async {
            calls++;
            return false;
          },
          onGiveUp: () => gaveUp = true,
        );
        loop.start();
        async.elapse(const Duration(seconds: 25));
        expect(calls, 3);
        expect(gaveUp, isTrue);
        expect(loop.isRunning, isFalse);
        async.elapse(const Duration(seconds: 60));
        expect(calls, 3);
      });
    });

    test('cancel frena los reintentos y una excepción cuenta como fallo', () {
      fakeAsync((async) {
        var calls = 0;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 1),
          attempt: () async {
            calls++;
            throw StateError('sin BT');
          },
        );
        loop.start();
        async.elapse(const Duration(seconds: 2));
        expect(calls, 3);
        loop.cancel();
        expect(loop.isRunning, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(calls, 3);
      });
    });
  });

  group('StaleWatchdog', () {
    test('dispara tras el timeout sin touch, y touch lo rearma', () {
      fakeAsync((async) {
        var stale = 0;
        final w = StaleWatchdog(timeout: const Duration(seconds: 10), onStale: () => stale++);
        w.touch();
        async.elapse(const Duration(seconds: 9));
        w.touch();
        async.elapse(const Duration(seconds: 9));
        expect(stale, 0);
        async.elapse(const Duration(seconds: 1));
        expect(stale, 1);
        async.elapse(const Duration(seconds: 30));
        expect(stale, 1, reason: 'dispara una sola vez por touch');
        w.touch();
        w.stop();
        async.elapse(const Duration(seconds: 30));
        expect(stale, 1);
      });
    });
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/reconnect_loop_test.dart`
Expected: "Target of URI doesn't exist".

- [ ] **Step 3: Implementar**

```dart
// lib/core/bluetooth/reconnect_loop.dart
import 'dart:async';

/// Reintenta [attempt] hasta que devuelva true, se agoten [maxAttempts]
/// (null = sin límite) o se llame a [cancel]. El primer intento es inmediato
/// al llamar a [start]; los siguientes esperan [interval] tras cada fallo.
/// Una excepción en [attempt] cuenta como fallo.
class ReconnectLoop {
  ReconnectLoop({
    required this.interval,
    required this.attempt,
    this.maxAttempts,
    this.onGiveUp,
  });

  final Duration interval;
  final Future<bool> Function() attempt;
  final int? maxAttempts;
  final void Function()? onGiveUp;

  Timer? _timer;
  int _attempts = 0;
  bool _running = false;
  bool _busy = false;

  bool get isRunning => _running;
  int get attempts => _attempts;

  void start() {
    cancel();
    _running = true;
    _attempts = 0;
    _tryOnce();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _tryOnce() async {
    if (!_running || _busy) return;
    _busy = true;
    _attempts++;
    var ok = false;
    try {
      ok = await attempt();
    } catch (_) {
      ok = false;
    } finally {
      _busy = false;
    }
    if (!_running) return; // cancelado mientras intentaba
    if (ok) {
      _running = false;
      return;
    }
    final max = maxAttempts;
    if (max != null && _attempts >= max) {
      _running = false;
      onGiveUp?.call();
      return;
    }
    _timer = Timer(interval, _tryOnce);
  }
}

/// Llama a [onStale] si pasan [timeout] sin un [touch]. Cada [touch] rearma
/// el plazo; [stop] lo desactiva.
class StaleWatchdog {
  StaleWatchdog({required this.timeout, required this.onStale});

  final Duration timeout;
  final void Function() onStale;
  Timer? _timer;

  void touch() {
    _timer?.cancel();
    _timer = Timer(timeout, onStale);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/reconnect_loop_test.dart`
Expected: `All tests passed!` (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/bluetooth/reconnect_loop.dart test/reconnect_loop_test.dart
git commit -m "feat(hrm): ReconnectLoop and StaleWatchdog helpers"
```

---

### Task 4: `HeartRateService` (cliente BLE real)

No tiene tests unitarios: depende de `FlutterBluePlus` estático, igual que `BleService`. Se verifica con `flutter analyze` y con el reloj.

**Files:**
- Create: `lib/core/bluetooth/heart_rate_service.dart`

- [ ] **Step 1: Escribir el servicio**

```dart
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
  /// la UI no permite escanear ambos a la vez.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (!await FlutterBluePlus.isSupported) return;
    _setStatus(HrmStatus.scanning);
    _devicesController.add(const []);
    final found = <String, ScanResult>{};
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(HeartRateParser.serviceUuid)],
        timeout: timeout,
      );
      // Suscribirse DESPUÉS de startScan: la librería ya vació la lista cacheada
      // (que reemite a cada listener nuevo). Antes recibiríamos el escaneo anterior.
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          found[r.device.remoteId.str] = r;
        }
        _devicesController.add(found.values.toList());
      });
      await Future.delayed(timeout);
    } catch (e) {
      debugPrint('[HRM] Error escaneando: $e');
      rethrow;
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
      if (_status == HrmStatus.scanning) _setStatus(HrmStatus.disconnected);
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
    _startupLoop.cancel();
    _dropLoop.cancel();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    await _connectTo(device);
  }

  /// Al arrancar la app: reconectar al sensor recordado sin escanear.
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
    _bpmController.add(value);
  }

  // ── Desconexión ──────────────────────────────────────────────────────────

  /// Desconexión manual: corta reintentos, desconecta y olvida el sensor
  /// (si no, la reconexión automática lo volvería a enganchar).
  Future<void> disconnect() async {
    _startupLoop.cancel();
    _dropLoop.cancel();
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
    _startupLoop.cancel();
    _dropLoop.cancel();
    _rememberedId = null;
    _rememberedName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefDeviceId);
    await prefs.remove(prefDeviceName);
    _reemitStatus();
  }

  void _cleanupConnection() {
    _watchdog.stop();
    _notifySub?.cancel();
    _notifySub = null;
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
    _statusController.add(s);
  }

  /// Reemite el estado actual para que la UI relea `isRetrying` / `rememberedDeviceName`.
  void _reemitStatus() => _statusController.add(_status);

  void dispose() {
    _startupLoop.cancel();
    _dropLoop.cancel();
    _watchdog.stop();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _statusController.close();
    _bpmController.close();
    _devicesController.close();
  }
}
```

- [ ] **Step 2: Analizar**

Run: `flutter analyze lib/core/bluetooth/heart_rate_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/bluetooth/heart_rate_service.dart
git commit -m "feat(hrm): HeartRateService BLE client with auto-reconnect"
```

---

### Task 5: El remo simulado deja de emitir pulso

**Files:**
- Modify: `lib/core/dev/rowing_simulator.dart`
- Modify: `lib/core/bluetooth/simulated_ble_service.dart` (`_connect`)
- Test: `test/rowing_simulator_test.dart`, `test/simulated_ble_service_test.dart`

- [ ] **Step 1: Agregar los tests que fallan**

Al final de `main()` en `test/rowing_simulator_test.dart`:

```dart
  test('heartRate expone el último pulso calculado por tick()', () {
    final sim = RowingSimulator(noise: false);
    final d = sim.tick();
    expect(sim.heartRate, d.heartRate);
    expect(sim.heartRate, greaterThan(70));
  });
```

En `test/simulated_ble_service_test.dart`, en el primer test, después de `expect(data, hasLength(3));`:

```dart
      expect(data.every((d) => d.heartRate == 0), isTrue,
          reason: 'el pulso llega solo por el pulsómetro simulado');
```

- [ ] **Step 2: Correr y verificar que fallan**

Run: `flutter test test/rowing_simulator_test.dart test/simulated_ble_service_test.dart`
Expected: el primero no compila ("The getter 'heartRate' isn't defined for the type 'RowingSimulator'"); el segundo falla en el `every`.

- [ ] **Step 3: Implementar**

En `lib/core/dev/rowing_simulator.dart`, después de `bool rowing = true;`:

```dart
  /// Último pulso calculado por [tick] (bpm). Lo emite el pulsómetro simulado.
  int get heartRate => _heartRate.round();
```

En `lib/core/bluetooth/simulated_ble_service.dart`, en `_connect()`:

```dart
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Como el monitor real: el pulso no viene por FTMS sino por el pulsómetro.
      _dataController.add(simulator.tick().copyWith(heartRate: 0));
    });
```

- [ ] **Step 4: Correr y verificar que pasan**

Run: `flutter test test/rowing_simulator_test.dart test/simulated_ble_service_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/dev/rowing_simulator.dart lib/core/bluetooth/simulated_ble_service.dart test/rowing_simulator_test.dart test/simulated_ble_service_test.dart
git commit -m "feat(sim): expose simulator heart rate; simulated rower sends none over FTMS"
```

---

### Task 6: `SimulatedHeartRateService`

**Files:**
- Create: `lib/core/bluetooth/simulated_heart_rate_service.dart`
- Test: `test/simulated_heart_rate_service_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
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
      expect(bpm.last, 0, reason: 'al caer se emite 0');
      async.elapse(const Duration(seconds: 2));
      expect(statuses, [HrmStatus.connected, HrmStatus.disconnected]);
      async.elapse(const Duration(seconds: 1));
      expect(statuses.last, HrmStatus.connected);
      expect(hrm.isRetrying, isFalse);

      hrm.disconnect();
      async.elapse(const Duration(seconds: 10));
      expect(hrm.status, HrmStatus.disconnected);
      expect(hrm.connectedDeviceName, isNull);

      hrm.dispose();
    });
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `flutter test test/simulated_heart_rate_service_test.dart`
Expected: "Target of URI doesn't exist".

- [ ] **Step 3: Implementar**

```dart
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
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `flutter test test/simulated_heart_rate_service_test.dart`
Expected: `All tests passed!` (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/bluetooth/simulated_heart_rate_service.dart test/simulated_heart_rate_service_test.dart
git commit -m "feat(sim): SimulatedHeartRateService"
```

---

### Task 7: Fusión del pulso en `WorkoutProvider`

**Files:**
- Modify: `lib/features/workout/workout_provider.dart`
- Modify: `lib/main.dart` (solo la línea del constructor, para que compile; el resto del cableado va en Task 11)
- Test: `test/workout_provider_hr_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
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
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `flutter test test/workout_provider_hr_test.dart`
Expected: "Too many positional arguments: 2 expected, but 3 found" en `WorkoutProvider(ble, hrm, DatabaseService())`.

- [ ] **Step 3: Implementar la fusión**

En `lib/features/workout/workout_provider.dart`:

Import nuevo (junto al de `ble_service.dart`):

```dart
import '../../core/bluetooth/heart_rate_service.dart';
```

Campos y constructor (reemplazar `final BleService _ble;` … `WorkoutProvider(this._ble, this._db) { ... }`):

```dart
  final BleService _ble;
  final HeartRateService _hrm;
  final DatabaseService _db;

  WorkoutPhase _phase = WorkoutPhase.idle;
  RowingData _data = const RowingData();
  // ... (resto de campos sin cambios)

  Timer? _timer;
  StreamSubscription<RowingData>? _dataSub;
  StreamSubscription<int>? _hrmBpmSub;
  StreamSubscription<HrmStatus>? _hrmStatusSub;

  /// Último bpm del pulsómetro. null = sensor no conectado (se respeta el FTMS);
  /// 0 = conectado pero sin lectura válida.
  int? _hrmBpm;

  WorkoutProvider(this._ble, this._hrm, this._db) {
    _dataSub = _ble.dataStream.listen(_onData);
    _hrmBpmSub = _hrm.bpmStream.listen(_onHrmBpm);
    _hrmStatusSub = _hrm.statusStream.listen(_onHrmStatus);
  }
```

Handlers (reemplazar `_onData`):

```dart
  void _onData(RowingData d) {
    // El pulsómetro manda sobre el pulso que (rara vez) manda el monitor por FTMS.
    _data = d.copyWith(heartRate: _hrmBpm ?? d.heartRate);
    notifyListeners();
  }

  void _onHrmBpm(int bpm) {
    _hrmBpm = bpm;
    _data = _data.copyWith(heartRate: bpm);
    notifyListeners();
  }

  void _onHrmStatus(HrmStatus s) {
    if (s == HrmStatus.connected || _hrmBpm == null) return;
    _hrmBpm = null;
    _data = _data.copyWith(heartRate: 0);
    notifyListeners();
  }
```

`dispose`:

```dart
  @override
  void dispose() {
    _timer?.cancel();
    _dataSub?.cancel();
    _hrmBpmSub?.cancel();
    _hrmStatusSub?.cancel();
    super.dispose();
  }
```

En `lib/main.dart`, para que compile hasta la Task 11, crear el servicio y pasarlo (el resto del cableado se completa después):

```dart
import 'core/bluetooth/heart_rate_service.dart';
import 'core/bluetooth/simulated_heart_rate_service.dart';
```

```dart
    final BleService ble = kSimulator ? SimulatedBleService() : BleService();
    final HeartRateService hrm = kSimulator
        ? SimulatedHeartRateService((ble as SimulatedBleService).simulator)
        : HeartRateService();
```

```dart
        ChangeNotifierProvider(create: (_) => WorkoutProvider(ble, hrm, db)),
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `flutter test test/workout_provider_hr_test.dart && flutter analyze`
Expected: `All tests passed!` (2 tests) y `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/workout/workout_provider.dart lib/main.dart test/workout_provider_hr_test.dart
git commit -m "feat(hrm): merge heart rate monitor bpm into WorkoutProvider data"
```

---

### Task 8: Textos l10n

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`
- Regenerar: `lib/l10n/app_localizations*.dart`

- [ ] **Step 1: Agregar las claves**

En `lib/l10n/app_en.arb`, después de `"deviceBtEnable": "Enable Bluetooth",`:

```json
  "hrmTitle": "Heart rate sensor",
  "hrmNoSensor": "No sensor",
  "hrmWatchHint": "A smartwatch needs an app that broadcasts heart rate over Bluetooth (e.g. Heart for Bluetooth on Wear OS).",
  "hrmSearch": "Search",
  "hrmSearchOther": "Search another",
  "hrmSearching": "Searching sensors…",
  "hrmConnectingTo": "Connecting to {name}…",
  "@hrmConnectingTo": {
    "placeholders": {
      "name": { "type": "String" }
    }
  },
  "hrmConnect": "Connect",
  "hrmDisconnect": "Disconnect",
  "hrmForget": "Forget",
  "hrmReconnecting": "reconnecting…",
  "hrmNotFound": "not found",
  "hrmUnknownSensor": "Unknown sensor",
  "hrmIncompatible": "Not a compatible heart rate sensor (no Heart Rate service)",
  "hrmConnectError": "Connection error: {error}",
  "@hrmConnectError": {
    "placeholders": {
      "error": { "type": "String" }
    }
  },
  "hrmBpm": "bpm",
```

Y después de `"historyStatCalories": "kcal",`:

```json
  "historyStatHeartRate": "HR",
```

En `lib/l10n/app_es.arb`, en las mismas posiciones:

```json
  "hrmTitle": "Pulsómetro",
  "hrmNoSensor": "Sin sensor",
  "hrmWatchHint": "Un smartwatch necesita una app que transmita el pulso por Bluetooth (p. ej. Heart for Bluetooth en Wear OS).",
  "hrmSearch": "Buscar",
  "hrmSearchOther": "Buscar otro",
  "hrmSearching": "Buscando sensores…",
  "hrmConnectingTo": "Conectando a {name}…",
  "@hrmConnectingTo": {
    "placeholders": {
      "name": { "type": "String" }
    }
  },
  "hrmConnect": "Conectar",
  "hrmDisconnect": "Desconectar",
  "hrmForget": "Olvidar",
  "hrmReconnecting": "reconectando…",
  "hrmNotFound": "no encontrado",
  "hrmUnknownSensor": "Sensor desconocido",
  "hrmIncompatible": "No es un pulsómetro compatible (sin servicio Heart Rate)",
  "hrmConnectError": "Error al conectar: {error}",
  "@hrmConnectError": {
    "placeholders": {
      "error": { "type": "String" }
    }
  },
  "hrmBpm": "bpm",
```

```json
  "historyStatHeartRate": "Pulso",
```

- [ ] **Step 2: Regenerar y verificar**

Run: `flutter gen-l10n && grep -c "hrm" lib/l10n/app_localizations_es.dart`
Expected: sin errores; el `grep` devuelve un número ≥ 17.

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/l10n/
git commit -m "feat(hrm): l10n strings for the heart rate sensor card"
```

---

### Task 9: `HeartRateProvider`

**Files:**
- Create: `lib/features/device/heart_rate_provider.dart`
- Test: `test/heart_rate_provider_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
// test/heart_rate_provider_test.dart
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
    });
  });

  test('errorText distingue el sensor incompatible', () {
    const incompatible = HrmIncompatibleException();
    expect(HeartRateProvider.isIncompatible(incompatible), isTrue);
    expect(HeartRateProvider.isIncompatible(StateError('x')), isFalse);
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `flutter test test/heart_rate_provider_test.dart`
Expected: "Target of URI doesn't exist".

- [ ] **Step 3: Implementar**

```dart
// lib/features/device/heart_rate_provider.dart
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
    try {
      await _hrm.startScan();
    } catch (e) {
      _error = e;
      notifyListeners();
    }
  }

  Future<void> connect(BluetoothDevice device, {String? name}) async {
    _error = null;
    _connectingName = name;
    notifyListeners();
    try {
      await _hrm.connect(device);
    } catch (e) {
      _error = e;
      notifyListeners();
    }
  }

  /// Reintenta con el sensor recordado (misma cadencia que al arrancar).
  Future<void> retry() async {
    _error = null;
    _connectingName = null;
    notifyListeners();
    await _hrm.autoConnect();
  }

  Future<void> disconnect() => _hrm.disconnect();

  Future<void> forget() async {
    await _hrm.forget();
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _bpmSub?.cancel();
    _devicesSub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Correr y verificar que pasa**

Run: `flutter test test/heart_rate_provider_test.dart`
Expected: `All tests passed!` (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/device/heart_rate_provider.dart test/heart_rate_provider_test.dart
git commit -m "feat(hrm): HeartRateProvider"
```

---

### Task 10: `HeartRateCard` y montaje en `DeviceScreen`

**Files:**
- Create: `lib/features/device/heart_rate_card.dart`
- Modify: `lib/features/device/device_screen.dart` (`_ConnectedViewState.build`, `_ScanView.build`)
- Test: `test/heart_rate_card_test.dart`

- [ ] **Step 1: Escribir el test que falla**

```dart
// test/heart_rate_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/features/device/device_provider.dart';
import 'package:rowmate/features/device/device_screen.dart';
import 'package:rowmate/features/device/heart_rate_provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Services = ({
  RowingSimulator sim,
  SimulatedBleService ble,
  SimulatedHeartRateService hrm,
});

Future<_Services> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final sim = RowingSimulator(noise: false);
  final ble = SimulatedBleService(simulator: sim);
  final hrm = SimulatedHeartRateService(sim);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<BleService>.value(value: ble),
        Provider<HeartRateService>.value(value: hrm),
        ChangeNotifierProvider(create: (_) => DeviceProvider(ble)),
        ChangeNotifierProvider(create: (_) => HeartRateProvider(hrm)),
      ],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DeviceScreen(),
      ),
    ),
  );
  await tester.pump(); // el remo simulado se conecta en un microtask
  return (sim: sim, ble: ble, hrm: hrm);
}

Future<void> _teardown(WidgetTester tester, _Services s) async {
  await tester.pumpWidget(const SizedBox()); // dispone los providers
  s.ble.dispose();
  s.hrm.dispose();
}

void main() {
  testWidgets('sin sensor → buscar → conectar → bpm → desconectar', (tester) async {
    final s = await _pump(tester);

    // Vista conectada del remo + tarjeta en "sin sensor"
    expect(find.text('PULSÓMETRO'), findsOneWidget);
    expect(find.text('Sin sensor'), findsOneWidget);
    expect(find.textContaining('Heart for Bluetooth'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hrm-search')));
    await tester.pump();
    expect(find.text('Buscando sensores…'), findsOneWidget);
    expect(find.text('Pulsómetro simulado'), findsOneWidget);

    await tester.tap(find.text('Pulsómetro simulado'));
    await tester.pump();
    expect(s.hrm.status, HrmStatus.connected);
    expect(find.text('Pulsómetro simulado'), findsOneWidget);
    expect(find.text('--'), findsOneWidget, reason: 'todavía sin lectura');

    s.sim.tick();
    await tester.pump(const Duration(seconds: 1));
    // Se compara con el bpm que emitió el servicio (el remo simulado también
    // hace tick() en ese segundo, así que sim.heartRate puede ir un paso adelante).
    expect(s.hrm.bpm, greaterThan(0));
    expect(find.text('${s.hrm.bpm}'), findsOneWidget);
    expect(find.text('--'), findsNothing);

    await tester.tap(find.byKey(const Key('hrm-disconnect')));
    await tester.pump();
    expect(find.text('Sin sensor'), findsOneWidget);

    await _teardown(tester, s);
  });

  testWidgets('los escaneos del remo y del pulsómetro se excluyen', (tester) async {
    final s = await _pump(tester);

    await s.ble.disconnect(); // pasa a la vista de escaneo del remo
    await tester.pump();
    final rowerSearch = find.widgetWithText(FilledButton, 'Buscar dispositivos');
    expect(rowerSearch, findsOneWidget);
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('hrm-search')));
    await tester.pump();
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNull,
        reason: 'mientras el pulsómetro escanea no se puede escanear el remo');

    await s.hrm.stopScan();
    await tester.pump();
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNotNull);

    await _teardown(tester, s);
  });
}
```

- [ ] **Step 2: Correr y verificar que falla**

Run: `flutter test test/heart_rate_card_test.dart`
Expected: falla en `find.text('PULSÓMETRO')` (la tarjeta no existe todavía).

- [ ] **Step 3: Crear la tarjeta**

```dart
// lib/features/device/heart_rate_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import '../../core/bluetooth/ble_service.dart';
import '../../core/bluetooth/heart_rate_service.dart';
import '../../shared/theme.dart';
import 'device_provider.dart';
import 'heart_rate_provider.dart';

/// Tarjeta "Pulsómetro" de la pestaña Dispositivo: buscar, conectar,
/// ver el pulso en vivo y desconectar/olvidar el sensor recordado.
class HeartRateCard extends StatelessWidget {
  const HeartRateCard({super.key});

  static const _color = MetricColors.heartRate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hr = context.watch<HeartRateProvider>();
    final rowerStatus = context.select<DeviceProvider, BleStatus>((p) => p.status);
    final rowerBusy =
        rowerStatus == BleStatus.scanning || rowerStatus == BleStatus.connecting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E45),
        borderRadius: BorderRadius.circular(16),
        border: Border(top: BorderSide(color: _color.withOpacity(0.6), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite,
                  size: 14, color: hr.isConnected ? _color : _color.withOpacity(0.4)),
              const SizedBox(width: 6),
              Text(l10n.hrmTitle.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      color: _color.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          _body(hr, l10n, rowerBusy),
          if (hr.error != null) ...[
            const SizedBox(height: 8),
            Text(
              HeartRateProvider.isIncompatible(hr.error!)
                  ? l10n.hrmIncompatible
                  : l10n.hrmConnectError('${hr.error}'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    switch (hr.status) {
      case HrmStatus.connected:
        return _connected(hr, l10n);
      case HrmStatus.connecting:
        return Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.hrmConnectingTo(hr.connectingName))),
          ],
        );
      case HrmStatus.scanning:
        return _scanning(hr, l10n);
      case HrmStatus.disconnected:
        return hr.hasRemembered
            ? _remembered(hr, l10n, rowerBusy)
            : _noSensor(hr, l10n, rowerBusy);
    }
  }

  Widget _noSensor(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.hrmNoSensor,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(l10n.hrmWatchHint,
            style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const Key('hrm-search'),
          onPressed: rowerBusy ? null : hr.startScan,
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: Text(l10n.hrmSearch),
        ),
      ],
    );
  }

  Widget _scanning(HeartRateProvider hr, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(l10n.hrmSearching,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        for (final r in hr.scanResults)
          ListTile(
            key: Key('hrm-device-${r.device.remoteId.str}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.favorite_border, color: _color),
            title: Text(_nameOf(r, l10n)),
            subtitle: Text(r.device.remoteId.str,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => hr.connect(r.device, name: _nameOf(r, l10n)),
          ),
      ],
    );
  }

  Widget _connected(HeartRateProvider hr, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hr.connectedDeviceName ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(hr.bpm > 0 ? '${hr.bpm}' : '--',
                      style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w800,
                          color: _color,
                          height: 1)),
                  const SizedBox(width: 6),
                  Text(l10n.hrmBpm,
                      style: TextStyle(fontSize: 14, color: _color.withOpacity(0.7))),
                ],
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('hrm-disconnect'),
          onPressed: hr.disconnect,
          icon: const Icon(Icons.bluetooth_disabled, size: 18),
          label: Text(l10n.hrmDisconnect),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
        ),
      ],
    );
  }

  Widget _remembered(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    final suffix = hr.isRetrying ? l10n.hrmReconnecting : l10n.hrmNotFound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${hr.rememberedDeviceName} · $suffix',
            style: const TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const Key('hrm-retry'),
              onPressed: hr.isRetrying || rowerBusy ? null : hr.retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.hrmConnect),
            ),
            OutlinedButton(
              key: const Key('hrm-search'),
              onPressed: rowerBusy ? null : hr.startScan,
              child: Text(l10n.hrmSearchOther),
            ),
            TextButton(
              key: const Key('hrm-forget'),
              onPressed: hr.forget,
              child: Text(l10n.hrmForget),
            ),
          ],
        ),
      ],
    );
  }

  static String _nameOf(ScanResult r, AppLocalizations l10n) {
    final n = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : r.advertisementData.advName;
    return n.isNotEmpty ? n : l10n.hrmUnknownSensor;
  }
}
```

- [ ] **Step 4: Montar la tarjeta en `device_screen.dart`**

Import:

```dart
import 'heart_rate_card.dart';
import 'heart_rate_provider.dart';
```

En `_ConnectedViewState.build`, reemplazar

```dart
          _LiveMetricsGrid(p: p),
          const SizedBox(height: 32),
```

por

```dart
          _LiveMetricsGrid(p: p),
          const SizedBox(height: 12),
          const HeartRateCard(),
          const SizedBox(height: 32),
```

En `_ScanView.build`, al principio del método (después de `final btUnauthorized = ...`):

```dart
    final hrmScanning = context.select<HeartRateProvider, bool>((h) => h.isScanning);
```

El botón de buscar remo:

```dart
            FilledButton.icon(
              onPressed: isScanning || isConnecting || hrmScanning ? null : p.startScan,
```

Y al final del spread `else ...[`, después del bloque `if (p.scanResults.isNotEmpty) Expanded(...)`, agregar como últimos elementos del spread (dentro de los `]` del `else`):

```dart
            const SizedBox(height: 12),
            const HeartRateCard(),
```

Así la tarjeta no aparece cuando se muestra la pantalla de "Bluetooth apagado".

- [ ] **Step 5: Correr y verificar que pasa**

Run: `flutter test test/heart_rate_card_test.dart && flutter analyze`
Expected: `All tests passed!` (2 tests) y `No issues found!`

Si el primer test falla en `find.text('${s.hrm.bpm}')` porque el bpm coincide con otro número en pantalla (improbable: la grilla del remo no muestra pulso), usar `find.descendant(of: find.byType(HeartRateCard), matching: find.text(...))`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/device/heart_rate_card.dart lib/features/device/device_screen.dart test/heart_rate_card_test.dart
git commit -m "feat(hrm): heart rate sensor card in the Device tab"
```

---

### Task 11: Cableado en `main.dart` y botón del simulador

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/core/dev/simulator_overlay.dart`
- Test: `test/simulator_overlay_test.dart`

- [ ] **Step 1: Actualizar el test del overlay (falla)**

En `test/simulator_overlay_test.dart`, imports:

```dart
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
```

En el test principal, crear el servicio y proveerlo:

```dart
    final ble = SimulatedBleService(simulator: RowingSimulator(noise: false));
    final hrm = SimulatedHeartRateService(ble.simulator);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BleService>.value(value: ble),
          Provider<HeartRateService>.value(value: hrm),
          ChangeNotifierProvider(create: (_) => SceneSettings()),
        ],
```

Después de `await tester.tap(find.text('Simular desconexión')); ... expect(tester.takeException(), isNull);`:

```dart
    await tester.tap(find.text('Simular caída del pulsómetro'));
    await tester.pump();
    expect(tester.takeException(), isNull);
```

Y al final, junto a `ble.dispose();`:

```dart
    hrm.dispose();
```

Hacer el mismo cambio de providers (`hrm` + `Provider<HeartRateService>.value`) y el `hrm.dispose()` en `_shortWindowTest`.

Run: `flutter test test/simulator_overlay_test.dart`
Expected: falla en `find.text('Simular caída del pulsómetro')`.

- [ ] **Step 2: Botón en el panel**

En `lib/core/dev/simulator_overlay.dart`, imports:

```dart
import '../bluetooth/heart_rate_service.dart';
import '../bluetooth/simulated_heart_rate_service.dart';
```

En `_SimulatorPanelState`, junto al getter `_ble`:

```dart
  SimulatedHeartRateService get _hrm =>
      context.read<HeartRateService>() as SimulatedHeartRateService;
```

Después del `OutlinedButton.icon` de "Simular desconexión":

```dart
              OutlinedButton.icon(
                icon: const Icon(Icons.heart_broken),
                label: const Text('Simular caída del pulsómetro'),
                onPressed: () => _hrm.simulateDisconnect(),
              ),
```

- [ ] **Step 3: Cableado completo en `main.dart`**

En la lista de `providers`, después del `Provider<DatabaseService>`:

```dart
        Provider<HeartRateService>(
          // lazy: false → create corre al arrancar aunque nadie lea el servicio
          // del árbol (los providers lo reciben por closure). Sin esto,
          // autoConnect() nunca se ejecutaría en producción.
          lazy: false,
          create: (_) {
            unawaited(hrm.autoConnect().catchError(
                (Object e) => debugPrint('[HRM] autoConnect: $e')));
            return hrm;
          },
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => DeviceProvider(ble)),
        ChangeNotifierProvider(create: (_) => HeartRateProvider(hrm)),
        ChangeNotifierProvider(create: (_) => WorkoutProvider(ble, hrm, db)),
```

Import:

```dart
import 'features/device/heart_rate_provider.dart';
```

- [ ] **Step 4: Verificar**

Run: `flutter test test/simulator_overlay_test.dart && flutter analyze`
Expected: `All tests passed!` y `No issues found!`

Run (humo manual, opcional en Windows): `flutter run -d windows --dart-define=SIMULATOR=true`. En Dispositivo: tarjeta "PULSÓMETRO · Sin sensor" → Buscar → "Pulsómetro simulado" → conectado con bpm. Panel 🛠 → "Simular caída del pulsómetro" → la tarjeta pasa a "Sin sensor" y vuelve sola a los 3 s. En Workout, la tarjeta BPM aparece con el sensor conectado.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/core/dev/simulator_overlay.dart test/simulator_overlay_test.dart
git commit -m "feat(hrm): wire HeartRateService and provider; simulator HRM drop button"
```

---

### Task 12: Chip de pulso en historial y detalle

**Files:**
- Modify: `lib/features/history/history_screen.dart` (`_SessionCard.build`, Row de stats)
- Modify: `lib/features/history/session_detail_screen.dart` (`_buildSummary`)

- [ ] **Step 1: Historial**

En `_SessionCard.build`, en el `Row` de stats, después del `_Stat` de `Split`:

```dart
                  if (stats.hasHeartRate)
                    _Stat(
                      label: l10n.historyStatHeartRate,
                      value: '${stats.avgHeartRate}/${stats.maxHeartRate}',
                      color: MetricColors.heartRate,
                    ),
```

(El spec dice "avg · max"; se usa `/` porque la fila ya tiene 5 columnas y en un teléfono de 360 px "137 · 150" no entra en 14 px bold.)

- [ ] **Step 2: Detalle**

En `_buildSummary`, en el `Row` de `_StatChip`, después del de `Split`:

```dart
                if (stats.hasHeartRate)
                  _StatChip(
                    label: l10n.historyStatHeartRate,
                    value: '${stats.avgHeartRate}/${stats.maxHeartRate}',
                    color: MetricColors.heartRate,
                  ),
```

- [ ] **Step 3: Verificar**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` y `All tests passed!`

Humo manual con simulador: terminar un entrenamiento corto con el pulsómetro simulado conectado; en Historial la tarjeta muestra "Pulso 1xx/1xx"; en el detalle también, y el gráfico "bpm" tiene datos.

- [ ] **Step 4: Commit**

```bash
git add lib/features/history/history_screen.dart lib/features/history/session_detail_screen.dart
git commit -m "feat(hrm): avg/max heart rate chip in history and session detail"
```

---

### Task 13: Arreglo del listener de escaneo en `BleService`

**Files:**
- Modify: `lib/core/bluetooth/ble_service.dart` (`startScan`, `stopScan`, `dispose`)

- [ ] **Step 1: Cambiar `startScan`**

Campo nuevo, junto a los otros `StreamSubscription`:

```dart
  StreamSubscription<List<ScanResult>>? _scanSub;
```

Reemplazar desde `_setStatus(BleStatus.scanning);` hasta el final de `startScan` por:

```dart
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
```

`stopScan`:

```dart
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _setStatus(BleStatus.disconnected);
  }
```

En `dispose()`, antes de `_adapterSub?.cancel();`:

```dart
    _scanSub?.cancel();
```

- [ ] **Step 2: Verificar**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` y `All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/bluetooth/ble_service.dart
git commit -m "fix(ble): cancel scan listener after each scan and subscribe after startScan"
```

---

### Task 14: Documentación

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Documentar en `CLAUDE.md`**

En "Core Layer", después del bullet de `FtmsParser`:

```markdown
- **[HeartRateService](lib/core/bluetooth/heart_rate_service.dart)**: generic BLE client for Heart Rate Profile sensors (service `0x180D`, characteristic `0x2A37`, parsed by [HeartRateParser](lib/core/bluetooth/heart_rate_parser.dart)). Independent from `BleService`: the phone holds two GATT connections. Emits `Stream<HrmStatus>` and `Stream<int>` (bpm; `0` = no valid reading, also after 10 s without notifications). Remembers the last sensor in SharedPreferences (`hrm.deviceId` / `hrm.deviceName`) and reconnects with [ReconnectLoop](lib/core/bluetooth/reconnect_loop.dart): on app start every 10 s for 1 minute (`autoConnect()`), after a drop every 3 s until manual `disconnect()` (which also forgets the sensor). Scans cannot run concurrently with the rower scan (`flutter_blue_plus` stops the previous one), so the Device tab disables one while the other scans. A Galaxy/Apple Watch needs a broadcaster app (e.g. *Heart for Bluetooth* on Wear OS) to expose `0x180D`.
```

En "Feature Layer", bullet `device/`:

```markdown
- **device/**: BLE scan results and connection state for the rower (`DeviceProvider`) plus the heart rate sensor card (`HeartRateProvider`, [heart_rate_card.dart](lib/features/device/heart_rate_card.dart)).
```

En "Data Flow", después del párrafo del flujo BLE:

```markdown
Heart rate: `HeartRateService.bpmStream` → `WorkoutProvider` merges it into `_data` with `copyWith(heartRate:)` (the sensor overrides the FTMS heart-rate field; when the sensor disconnects the field goes back to 0 until the next FTMS packet). Everything downstream (`data_points`, TCX, charts, metric cards, `SessionStats.avgHeartRate/maxHeartRate`) just reads `RowingData.heartRate`.
```

En "Dev Mode: Simulated Rower", después del bullet de `SimulatedBleService`:

```markdown
- **[SimulatedHeartRateService](lib/core/bluetooth/simulated_heart_rate_service.dart)** `implements HeartRateService`; shares the `RowingSimulator`. The simulated rower sends `heartRate: 0` over FTMS so the pulse only arrives through the simulated sensor. `startScan()` lists one synthetic "Pulsómetro simulado"; `autoConnect()` does nothing (nothing is persisted); `simulateDisconnect()` drops and reconnects after 3 s (panel button "Simular caída del pulsómetro").
```

- [ ] **Step 2: Verificación final completa**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` y `All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: heart rate monitor architecture notes"
```

---

## Prueba con el Galaxy Watch 7 (manual, fuera del plan automatizado)

1. En el reloj instalar una app de broadcast BLE (p. ej. *Heart for Bluetooth*) y activar la transmisión.
2. `flutter run` en el teléfono Android. Pestaña Dispositivo → tarjeta Pulsómetro → **Buscar** → aparece el reloj → tocar → bpm en vivo.
3. Cerrar y reabrir la app: debe reconectar sola (estado "reconectando…" y luego conectado).
4. Apagar la transmisión en el reloj: a los ~10 s el bpm pasa a "--"; al cortarse la conexión la tarjeta pasa a "reconectando…" y vuelve cuando se reactiva.
5. Hacer un entrenamiento corto; verificar la tarjeta BPM en la pantalla inmersiva, el chip "Pulso" en Historial y el detalle, y (si Strava está configurado) que el TCX subido tenga pulso.
