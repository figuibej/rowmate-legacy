# Parciales de 500 m y comparación de series: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En la pantalla inmersiva, mostrar vueltas de 500 m por paso de trabajo, los metros de la repetición actual, las últimas 3 repeticiones de la serie (en paneles colapsables, colapsados por defecto) y la hora actual.

**Architecture:** `Routine.flattenedStepPositions` indica a qué repetición de qué serie pertenece cada paso aplanado. `SeriesTracker` es una clase pura que recibe una lectura por segundo desde `WorkoutProvider._tick` y calcula vueltas y repeticiones. `series_panels.dart` tiene los widgets (`WallClock`, `SeriesPanels`) y la pantalla inmersiva los monta.

**Tech Stack:** Flutter 3.47, provider, shared_preferences, intl, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-02-series-splits-design.md`

**Branch:** `feature/immersive-dev-simulator`

Flutter no está en el PATH de las shells de agentes: usar `C:\Users\Usuario\dev\flutter\bin\flutter.bat`.

---

## Estructura de archivos

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `lib/core/models/routine.dart` | Modificar | `StepPosition` y `flattenedStepPositions` |
| `lib/features/workout/series_tracker.dart` | Crear | `Lap`, `RepSummary`, `SeriesTracker` (lógica pura) |
| `lib/features/workout/workout_provider.dart` | Modificar | Alimentar el tracker y exponerlo |
| `lib/features/workout/series_panels.dart` | Crear | `WallClock`, `SeriesPanels` y sus formatos |
| `lib/features/workout/immersive_workout_screen.dart` | Modificar | Montar la hora y los paneles |
| `test/routine_positions_test.dart` | Crear | Tests de `flattenedStepPositions` |
| `test/series_tracker_test.dart` | Crear | Tests del tracker |
| `test/series_panels_test.dart` | Crear | Tests de widget de los paneles |

---

### Task 1: `Routine.flattenedStepPositions`

**Files:** Modify `lib/core/models/routine.dart`; Test `test/routine_positions_test.dart`

- [ ] **Step 1: Test que falla**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/core/models/routine.dart';

void main() {
  test('las posiciones quedan alineadas con flattenedSteps', () {
    final routine = Routine(
      name: 't',
      createdAt: DateTime(2026),
      steps: const [
        IntervalStep(routineId: 1, order: 0, type: StepType.warmup, durationSeconds: 300),
        IntervalStep(routineId: 1, order: 1, type: StepType.work, distanceMeters: 500, groupId: 'a', groupRepeatCount: 3),
        IntervalStep(routineId: 1, order: 2, type: StepType.cooldown, durationSeconds: 60, groupId: 'a', groupRepeatCount: 3),
        IntervalStep(routineId: 1, order: 3, type: StepType.cooldown, durationSeconds: 300),
      ],
    );

    final positions = routine.flattenedStepPositions;
    expect(positions, hasLength(routine.flattenedSteps.length));
    expect(positions, hasLength(8));
    expect(positions[0], (groupId: null, rep: 1, repCount: 1));
    expect(positions[1], (groupId: 'a', rep: 1, repCount: 3));
    expect(positions[2], (groupId: 'a', rep: 1, repCount: 3));
    expect(positions[3], (groupId: 'a', rep: 2, repCount: 3));
    expect(positions[6], (groupId: 'a', rep: 3, repCount: 3));
    expect(positions[7], (groupId: null, rep: 1, repCount: 1));
  });
}
```

Run: `flutter test test/routine_positions_test.dart`. Expected: falla porque `flattenedStepPositions` no está definido.

- [ ] **Step 2: Implementar**

En `lib/core/models/routine.dart`, agregar después del `import`:

```dart

/// Posición de un paso aplanado dentro de su serie: grupo, repetición (desde 1)
/// y cantidad total de repeticiones. Un paso suelto da (null, 1, 1).
typedef StepPosition = ({String? groupId, int rep, int repCount});
```

Y dentro de la clase `Routine`, justo después del getter `flattenedSteps`:

