# Simulador de remo (modo desarrollo): plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Con `--dart-define=SIMULATOR=true`, la app arranca conectada a un remo simulado que se controla desde un panel flotante, usa una base de datos separada y nunca sube nada a Strava.

**Architecture:** `SimulatedBleService implements BleService` reemplaza al servicio real en `main.dart`, así que providers y pantallas no cambian. La física vive en `RowingSimulator`, una clase pura con `tick()`. El panel se monta con `MaterialApp.builder` para quedar por encima de todas las rutas. `kSimulator` es una constante de compilación, así que en builds normales todo esto se elimina por tree-shaking.

**Tech Stack:** Flutter 3.47, Dart 3.13, provider, sqflite, flutter_blue_plus 2.x, flutter_test y fake_async.

**Spec:** `docs/superpowers/specs/2026-10-01-dev-simulator-design.md`

**Branch:** `feature/dev-simulator`

---

## Estructura de archivos

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `lib/core/dev/dev_config.dart` | Crear | Constante `kSimulator` |
| `lib/core/dev/rowing_simulator.dart` | Crear | Física del remo: estado y `tick()` → `RowingData` |
| `lib/core/bluetooth/simulated_ble_service.dart` | Crear | Implementa `BleService`: estado de conexión, timer y streams |
| `lib/core/dev/simulator_overlay.dart` | Crear | Cinta "SIMULADOR" y panel de control |
| `lib/main.dart` | Modificar | Elegir el servicio y montar el overlay |
| `lib/core/database/database_service.dart` | Modificar | Nombre de la base de datos de desarrollo |
| `lib/core/strava/strava_api_service.dart` | Modificar | Bloquear `uploadActivity` |
| `lib/features/workout/workout_screen.dart` | Modificar | Saltar `_triggerStravaUpload` (dos lugares) |
| `.vscode/launch.json` | Crear | Configuraciones de lanzamiento |
| `CLAUDE.md` | Modificar | Documentar el comando del simulador |
| `test/rowing_simulator_test.dart` | Crear | Tests de la física |
| `test/simulated_ble_service_test.dart` | Crear | Tests del servicio (fake_async) |
| `test/simulator_overlay_test.dart` | Crear | Test de widget del panel |

En esta máquina Windows, `flutter` está en `C:\Users\Usuario\dev\flutter\bin`. Si la terminal no lo encuentra, abrí una terminal nueva.

---

### Task 1: `kSimulator` y `RowingSimulator`

**Files:**
- Create: `lib/core/dev/dev_config.dart`
- Create: `lib/core/dev/rowing_simulator.dart`
- Test: `test/rowing_simulator_test.dart`

- [ ] **Step 1: Crear `dev_config.dart`**

```dart
/// Modo desarrollo con remo simulado:
///   flutter run -d windows --dart-define=SIMULATOR=true
/// Es una constante de compilación: sin el flag, el código del simulador
/// queda fuera del build por tree-shaking.
const bool kSimulator = bool.fromEnvironment('SIMULATOR');
```

- [ ] **Step 2: Escribir el test que falla**