```dart
  /// Posiciones alineadas índice por índice con [flattenedSteps]:
  /// indica a qué repetición de qué serie pertenece cada paso.
  List<StepPosition> get flattenedStepPositions {
    final result = <StepPosition>[];
    var i = 0;
    while (i < steps.length) {
      final gid = steps[i].groupId;
      if (gid == null) {
        result.add((groupId: null, rep: 1, repCount: 1));
        i++;
        continue;
      }
      final repeat = steps[i].groupRepeatCount ?? 1;
      var size = 0;
      while (i < steps.length && steps[i].groupId == gid) {
        size++;
        i++;
      }
      for (var r = 1; r <= repeat; r++) {
        for (var k = 0; k < size; k++) {
          result.add((groupId: gid, rep: r, repCount: repeat));
        }
      }
    }
    return result;
  }
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/routine_positions_test.dart`. Expected: PASS.

```bash
git add lib/core/models/routine.dart test/routine_positions_test.dart
git commit -m "feat(workout): add Routine.flattenedStepPositions"
```

---

### Task 2: `SeriesTracker`

**Files:** Create `lib/features/workout/series_tracker.dart`; Test `test/series_tracker_test.dart`

- [ ] **Step 1: Tests que fallan**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/core/models/routine.dart';
import 'package:rowmate/features/workout/series_tracker.dart';

const _g = 'g1';

IntervalStep _work(int meters, {String? group = _g}) => IntervalStep(
    routineId: 1, order: 0, type: StepType.work, distanceMeters: meters,
    groupId: group, groupRepeatCount: 5);

IntervalStep _cool(int seconds, {String? group = _g}) => IntervalStep(
    routineId: 1, order: 1, type: StepType.cooldown, durationSeconds: seconds,
    groupId: group, groupRepeatCount: 5);

StepPosition _pos(int rep, {String? group = _g}) =>
    (groupId: group, rep: rep, repCount: group == null ? 1 : 5);

/// Simula lecturas de 1 s a velocidad constante, como WorkoutProvider._tick.
class _Feeder {
  _Feeder(this.tracker) {
    tracker.begin(0);
  }
  final SeriesTracker tracker;
  int t = 0;
  double d = 0;

  void run(int stepIndex, IntervalStep step, StepPosition pos,
      {required int seconds, required double speed}) {
    for (var i = 0; i < seconds; i++) {
      t++;
      d += speed;
      tracker.update(
        stepIndex: stepIndex,
        step: step,
        position: pos,
        distanceMeters: d.floor(),
        elapsedSeconds: t,
      );
    }
  }
}