`test/rowing_simulator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/models/rowing_data.dart';

void main() {
  group('RowingSimulator', () {
    test('más watts → pace más rápido', () {
      expect(
        RowingSimulator.paceForWatts(300),
        lessThan(RowingSimulator.paceForWatts(150)),
      );
    });

    test('203 W ≈ 2:00 /500m (fórmula Concept2)', () {
      expect(RowingSimulator.paceForWatts(203), closeTo(120, 0.5));
    });

    test('acumula distancia, remadas y tiempo mientras rema', () {
      final sim = RowingSimulator(noise: false)
        ..targetWatts = 150
        ..targetSpm = 24;
      late RowingData d;
      for (var i = 0; i < 60; i++) {
        d = sim.tick();
      }
      expect(d.powerWatts, 150);
      expect(d.strokeRate, 24);
      expect(d.pace500mSeconds, 133); // 132.67 s redondeado
      expect(d.elapsedSeconds, 60);
      expect(d.strokeCount, 24);
      expect(d.distanceMeters, 226); // 60 * 500 / 132.67
      expect(d.totalCalories, 13); // 60 * (150*4*0.8604 + 300) / 3600
      expect(d.heartRate, greaterThan(70));
    });

    test('sin remar: 0 spm/watts/pace y totales congelados', () {
      final sim = RowingSimulator(noise: false);
      for (var i = 0; i < 10; i++) {
        sim.tick();
      }
      final before = sim.tick();
      sim.rowing = false;
      final after = sim.tick();
      expect(after.strokeRate, 0);
      expect(after.powerWatts, 0);
      expect(after.pace500mSeconds, 0);
      expect(after.distanceMeters, before.distanceMeters);
      expect(after.strokeCount, before.strokeCount);
      expect(after.elapsedSeconds, before.elapsedSeconds);
      expect(after.heartRate, lessThanOrEqualTo(before.heartRate));
    });

    test('los objetivos se limitan a su rango', () {
      final sim = RowingSimulator()
        ..targetWatts = 9999
        ..targetSpm = 1;
      expect(sim.targetWatts, RowingSimulator.maxWatts);
      expect(sim.targetSpm, RowingSimulator.minSpm);
    });

    test('con ruido, los watts quedan dentro de ±5 %', () {
      final sim = RowingSimulator()..targetWatts = 200;
      for (var i = 0; i < 100; i++) {
        expect(sim.tick().powerWatts, inInclusiveRange(190, 210));
      }
    });
  });
}
```

- [ ] **Step 3: Correr el test y verificar que falla**

Run: `flutter test test/rowing_simulator_test.dart`
Expected: falla la compilación con `Error when reading 'lib/core/dev/rowing_simulator.dart'`.

- [ ] **Step 4: Implementar `RowingSimulator`**

`lib/core/dev/rowing_simulator.dart`:

```dart
import 'dart:math';
import '../models/rowing_data.dart';

/// Física simplificada de un remo para el modo simulador.
/// Cada [tick] avanza 1 segundo y devuelve la lectura que emitiría el monitor.
class RowingSimulator {
  static const minWatts = 30;
  static const maxWatts = 500;
  static const minSpm = 14;
  static const maxSpm = 40;

  RowingSimulator({Random? random, this.noise = true})
      : _random = random ?? Random();

  final Random _random;

  /// Si es false, los valores emitidos son exactamente los objetivos (para tests).
  final bool noise;

  int _targetWatts = 150;
  int get targetWatts => _targetWatts;
  set targetWatts(int v) => _targetWatts = v.clamp(minWatts, maxWatts);

  int _targetSpm = 24;
  int get targetSpm => _targetSpm;
  set targetSpm(int v) => _targetSpm = v.clamp(minSpm, maxSpm);

  /// false = el remero dejó de remar (spm/watts en 0, totales congelados)
  bool rowing = true;

  double _distance = 0;
  double _strokes = 0;
  double _calories = 0;
  double _heartRate = 70;
  int _elapsed = 0;

  RowingData tick() {
    var watts = 0;
    var spm = 0.0;
    var pace = 0;

    if (rowing) {
      watts = max(1, (targetWatts * (1 + _jitter(0.05))).round());
      spm = max(1.0, targetSpm + _jitter(1.0));
      final paceExact = paceForWatts(watts);
      pace = paceExact.round();
      _distance += 500 / paceExact;
      _strokes += spm / 60;
      _calories += caloriesPerSecond(watts);
      _elapsed++;
    }

    final targetHr = rowing ? min(190.0, 90 + watts * 0.35) : 70.0;
    _heartRate += (targetHr - _heartRate) * 0.1;

    return RowingData(
      strokeRate: double.parse(spm.toStringAsFixed(1)),
      // + 1e-6 evita que errores de punto flotante (23.9999…) resten una unidad
      strokeCount: (_strokes + 1e-6).floor(),
      distanceMeters: (_distance + 1e-6).floor(),
      pace500mSeconds: pace,
      powerWatts: watts,
      totalCalories: (_calories + 1e-6).floor(),
      heartRate: _heartRate.round(),
      elapsedSeconds: _elapsed,
    );
  }

  /// Valor aleatorio uniforme en [-amplitude, amplitude], o 0 sin ruido.
  double _jitter(double amplitude) =>
      noise ? (_random.nextDouble() * 2 - 1) * amplitude : 0;

  /// Segundos por 500 m para una potencia dada (fórmula de Concept2).
  static double paceForWatts(int watts) =>
      500 * pow(2.80 / watts, 1 / 3).toDouble();

  /// kcal por segundo para una potencia dada (fórmula de Concept2).
  static double caloriesPerSecond(int watts) =>
      (watts * 4 * 0.8604 + 300) / 3600;
}
```