void main() {
  test('interpola el tiempo de la vuelta entre lecturas', () {
    final f = _Feeder(SeriesTracker());
    // 3 m/s: 498 m en t=166 y 501 m en t=167 → cruza 500 m en 166.67 s
    f.run(0, _work(1000), _pos(1), seconds: 170, speed: 3);
    final t = f.tracker;
    expect(t.laps, hasLength(1));
    expect(t.laps.first.number, 1);
    expect(t.laps.first.seconds, closeTo(166.67, 0.01));
    expect(t.currentLapMeters, 10); // 510 - 500
    expect(t.currentLapSeconds, closeTo(3.33, 0.01));
    expect(t.isWorkStep, isTrue);
  });

  test('dos vueltas dentro del mismo paso', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(2000), _pos(1), seconds: 220, speed: 5);
    expect(f.tracker.laps.map((l) => l.seconds), [100, 100]);
  });

  test('un paso de trabajo de menos de 500 m no genera vueltas', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(400), _pos(1), seconds: 80, speed: 5);
    expect(f.tracker.laps, isEmpty);
  });

  test('el enfriamiento no genera vueltas pero suma metros a la repetición', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _cool(60), _pos(1), seconds: 60, speed: 2);
    final t = f.tracker;
    expect(t.isWorkStep, isFalse);
    expect(t.laps, isEmpty);
    expect(t.currentLapMeters, 0);
    expect(t.inSeries, isTrue);
    expect(t.rep, 1);
    expect(t.repCount, 5);
    expect(t.repMeters, 620);
  });

  test('al cambiar de repetición guarda el resumen de la anterior', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _cool(60), _pos(1), seconds: 60, speed: 2);
    f.run(2, _work(500), _pos(2), seconds: 10, speed: 5);
    final t = f.tracker;
    expect(t.rep, 2);
    expect(t.repMeters, 50);
    expect(t.previousReps, hasLength(1));
    final r = t.previousReps.first;
    expect(r.rep, 1);
    expect(r.totalMeters, 620);
    expect(r.workMeters, 500);
    expect(r.workSeconds, 100);
    expect(r.workSplitSeconds, closeTo(100, 0.001));
  });

  test('guarda solo las últimas 3 repeticiones, la más reciente primero', () {
    final f = _Feeder(SeriesTracker());
    for (var rep = 1; rep <= 5; rep++) {
      f.run((rep - 1) * 2, _work(500), _pos(rep), seconds: 100, speed: 5);
      f.run((rep - 1) * 2 + 1, _cool(10), _pos(rep), seconds: 10, speed: 2);
    }
    expect(f.tracker.rep, 5);
    expect(f.tracker.previousReps.map((r) => r.rep), [4, 3, 2]);
  });

  test('una serie nueva o un paso suelto vacían la comparación', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _work(500), _pos(2), seconds: 10, speed: 5);
    expect(f.tracker.previousReps, hasLength(1));

    f.run(2, _work(500, group: 'g2'), _pos(1, group: 'g2'), seconds: 10, speed: 5);
    expect(f.tracker.previousReps, isEmpty);

    f.run(3, _cool(60, group: null), _pos(1, group: null), seconds: 10, speed: 2);
    expect(f.tracker.inSeries, isFalse);
    expect(f.tracker.previousReps, isEmpty);
  });

  test('una repetición sin metros de trabajo no tiene split', () {
    const r = RepSummary(rep: 1, totalMeters: 100, workMeters: 0, workSeconds: 0);
    expect(r.workSplitSeconds, isNull);
  });
}
```

Run: `flutter test test/series_tracker_test.dart`. Expected: falla porque el archivo no existe.

- [ ] **Step 2: Implementar `lib/features/workout/series_tracker.dart`**

```dart
import '../../core/models/interval_step.dart';
import '../../core/models/routine.dart';

/// Vuelta de 500 m completada dentro de un paso de trabajo.
class Lap {
  const Lap(this.number, this.seconds);

  /// 1, 2, 3… dentro del paso.
  final int number;

  /// Tiempo en remar esos 500 m.
  final double seconds;
}

/// Resumen de una repetición completa de la serie.
class RepSummary {
  const RepSummary({
    required this.rep,
    required this.totalMeters,
    required this.workMeters,
    required this.workSeconds,
  });

  final int rep;

  /// Metros de todos los pasos de la repetición (trabajo + enfriamiento…).
  final int totalMeters;
  final int workMeters;
  final double workSeconds;

  /// Split promedio de trabajo en s/500m, o null si no hubo metros de trabajo.
  double? get workSplitSeconds =>
      workMeters > 0 ? workSeconds / workMeters * 500 : null;
}

/// Lleva las vueltas de 500 m de los pasos de trabajo y los totales de cada
/// repetición de la serie en curso. WorkoutProvider lo alimenta una vez por
/// segundo con la distancia del monitor y los segundos activos (sin pausas).
class SeriesTracker {
  static const lapMeters = 500;
  static const maxPreviousReps = 3;

  // Última lectura
  double _lastDistance = 0;
  double _lastTime = 0;

  int? _stepIndex;
  StepPosition? _position;
  bool _isWork = false;

  // Paso actual
  double _stepStartDistance = 0;
  double _lastLapEndTime = 0;
  final List<Lap> _laps = [];

  // Repetición actual
  double _repStartDistance = 0;
  double _repWorkMeters = 0;
  double _repWorkSeconds = 0;
  final List<RepSummary> _previousReps = []; // la más reciente primero

  List<Lap> get laps => List.unmodifiable(_laps);
  bool get isWorkStep => _isWork;

  /// Metros recorridos en la vuelta en curso (0 fuera de pasos de trabajo).
  int get currentLapMeters => _isWork
      ? ((_lastDistance - _stepStartDistance) - _laps.length * lapMeters).floor()
      : 0;