- [ ] **Step 5: Correr el test y verificar que pasa**

Run: `flutter test test/rowing_simulator_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/dev/dev_config.dart lib/core/dev/rowing_simulator.dart test/rowing_simulator_test.dart
git commit -m "feat(dev): add kSimulator flag and RowingSimulator physics"
```

---

### Task 2: `SimulatedBleService`

**Files:**
- Modify: `pubspec.yaml` (agregar `fake_async` en dev_dependencies)
- Create: `lib/core/bluetooth/simulated_ble_service.dart`
- Test: `test/simulated_ble_service_test.dart`

- [ ] **Step 1: Agregar `fake_async`**

Run: `flutter pub add dev:fake_async`
Expected: `fake_async` aparece bajo `dev_dependencies` en `pubspec.yaml`. Ya era una dependencia transitiva de `flutter_test`.

- [ ] **Step 2: Escribir el test que falla**

`test/simulated_ble_service_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/models/rowing_data.dart';

void main() {
  SimulatedBleService build() =>
      SimulatedBleService(simulator: RowingSimulator(noise: false));

  test('emite connected y adapter on al primer listener, y datos cada segundo', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      final adapter = <BluetoothAdapterState>[];
      final data = <RowingData>[];
      ble.statusStream.listen(statuses.add);
      ble.adapterStateStream.listen(adapter.add);
      ble.dataStream.listen(data.add);

      async.flushMicrotasks();
      expect(statuses, [BleStatus.connected]);
      expect(adapter, [BluetoothAdapterState.on]);
      expect(ble.status, BleStatus.connected);
      expect(ble.connectedDeviceName, SimulatedBleService.deviceName);

      async.elapse(const Duration(seconds: 3));
      expect(data, hasLength(3));
      expect(data.last.distanceMeters, greaterThan(data.first.distanceMeters));

      ble.dispose();
    });
  });

  test('simulateDisconnect emite disconnected y reconecta a los 3 s', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      final data = <RowingData>[];
      ble.statusStream.listen(statuses.add);
      ble.dataStream.listen(data.add);
      async.flushMicrotasks();

      ble.simulateDisconnect();
      async.elapse(const Duration(seconds: 2));
      expect(statuses, [BleStatus.connected, BleStatus.disconnected]);
      expect(data, isEmpty, reason: 'no hay datos mientras está desconectado');

      async.elapse(const Duration(seconds: 1));
      expect(statuses, [
        BleStatus.connected,
        BleStatus.disconnected,
        BleStatus.connected,
      ]);

      ble.dispose();
    });
  });

  test('disconnect no reconecta solo; startScan reconecta', () {
    fakeAsync((async) {
      final ble = build();
      final statuses = <BleStatus>[];
      ble.statusStream.listen(statuses.add);
      async.flushMicrotasks();

      ble.disconnect();
      async.elapse(const Duration(seconds: 10));
      expect(ble.status, BleStatus.disconnected);
      expect(ble.connectedDeviceName, isNull);

      ble.startScan();
      async.flushMicrotasks();
      expect(ble.status, BleStatus.connected);
      expect(statuses.last, BleStatus.connected);

      ble.dispose();
    });
  });
}
```

- [ ] **Step 3: Correr el test y verificar que falla**

Run: `flutter test test/simulated_ble_service_test.dart`
Expected: falla la compilación con `Error when reading 'lib/core/bluetooth/simulated_ble_service.dart'`.

- [ ] **Step 4: Implementar `SimulatedBleService`**

`lib/core/bluetooth/simulated_ble_service.dart`:

```dart
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
```

- [ ] **Step 5: Correr el test y verificar que pasa**

Run: `flutter test test/simulated_ble_service_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/bluetooth/simulated_ble_service.dart test/simulated_ble_service_test.dart
git commit -m "feat(dev): add SimulatedBleService implementing BleService"
```