  /// Segundos de la vuelta en curso (0 fuera de pasos de trabajo).
  double get currentLapSeconds => _isWork ? _lastTime - _lastLapEndTime : 0;

  bool get inSeries => _position?.groupId != null;
  int get rep => _position?.rep ?? 0;
  int get repCount => _position?.repCount ?? 0;
  int get repMeters => (_lastDistance - _repStartDistance).floor();
  List<RepSummary> get previousReps => List.unmodifiable(_previousReps);

  /// Reinicia todo. [distanceMeters] es la distancia del monitor al iniciar.
  void begin(int distanceMeters) {
    _lastDistance = distanceMeters.toDouble();
    _lastTime = 0;
    _stepIndex = null;
    _position = null;
    _isWork = false;
    _stepStartDistance = _lastDistance;
    _lastLapEndTime = 0;
    _laps.clear();
    _repStartDistance = _lastDistance;
    _repWorkMeters = 0;
    _repWorkSeconds = 0;
    _previousReps.clear();
  }

  /// Registra una lectura del paso [stepIndex].
  void update({
    required int stepIndex,
    required IntervalStep step,
    required StepPosition position,
    required int distanceMeters,
    required int elapsedSeconds,
  }) {
    if (stepIndex != _stepIndex) _enterStep(stepIndex, step, position);

    final d = distanceMeters.toDouble();
    final t = elapsedSeconds.toDouble();
    final dd = d - _lastDistance;
    final dt = t - _lastTime;

    if (_isWork) {
      if (dd > 0) _repWorkMeters += dd;
      _repWorkSeconds += dt;
      // Puede completarse más de una vuelta en una lectura
      while (d - _stepStartDistance >= (_laps.length + 1) * lapMeters) {
        final target = _stepStartDistance + (_laps.length + 1) * lapMeters;
        // Interpolación lineal del instante en que se cruzó la marca
        final crossTime =
            dd > 0 ? _lastTime + (target - _lastDistance) / dd * dt : t;
        _laps.add(Lap(_laps.length + 1, crossTime - _lastLapEndTime));
        _lastLapEndTime = crossTime;
      }
    }

    _lastDistance = d;
    _lastTime = t;
  }

  void _enterStep(int stepIndex, IntervalStep step, StepPosition position) {
    final prev = _position;
    final isNewRep = prev == null ||
        position.groupId != prev.groupId ||
        position.rep != prev.rep;

    if (isNewRep) {
      final sameSeries =
          prev != null && prev.groupId != null && position.groupId == prev.groupId;
      if (sameSeries) {
        _previousReps.insert(
          0,
          RepSummary(
            rep: prev.rep,
            totalMeters: (_lastDistance - _repStartDistance).floor(),
            workMeters: _repWorkMeters.floor(),
            workSeconds: _repWorkSeconds,
          ),
        );
        if (_previousReps.length > maxPreviousReps) _previousReps.removeLast();
      } else {
        // La comparación es dentro de la serie en curso
        _previousReps.clear();
      }
      _repStartDistance = _lastDistance;
      _repWorkMeters = 0;
      _repWorkSeconds = 0;
    }

    _stepIndex = stepIndex;
    _position = position;
    _isWork = step.type == StepType.work;
    _stepStartDistance = _lastDistance;
    _lastLapEndTime = _lastTime;
    _laps.clear();
  }
}
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/series_tracker_test.dart`. Expected: PASS (8 tests).

```bash
git add lib/features/workout/series_tracker.dart test/series_tracker_test.dart
git commit -m "feat(workout): add SeriesTracker for 500m laps and rep summaries"
```

---

### Task 3: Alimentar el tracker desde `WorkoutProvider`

**Files:** Modify `lib/features/workout/workout_provider.dart`

- [ ] **Step 1: Import y campos**

Agregar `import 'series_tracker.dart';` después de `import '../../core/models/workout_session.dart';`.

En la clase, después de `int _distanceAtStepStart = 0;`:

```dart
  // Parciales de 500 m y repeticiones de la serie (solo en memoria)
  final SeriesTracker _series = SeriesTracker();
  List<StepPosition> _stepPositions = const [];
```

Después del getter `int get totalElapsedSeconds => _totalElapsedSeconds;`:

```dart
  SeriesTracker get series => _series;
```

- [ ] **Step 2: Iniciar en `startWithRoutine`**

En `startWithRoutine`, después de `_distanceAtStepStart = _data.distanceMeters;`:

```dart
    _stepPositions = routine.flattenedStepPositions;
    _series.begin(_data.distanceMeters);
```

`routine` es el parámetro original, sin aplanar. Es correcto: `flattenedStepPositions` aplana por su cuenta.

- [ ] **Step 3: Actualizar en `_tick`**

Reemplazar:

```dart
    // Avanza al siguiente paso si se cumplió el objetivo
    if (_routine != null) {
      _checkStepCompletion();
    }
```

por:

```dart
    // Avanza al siguiente paso si se cumplió el objetivo
    if (_routine != null) {
      // Antes de avanzar: esta lectura pertenece al paso actual
      _series.update(
        stepIndex: _currentStepIndex,
        step: _routine!.steps[_currentStepIndex],
        position: _stepPositions[_currentStepIndex],
        distanceMeters: _data.distanceMeters,
        elapsedSeconds: _totalElapsedSeconds,
      );
      _checkStepCompletion();
    }
```

- [ ] **Step 4: Limpiar en `reset`**

En `reset()`, antes de `notifyListeners();`:

```dart
    _stepPositions = const [];
    _series.begin(0);
```

- [ ] **Step 5: Verificar y commitear**

Run: `flutter analyze lib/features/workout lib/core/models`. Expected: ningún issue nuevo de nivel `error` o `warning` en las líneas tocadas.
Run: `flutter test`. Expected: todo pasa.

```bash
git add lib/features/workout/workout_provider.dart
git commit -m "feat(workout): feed SeriesTracker from WorkoutProvider tick"
```

---

### Task 4: Widgets `WallClock` y `SeriesPanels`

**Files:** Create `lib/features/workout/series_panels.dart`; Test `test/series_panels_test.dart`

- [ ] **Step 1: Tests que fallan**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/features/workout/series_panels.dart';
import 'package:rowmate/features/workout/series_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _work = IntervalStep(
    routineId: 1, order: 0, type: StepType.work, distanceMeters: 1000,
    groupId: 'g', groupRepeatCount: 3);

SeriesTracker _trackerAt300m({String? group = 'g'}) {
  final t = SeriesTracker()..begin(0);
  t.update(
    stepIndex: 0,
    step: _work,
    position: (groupId: group, rep: 1, repCount: group == null ? 1 : 3),
    distanceMeters: 300,
    elapsedSeconds: 60,
  );
  return t;
}

Future<void> _pump(WidgetTester tester, SeriesTracker t) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SeriesPanels(tracker: t)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('formatos', () {
    expect(formatLapTime(166.667), '2:46.7');
    expect(formatLapTime(65), '1:05.0');
    expect(formatSplit(114.4), '1:54');
    expect(formatMeters(1245), '1.245 m');
  });

  testWidgets('arrancan colapsados y al tocar se expanden y se recuerda',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, _trackerAt300m());

    expect(find.text('Parciales 500 m'), findsNothing);
    expect(find.text('Series anteriores'), findsNothing);
    expect(find.text('500 m'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);

    await tester.tap(find.text('500 m'));
    await tester.pumpAndSettle();
    expect(find.text('Parciales 500 m'), findsOneWidget);
    expect(find.text('Rep 1/3 · 300 m'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SeriesPanels.lapsKey), isTrue);

    await tester.tap(find.text('Reps'));
    await tester.pumpAndSettle();
    expect(find.text('Sin repeticiones completas'), findsOneWidget);
  });

  testWidgets('respeta la preferencia guardada', (tester) async {
    SharedPreferences.setMockInitialValues({SeriesPanels.lapsKey: true});
    await _pump(tester, _trackerAt300m());
    expect(find.text('Parciales 500 m'), findsOneWidget);
  });

  testWidgets('sin serie no aparece el panel de repeticiones', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, _trackerAt300m(group: null));
    expect(find.text('500 m'), findsOneWidget);
    expect(find.text('Reps'), findsNothing);
  });
}
```

Run: `flutter test test/series_panels_test.dart`. Expected: falla porque el archivo no existe.