---

### Task 3: `SimulatorOverlay` (cinta y panel)

**Files:**
- Create: `lib/core/dev/simulator_overlay.dart`
- Test: `test/simulator_overlay_test.dart`

El overlay se monta en `MaterialApp.builder`, por encima del `Navigator`, así que **no hay `Overlay` disponible**. No usar `Tooltip` (ni el parámetro `tooltip:` de ningún widget), `Slider`, `showModalBottomSheet` ni `DropdownButton`. El test de widget reproduce ese contexto y falla si alguno de esos widgets aparece.

- [ ] **Step 1: Escribir el test que falla**

`test/simulator_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/dev/simulator_overlay.dart';

void main() {
  testWidgets('el panel se abre fuera del Navigator y + sube los watts',
      (tester) async {
    final ble = SimulatedBleService(simulator: RowingSimulator(noise: false));
    await tester.pumpWidget(
      Provider<BleService>.value(
        value: ble,
        child: MaterialApp(
          // Igual que en main.dart: por encima del Navigator.
          builder: (context, child) => SimulatorOverlay(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );

    expect(find.text('home'), findsOneWidget);
    expect(find.text('150 W'), findsNothing);

    await tester.tap(find.byIcon(Icons.build));
    await tester.pump();
    expect(find.text('150 W'), findsOneWidget);
    expect(find.text('24 spm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sim-watts-plus')));
    await tester.pump();
    expect(ble.simulator.targetWatts, 160);
    expect(find.text('160 W'), findsOneWidget);

    await tester.tap(find.text('Fuerte'));
    await tester.pump();
    expect(ble.simulator.targetWatts, 280);
    expect(ble.simulator.targetSpm, 30);

    await tester.tap(find.text('Remando'));
    await tester.pump();
    expect(ble.simulator.rowing, isFalse);

    await tester.tap(find.byKey(const Key('sim-close')));
    await tester.pump();
    expect(find.text('280 W'), findsNothing);

    ble.dispose();
  });
}
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `flutter test test/simulator_overlay_test.dart`
Expected: falla la compilación con `Error when reading 'lib/core/dev/simulator_overlay.dart'`.

- [ ] **Step 3: Implementar `SimulatorOverlay`**

`lib/core/dev/simulator_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bluetooth/ble_service.dart';
import '../bluetooth/simulated_ble_service.dart';

/// Presets de intensidad: (nombre, watts, spm)
const _presets = [
  ('Suave', 100, 20),
  ('Medio', 180, 24),
  ('Fuerte', 280, 30),
];

/// Cinta "SIMULADOR" + panel flotante para controlar el remo simulado.
/// Se monta en MaterialApp.builder (encima del Navigator): no hay Overlay,
/// así que no usar Tooltip, Slider ni bottom sheets acá.
class SimulatorOverlay extends StatefulWidget {
  const SimulatorOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<SimulatorOverlay> createState() => _SimulatorOverlayState();
}