- [ ] **Step 2: Implementar `lib/features/workout/series_panels.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'series_tracker.dart';

/// m:ss.d — tiempo de una vuelta.
String formatLapTime(double seconds) {
  final tenths = (seconds * 10).round();
  final m = tenths ~/ 600;
  final s = (tenths % 600) / 10;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

/// m:ss — split redondeado al segundo.
String formatSplit(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// "1.245 m"
String formatMeters(int meters) =>
    '${NumberFormat('#,##0', 'es').format(meters)} m';

BoxDecoration _glass() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    );

const _textStyle = TextStyle(
  color: Colors.white,
  fontSize: 13,
  fontFeatures: [FontFeature.tabularFigures()],
);
const _mutedStyle = TextStyle(color: Colors.white54, fontSize: 12);

/// Hora actual (HH:mm). Tiene su propio timer: sigue andando en pausa.
class WallClock extends StatefulWidget {
  const WallClock({super.key});

  @override
  State<WallClock> createState() => _WallClockState();
}

class _WallClockState extends State<WallClock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: _glass(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            DateFormat('HH:mm').format(_now),
            style: _textStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Paneles colapsables de parciales de 500 m y repeticiones anteriores.
/// Colapsados por defecto; el estado se recuerda entre sesiones.
class SeriesPanels extends StatefulWidget {
  const SeriesPanels({super.key, required this.tracker});

  final SeriesTracker tracker;

  static const lapsKey = 'immersive.lapsExpanded';
  static const repsKey = 'immersive.repsExpanded';

  @override
  State<SeriesPanels> createState() => _SeriesPanelsState();
}

class _SeriesPanelsState extends State<SeriesPanels> {
  bool _lapsExpanded = false;
  bool _repsExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _lapsExpanded = prefs.getBool(SeriesPanels.lapsKey) ?? false;
      _repsExpanded = prefs.getBool(SeriesPanels.repsKey) ?? false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracker;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsiblePanel(
          icon: Icons.timer_outlined,
          collapsedLabel: '500 m',
          title: 'Parciales 500 m',
          expanded: _lapsExpanded,
          onToggle: () {
            setState(() => _lapsExpanded = !_lapsExpanded);
            _save(SeriesPanels.lapsKey, _lapsExpanded);
          },
          child: _LapsContent(tracker: t),
        ),
        if (t.inSeries) ...[
          const SizedBox(height: 8),
          _CollapsiblePanel(
            icon: Icons.history,
            collapsedLabel: 'Reps',
            title: 'Series anteriores',
            expanded: _repsExpanded,
            onToggle: () {
              setState(() => _repsExpanded = !_repsExpanded);
              _save(SeriesPanels.repsKey, _repsExpanded);
            },
            child: _RepsContent(tracker: t),
          ),
        ],
      ],
    );
  }
}

class _CollapsiblePanel extends StatelessWidget {
  const _CollapsiblePanel({
    required this.icon,
    required this.collapsedLabel,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final String collapsedLabel;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: expanded ? 180 : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: _glass(),
        child: expanded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(title,
                            style: _textStyle.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const Icon(Icons.expand_less, size: 16, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(collapsedLabel, style: _textStyle),
                ],
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.left, this.right, {this.dim = false});

  final String left;
  final String right;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final style = dim ? _textStyle.copyWith(color: Colors.white60) : _textStyle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
      ),
    );
  }
}

class _LapsContent extends StatelessWidget {
  const _LapsContent({required this.tracker});

  final SeriesTracker tracker;

  @override
  Widget build(BuildContext context) {
    final t = tracker;
    final laps = t.laps;
    final shown = laps.length > 4 ? laps.sublist(laps.length - 4) : laps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!t.isWorkStep)
          const Text('Sin parciales en este paso', style: _mutedStyle)
        else ...[
          for (final lap in shown)
            _Row('#${lap.number}', formatLapTime(lap.seconds)),
          _Row('▸ ${t.currentLapMeters} m', formatLapTime(t.currentLapSeconds),
              dim: true),
        ],
        if (t.inSeries) ...[
          const SizedBox(height: 4),
          Text('Rep ${t.rep}/${t.repCount} · ${formatMeters(t.repMeters)}',
              style: _mutedStyle),
        ],
      ],
    );
  }
}

class _RepsContent extends StatelessWidget {
  const _RepsContent({required this.tracker});

  final SeriesTracker tracker;

  @override
  Widget build(BuildContext context) {
    final reps = tracker.previousReps;
    if (reps.isEmpty) {
      return const Text('Sin repeticiones completas', style: _mutedStyle);
    }
    return Column(
      children: [
        for (final r in reps)
          _Row(
            'Rep ${r.rep}',
            '${r.workSplitSeconds == null ? '—' : formatSplit(r.workSplitSeconds!)}'
                ' · ${formatMeters(r.totalMeters)}',
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/series_panels_test.dart`. Expected: PASS.
Run: `flutter analyze lib/features/workout/series_panels.dart test/series_panels_test.dart`. Expected: sin issues.

```bash
git add lib/features/workout/series_panels.dart test/series_panels_test.dart
git commit -m "feat(workout): add WallClock and collapsible SeriesPanels widgets"
```

---

### Task 5: Montar la hora y los paneles en la pantalla inmersiva

**Files:** Modify `lib/features/workout/immersive_workout_screen.dart`

- [ ] **Step 1: Import**

Agregar `import 'series_panels.dart';` después de `import 'workout_provider.dart';`.

- [ ] **Step 2: Hueco `belowSpm` en `_ImmersiveHUD`**

En `class _ImmersiveHUD`, agregar el campo `final Widget? belowSpm;` después de `final IntervalStep? currentStep;`, y `this.belowSpm,` en el constructor, después de `required this.currentStep,`.

En `build`, el bloque `// ── Top-left: SPM (biggest metric) ──` tiene un `Positioned(top: …padding.top + 90, left: 14, child: _GlassMetricCard(label: 'SPM', …))`. Reemplazar su `child:` por una columna que conserve exactamente el mismo `_GlassMetricCard` y agregue el hueco:

```dart
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GlassMetricCard(
                label: 'SPM',
                value: data.strokeRate.toStringAsFixed(1),
                color: spmColor,
                size: _MetricSize.large,
                hasTarget: hasSpmTarget,
              ),
              if (belowSpm != null) ...[
                const SizedBox(height: 10),
                belowSpm!,
              ],
            ],
          ),
```

- [ ] **Step 3: Pasar los paneles y agregar la hora**

En `_ImmersiveWorkoutPageState.build`, reemplazar:

```dart
            _ImmersiveHUD(data: w.data, elapsedSeconds: w.totalElapsedSeconds,
                currentStep: sp?.step),
```

por:

```dart
            _ImmersiveHUD(
              data: w.data,
              elapsedSeconds: w.totalElapsedSeconds,
              currentStep: sp?.step,
              // Parciales y series: solo en rutinas, colapsables
              belowSpm: w.routine != null ? SeriesPanels(tracker: w.series) : null,
            ),

            // ── 4b. Hora actual ────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 90,
              left: 0,
              right: 0,
              child: const Center(child: WallClock()),
            ),
```

- [ ] **Step 4: Verificar**

Run: `flutter analyze lib/features/workout`. Expected: sin issues nuevos de nivel `error` o `warning` en lo tocado.
Run: `flutter test`. Expected: todo pasa.

- [ ] **Step 5: Commit**

```bash
git add lib/features/workout/immersive_workout_screen.dart
git commit -m "feat(workout): show wall clock and series panels in immersive screen"
```

- [ ] **Step 6: Verificación manual (controller)**

`flutter run -d windows --dart-define=SIMULATOR=true`. Crear la rutina "Test series": una serie de 4 repeticiones con 1000 m de trabajo y 1 min de enfriamiento. Iniciarla y verificar:
- la hora arriba al centro;
- los chips "500 m" y "Reps" debajo de SPM;
- al expandir, las vueltas que se van sumando y la vuelta en curso;
- al llegar a la repetición 2, la fila "Rep 1 · m:ss · N m";
- que colapsado se vea como antes.

Con el panel del simulador en "Fuerte", la vuelta siguiente tiene que bajar a unos 1:47.