class _SimulatorOverlayState extends State<SimulatorOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'SIMULADOR',
      location: BannerLocation.topStart,
      color: Colors.deepOrange,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            right: 16,
            bottom: 96, // por encima de la NavigationBar
            child: _open
                ? _SimulatorPanel(onClose: () => setState(() => _open = false))
                : FloatingActionButton.small(
                    heroTag: null,
                    onPressed: () => setState(() => _open = true),
                    child: const Icon(Icons.build),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SimulatorPanel extends StatefulWidget {
  const _SimulatorPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends State<_SimulatorPanel> {
  // Se lee en cada uso: tras un hot reload RowerApp crea otro servicio,
  // pero el Provider conserva el original (el que emite los datos).
  SimulatedBleService get _ble =>
      context.read<BleService>() as SimulatedBleService;

  @override
  Widget build(BuildContext context) {
    final sim = _ble.simulator;
    return Card(
      elevation: 8,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Simulador', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    key: const Key('sim-close'),
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final (name, watts, spm) in _presets)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => setState(() {
                        sim.targetWatts = watts;
                        sim.targetSpm = spm;
                      }),
                    ),
                ],
              ),
              _StepperRow(
                label: 'Watts',
                value: '${sim.targetWatts} W',
                keyPrefix: 'sim-watts',
                onMinus: () => setState(() => sim.targetWatts -= 10),
                onPlus: () => setState(() => sim.targetWatts += 10),
              ),
              _StepperRow(
                label: 'Ritmo',
                value: '${sim.targetSpm} spm',
                keyPrefix: 'sim-spm',
                onMinus: () => setState(() => sim.targetSpm -= 1),
                onPlus: () => setState(() => sim.targetSpm += 1),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remando'),
                value: sim.rowing,
                onChanged: (v) => setState(() => sim.rowing = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('Simular desconexión'),
                onPressed: () => _ble.simulateDisconnect(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.keyPrefix,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final String keyPrefix;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$keyPrefix-minus'),
          icon: const Icon(Icons.remove),
          onPressed: onMinus,
        ),
        SizedBox(
          width: 72,
          child: Text(value, textAlign: TextAlign.center),
        ),
        IconButton(
          key: Key('$keyPrefix-plus'),
          icon: const Icon(Icons.add),
          onPressed: onPlus,
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Correr el test y verificar que pasa**

Run: `flutter test test/simulator_overlay_test.dart`
Expected: `All tests passed!`. Si aparece `No Overlay widget found`, algún widget del panel usa `Overlay`: reemplazalo, no envuelvas el panel en un `Overlay`.

- [ ] **Step 5: Commit**

```bash
git add lib/core/dev/simulator_overlay.dart test/simulator_overlay_test.dart
git commit -m "feat(dev): add simulator banner and control panel overlay"
```

---

### Task 4: Conectar en `main.dart` y separar la base de datos

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/core/database/database_service.dart:9`

- [ ] **Step 1: Imports en `lib/main.dart`**

Reemplazar:

```dart
import 'core/bluetooth/ble_service.dart';
import 'core/database/database_service.dart';
```

por:

```dart
import 'core/bluetooth/ble_service.dart';
import 'core/bluetooth/simulated_ble_service.dart';
import 'core/database/database_service.dart';
import 'core/dev/dev_config.dart';
import 'core/dev/simulator_overlay.dart';
```

- [ ] **Step 2: Elegir el servicio en `RowerApp.build`**

Reemplazar:

```dart
    final ble = BleService();
```

por:

```dart
    final BleService ble = kSimulator ? SimulatedBleService() : BleService();
```

- [ ] **Step 3: Montar el overlay en `MaterialApp`**

Reemplazar:

```dart
        home: const MainShell(),
      ),
```

por:

```dart
        home: const MainShell(),
        builder: kSimulator
            ? (context, child) => SimulatorOverlay(child: child!)
            : null,
      ),
```

- [ ] **Step 4: Base de datos separada**

En `lib/core/database/database_service.dart`, agregar el import después de `import 'package:path/path.dart';`:

```dart
import '../dev/dev_config.dart';
```

y reemplazar:

```dart
  static const _dbName = 'rower_app.db';
```

por:

```dart
  // El simulador usa su propia base para no mezclar sesiones de prueba con las reales
  static const _dbName = kSimulator ? 'rower_app_dev.db' : 'rower_app.db';
```

- [ ] **Step 5: Verificar**

Run: `flutter analyze lib/main.dart lib/core/database/database_service.dart lib/core/dev lib/core/bluetooth`
Expected: sin issues de nivel `error`.

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/core/database/database_service.dart
git commit -m "feat(dev): wire simulator into app and use separate dev database"
```

---

### Task 5: Bloquear subidas a Strava en modo simulador

**Files:**
- Modify: `lib/core/strava/strava_api_service.dart` (`uploadActivity`, ~línea 74)
- Modify: `lib/features/workout/workout_screen.dart` (`_triggerStravaUpload` en ~líneas 432 y 542)

- [ ] **Step 1: Bloqueo central en `uploadActivity`**

En `lib/core/strava/strava_api_service.dart`, agregar el import después de `import 'package:http/http.dart' as http;`:

```dart
import '../dev/dev_config.dart';
```

En `uploadActivity`, reemplazar:

```dart
  }) async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      debugPrint('[Strava] Upload failed: no access token');
      return null;
    }
```

por:

```dart
  }) async {
    if (kSimulator) {
      debugPrint('[Strava] Modo simulador: subida bloqueada (sesión ${session.id})');
      return null;
    }

    final token = await _auth.getAccessToken();
    if (token == null) {
      debugPrint('[Strava] Upload failed: no access token');
      return null;
    }
```

Verificar con `grep -n "final token = await _auth.getAccessToken();" lib/core/strava/strava_api_service.dart` que el bloque reemplazado está dentro de `uploadActivity` y no en otro método.

- [ ] **Step 2: Saltar el disparo de subida en la UI**

En `lib/features/workout/workout_screen.dart`, agregar el import después de `import '../../core/strava/strava_config.dart';`:

```dart
import '../../core/dev/dev_config.dart';
```

Reemplazar:

```dart
  void _triggerStravaUpload(BuildContext context, WorkoutProvider w) {
    final profile = context.read<ProfileProvider>();
```

por:

```dart
  void _triggerStravaUpload(BuildContext context, WorkoutProvider w) {
    if (kSimulator) return; // en modo simulador no se sube nada a Strava
    final profile = context.read<ProfileProvider>();
```

y reemplazar:

```dart
  void _triggerStravaUpload(BuildContext context, WorkoutProvider w, AppLocalizations l10n) {
    final profile = context.read<ProfileProvider>();
```

por:

```dart
  void _triggerStravaUpload(BuildContext context, WorkoutProvider w, AppLocalizations l10n) {
    if (kSimulator) return; // en modo simulador no se sube nada a Strava
    final profile = context.read<ProfileProvider>();
```

- [ ] **Step 3: Verificar que no queda otro camino de subida**

Run: `grep -rn "uploadActivity(" lib`
Expected: solo la definición en `strava_api_service.dart` y las dos llamadas en `profile_provider.dart`. Las tres pasan por el bloqueo.

Run: `flutter analyze lib/core/strava lib/features/workout`
Expected: sin issues de nivel `error`.

- [ ] **Step 4: Commit**

```bash
git add lib/core/strava/strava_api_service.dart lib/features/workout/workout_screen.dart
git commit -m "feat(dev): block all Strava uploads in simulator mode"
```

---

### Task 6: Lanzamiento, documentación y verificación manual

**Files:**
- Create: `.vscode/launch.json`
- Modify: `CLAUDE.md` (sección Commands)

- [ ] **Step 1: Crear `.vscode/launch.json`**

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "RowMate",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart"
    },
    {
      "name": "RowMate (simulador)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main.dart",
      "args": ["--dart-define=SIMULATOR=true"]
    }
  ]
}
```

- [ ] **Step 2: Documentar en `CLAUDE.md`**

En el bloque de Commands, después de:

```bash
# Run on Windows desktop
flutter run -d windows
```

agregar:

```bash
# Run with simulated rower (dev mode: separate DB, Strava uploads blocked)
flutter run -d windows --dart-define=SIMULATOR=true
```

- [ ] **Step 3: Suite completa**

Run: `flutter test`
Expected: `All tests passed!`

Run: `flutter analyze`
Expected: ningún issue de nivel `error`. Los avisos previos (`withOpacity`, `dead_null_aware_expression`, etc.) se mantienen.

- [ ] **Step 4: Verificación manual en Windows**

Run: `flutter run -d windows --dart-define=SIMULATOR=true`

Comprobar:
1. Arriba a la izquierda se ve la cinta naranja "SIMULADOR".
2. La pestaña Dispositivo muestra "Remo simulado" conectado y métricas que cambian cada segundo.
3. En Entrenamiento, "Entrenamiento libre" o una rutina avanza distancia, split y watts.
4. El botón 🛠 abre el panel. "Fuerte" baja el split a unos 1:47. "Remando" apagado deja SPM y watts en 0.
5. "Simular desconexión" muestra desconectado y a los 3 s vuelve a conectar.
6. Al terminar la sesión no aparece ningún aviso ni pregunta de Strava. La sesión aparece en Historial.
7. Sin el flag (`flutter run -d windows`) no hay cinta ni botón 🛠, y el historial no muestra la sesión simulada.

- [ ] **Step 5: Commit**

```bash
git add .vscode/launch.json CLAUDE.md
git commit -m "chore(dev): add VS Code launch configs and document simulator mode"
```
