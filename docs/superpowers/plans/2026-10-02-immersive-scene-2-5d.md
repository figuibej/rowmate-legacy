# Escena inmersiva 2.5D: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar la escena plana de la pantalla inmersiva por una escena en perspectiva con cámara de persecución, agua en GPU (fragment shader), remero articulado con la secuencia real de la palada y cuatro escenarios a elegir.

**Architecture:** Un motor de escena en capas bajo `lib/features/workout/scene/`: `SceneCamera` proyecta metros → píxeles; `SceneState` integra velocidad real, distancia y fase de palada una vez por frame desde un `Ticker`; `Environment` genera la orilla de forma determinista por segmento; cuatro `CustomPainter` (cielo, agua, orilla, bote) pintan en orden. La selección de escenario vive en `SceneSettings` (provider + SharedPreferences).

**Tech Stack:** Flutter 3.47, Dart 3.13, `dart:ui` FragmentProgram (GLSL), provider, shared_preferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-02-immersive-scene-2-5d-design.md` (leer antes de cada tarea).

**Branch:** `feature/immersive-dev-simulator`. Flutter no está en el PATH de las shells: `C:\Users\Usuario\dev\flutter\bin\flutter.bat`. Nunca `git add -A`/`.`; stagear solo los archivos de cada tarea. Comentarios en español, como el resto del código. Usar `withValues(alpha:)`, nunca `withOpacity`.

---

## Estructura de archivos

| Archivo | Tarea | Responsabilidad |
|---|---|---|
| `lib/features/workout/scene/scene_camera.dart` | 1 | Proyección mundo → pantalla |
| `lib/features/workout/scene/stroke_cycle.dart` | 2 | Secuencia de la palada y ángulo del remo |
| `lib/features/workout/scene/time_of_day.dart` | 2 | Paleta y luz según la hora |
| `lib/features/workout/scene/environment.dart` | 3 | `Environment`, `ShoreProp`, generador determinista |
| `lib/features/workout/scene/environments/*.dart` | 3 | Los 4 escenarios |
| `lib/features/workout/scene/scene_state.dart` | 4 | Velocidad, distancia, fase, cabeceo, charcos |
| `shaders/water.frag` + `scene/water_shader.dart` + `scene/painters/water_painter.dart` | 5 | Agua en GPU con fallback |
| `scene/painters/sky_painter.dart`, `shore_painter.dart` | 6 | Cielo y orilla |
| `scene/painters/boat_painter.dart` | 7 | Bote, remero, remos, charcos |
| `scene/scene_settings.dart`, `environment_picker.dart`, `painters/thumbnail_painter.dart`, l10n, `main.dart`, `simulator_overlay.dart` | 8 | Selección de escenario y hora forzada en dev |
| `scene/scene_view.dart`, `immersive_workout_screen.dart` | 9 | Composición e integración |

---

### Task 1: `SceneCamera`

**Files:** Create `lib/features/workout/scene/scene_camera.dart`; Test `test/scene/scene_camera_test.dart`

- [ ] **Step 1: Test que falla**

```dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';

void main() {
  const portrait = Size(390, 844);
  const landscape = Size(844, 390);

  test('horizonte y focal según orientación', () {
    expect(SceneCamera(portrait).horizonY, closeTo(844 * 0.40, 0.001));
    expect(SceneCamera(landscape).horizonY, closeTo(390 * 0.42, 0.001));
    expect(SceneCamera(portrait).focal, 390);
    expect(SceneCamera(landscape).focal, 390);
  });

  test('lo lejano queda más cerca del horizonte, centrado y más chico', () {
    final cam = SceneCamera(portrait);
    final near = cam.project(3, 0, 10)!;
    final far = cam.project(3, 0, 200)!;
    expect(far.dy, lessThan(near.dy));
    expect(far.dy, greaterThan(cam.horizonY));
    expect((far.dx - cam.centerX).abs(), lessThan((near.dx - cam.centerX).abs()));
    expect(cam.scaleAt(200), lessThan(cam.scaleAt(10)));
    // z → ∞ converge al punto de fuga
    final vp = cam.project(3, 0, 1e9)!;
    expect(vp.dx, closeTo(cam.centerX, 0.01));
    expect(vp.dy, closeTo(cam.horizonY, 0.01));
  });

  test('detrás de la cámara no se proyecta', () {
    expect(SceneCamera(portrait).project(0, 0, 0.2), isNull);
  });

  test('unprojectWater invierte project para y = 0', () {
    final cam = SceneCamera(landscape);
    for (final (x, z) in [(-4.0, 6.0), (0.0, 30.0), (7.5, 120.0)]) {
      final s = cam.project(x, 0, z)!;
      final w = cam.unprojectWater(s);
      expect(w.dx, closeTo(x, 1e-6));
      expect(w.dy, closeTo(z, 1e-6));
    }
  });
}
```

Run: `flutter test test/scene/scene_camera_test.dart` → falla: `scene_camera.dart` no existe.

- [ ] **Step 2: Implementar**

```dart
import 'dart:ui';

/// Cámara de persecución: proyecta coordenadas de mundo (metros) a pantalla.
/// Mundo: x lateral (0 = eje del bote, + derecha), z hacia adelante desde la
/// cámara, y altura sobre el agua.
class SceneCamera {
  SceneCamera(this.size)
      : horizonY = size.height * (size.width > size.height ? 0.42 : 0.40),
        focal = size.shortestSide;

  /// Altura de la cámara sobre el agua (m).
  static const double camHeight = 2.2;

  /// Distancia de la cámara al remero (m).
  static const double boatZ = 8.0;

  /// Nada más cerca que esto se dibuja.
  static const double minZ = 0.5;

  final Size size;
  final double horizonY;
  final double focal;

  double get centerX => size.width / 2;

  /// Punto de mundo → pantalla. null si queda detrás de la cámara.
  Offset? project(double x, double y, double z) {
    if (z <= minZ) return null;
    return Offset(
      centerX + focal * x / z,
      horizonY + focal * (camHeight - y) / z,
    );
  }

  /// Píxeles por metro a la distancia z.
  double scaleAt(double z) => focal / z;

  /// Inversa para puntos sobre el agua (y = 0); screen.dy debe ser > horizonY.
  /// Devuelve Offset(x, z) en metros.
  Offset unprojectWater(Offset screen) {
    final z = focal * camHeight / (screen.dy - horizonY);
    final x = (screen.dx - centerX) * z / focal;
    return Offset(x, z);
  }
}
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/scene/scene_camera_test.dart` → PASS. `flutter analyze lib/features/workout/scene test/scene` → sin issues.

```bash
git add lib/features/workout/scene/scene_camera.dart test/scene/scene_camera_test.dart
git commit -m "feat(scene): add SceneCamera perspective projection"
```

---

### Task 2: `StrokeCycle` y `TimeOfDay`

**Files:** Create `lib/features/workout/scene/stroke_cycle.dart`, `lib/features/workout/scene/time_of_day.dart`; Test `test/scene/stroke_cycle_test.dart`, `test/scene/time_of_day_test.dart`

- [ ] **Step 1: Tests que fallan**

`test/scene/stroke_cycle_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/stroke_cycle.dart';

void main() {
  test('catch: piernas plegadas, brazos estirados, pala en el agua', () {
    expect(StrokeCycle.legs(0), 0);
    expect(StrokeCycle.arms(0), 0);
    expect(StrokeCycle.back(0), 0);
    expect(StrokeCycle.bladeInWater(0), isTrue);
    expect(StrokeCycle.oarSweep(0), lessThan(0));
    expect(StrokeCycle.torsoLean(0), greaterThan(0)); // inclinado a la proa
  });

  test('finish: piernas extendidas, brazos flexionados, pala sale', () {
    expect(StrokeCycle.legs(0.36), 1);
    expect(StrokeCycle.arms(0.36), 1);
    expect(StrokeCycle.back(0.36), 1);
    expect(StrokeCycle.oarSweep(0.36), greaterThan(0));
    expect(StrokeCycle.bladeInWater(0.39), isFalse);
    expect(StrokeCycle.torsoLean(0.36), lessThan(0));
  });

  test('en el drive: piernas antes que espalda, espalda antes que brazos', () {
    expect(StrokeCycle.legs(0.12), greaterThan(StrokeCycle.back(0.12)));
    expect(StrokeCycle.back(0.12), greaterThan(StrokeCycle.arms(0.12)));
    expect(StrokeCycle.arms(0.12), 0);
  });

  test('la recuperación vuelve todo al catch', () {
    expect(StrokeCycle.legs(0.999), closeTo(0, 1e-3));
    expect(StrokeCycle.arms(0.999), 0);
    expect(StrokeCycle.back(0.999), 0);
    expect(StrokeCycle.oarSweep(0.999), closeTo(StrokeCycle.catchSweep, 1e-3));
    expect(StrokeCycle.bladeFeathered(0.7), isTrue);
  });
}
```

`test/scene/time_of_day_test.dart`:

```dart
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';
import 'package:rowmate/features/workout/scene/time_of_day.dart';

void main() {
  final cam = SceneCamera(const Size(390, 844));

  test('12:00 es día con el sol arriba', () {
    expect(TimeOfDay.isNight(12), isFalse);
    final light = TimeOfDay.lightFor(12, cam);
    expect(light.isMoon, isFalse);
    expect(light.position.dy, lessThan(cam.horizonY * 0.2));
    expect(light.strength, 1.0);
  });

  test('23:00 es noche con luna', () {
    expect(TimeOfDay.isNight(23), isTrue);
    final light = TimeOfDay.lightFor(23, cam);
    expect(light.isMoon, isTrue);
    expect(light.position.dy, lessThan(cam.horizonY));
    expect(TimeOfDay.paletteFor(23).ambient, lessThan(0.5));
  });

  test('18:30 interpola entre atardecer y anochecer', () {
    final p = TimeOfDay.paletteFor(18.5);
    expect(p.ambient, closeTo(0.85 + (0.5 - 0.85) * 0.25, 1e-9));
    expect(p.skyHorizon, isNot(TimeOfDay.paletteFor(18).skyHorizon));
    expect(p.skyHorizon, isNot(TimeOfDay.paletteFor(20).skyHorizon));
  });

  test('la paleta es continua a medianoche y al amanecer', () {
    expect(TimeOfDay.paletteFor(23.99).ambient, closeTo(TimeOfDay.paletteFor(0).ambient, 0.01));
    expect(TimeOfDay.paletteFor(4.99).ambient, closeTo(TimeOfDay.paletteFor(5).ambient, 0.01));
  });
}
```

Run ambos → fallan por archivos inexistentes.

- [ ] **Step 2: Implementar `stroke_cycle.dart`**

```dart
import 'dart:math' as math;

/// Secuencia de la palada en función de la fase p ∈ [0, 1).
/// Drive 0.00–0.40 (rápido), recuperación 0.40–1.00 (lenta): ratio 1:2.
class StrokeCycle {
  StrokeCycle._();

  /// Ángulo del remo en el catch: pala hacia la proa.
  static const double catchSweep = -55 * math.pi / 180;

  /// Ángulo del remo en el finish: pala hacia la popa.
  static const double finishSweep = 35 * math.pi / 180;

  /// 0 = piernas plegadas (catch), 1 = extendidas (finish).
  static double legs(double p) {
    if (p < 0.60) return _ramp(p, 0.00, 0.18);
    return 1 - _ramp(p, 0.60, 1.00);
  }

  /// 0 = tronco adelante (+25°), 1 = tronco atrás (−20°).
  static double back(double p) {
    if (p < 0.50) return _ramp(p, 0.10, 0.30);
    return 1 - _ramp(p, 0.50, 0.75);
  }

  /// 0 = brazos estirados, 1 = flexionados al pecho.
  static double arms(double p) {
    if (p < 0.40) return _ramp(p, 0.22, 0.36);
    return 1 - _ramp(p, 0.40, 0.60);
  }

  /// Inclinación del tronco en radianes (+ hacia la proa).
  static double torsoLean(double p) =>
      _lerp(25 * math.pi / 180, -20 * math.pi / 180, back(p));

  static bool bladeInWater(double p) => p < 0.38;
  static bool bladeFeathered(double p) => !bladeInWater(p);

  /// Ángulo del remo respecto de la perpendicular al bote (rad).
  /// Negativo = pala hacia la proa.
  static double oarSweep(double p) {
    if (p < 0.36) return _lerp(catchSweep, finishSweep, _smooth(p / 0.36));
    if (p < 0.40) return finishSweep;
    return _lerp(finishSweep, catchSweep, _smooth((p - 0.40) / 0.60));
  }

  static double _ramp(double p, double a, double b) =>
      _smooth(((p - a) / (b - a)).clamp(0.0, 1.0));
  static double _smooth(double t) => t * t * (3 - 2 * t);
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
```

- [ ] **Step 3: Implementar `time_of_day.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import 'scene_camera.dart';

/// Colores de la escena para una hora dada.
class ScenePalette {
  const ScenePalette({
    required this.skyTop,
    required this.skyHorizon,
    required this.waterNear,
    required this.waterFar,
    required this.sunColor,
    required this.sunGlow,
    required this.fog,
    required this.ambient,
  });

  final Color skyTop;
  final Color skyHorizon;
  final Color waterNear;
  final Color waterFar;
  final Color sunColor;
  final Color sunGlow;
  final Color fog;

  /// Multiplicador de luz para orilla y bote (1 = día, 0.35 = noche).
  final double ambient;

  static ScenePalette lerp(ScenePalette a, ScenePalette b, double t) => ScenePalette(
        skyTop: Color.lerp(a.skyTop, b.skyTop, t)!,
        skyHorizon: Color.lerp(a.skyHorizon, b.skyHorizon, t)!,
        waterNear: Color.lerp(a.waterNear, b.waterNear, t)!,
        waterFar: Color.lerp(a.waterFar, b.waterFar, t)!,
        sunColor: Color.lerp(a.sunColor, b.sunColor, t)!,
        sunGlow: Color.lerp(a.sunGlow, b.sunGlow, t)!,
        fog: Color.lerp(a.fog, b.fog, t)!,
        ambient: a.ambient + (b.ambient - a.ambient) * t,
      );
}

/// Sol o luna: posición en pantalla y fuerza del brillo sobre el agua.
class SceneLight {
  const SceneLight({required this.position, required this.strength, required this.isMoon});
  final Offset position;
  final double strength; // 0–1
  final bool isMoon;
}

class TimeOfDay {
  TimeOfDay._();

  static double sunElevation(double hour) => math.sin((hour - 6) / 12 * math.pi);
  static bool isNight(double hour) => sunElevation(hour) <= -0.1;

  static SceneLight lightFor(double hour, SceneCamera cam) {
    final night = isNight(hour);
    final h = night ? (hour + 12) % 24 : hour;
    final elev = math.sin((h - 6) / 12 * math.pi).clamp(0.0, 1.0);
    final fx = (0.25 + 0.5 * (h - 6) / 12).clamp(0.15, 0.85);
    return SceneLight(
      position: Offset(cam.size.width * fx, cam.horizonY - elev * cam.horizonY * 0.9),
      strength: night ? 0.45 : (elev * 1.2).clamp(0.2, 1.0),
      isMoon: night,
    );
  }

  static const _dawn = ScenePalette(
    skyTop: Color(0xFF2A1B5E), skyHorizon: Color(0xFFFF9A5C),
    waterNear: Color(0xFF1A2B4A), waterFar: Color(0xFF3A2F55),
    sunColor: Color(0xFFFFB070), sunGlow: Color(0xFFFF7A3D),
    fog: Color(0xFFC98A7A), ambient: 0.7);
  static const _morning = ScenePalette(
    skyTop: Color(0xFF3A7BD5), skyHorizon: Color(0xFFFFD9A0),
    waterNear: Color(0xFF1E5A9E), waterFar: Color(0xFF5C8FC9),
    sunColor: Color(0xFFFFE4A0), sunGlow: Color(0xFFFFC46B),
    fog: Color(0xFFDCE8F5), ambient: 0.95);
  static const _noon = ScenePalette(
    skyTop: Color(0xFF0B4FA8), skyHorizon: Color(0xFF8FD3FF),
    waterNear: Color(0xFF0E4F8F), waterFar: Color(0xFF2F8FD6),
    sunColor: Color(0xFFFFF6D5), sunGlow: Color(0xFFFFE9A6),
    fog: Color(0xFFCFE9FF), ambient: 1.0);
  static const _sunset = ScenePalette(
    skyTop: Color(0xFF2E3C8C), skyHorizon: Color(0xFFFF8C5A),
    waterNear: Color(0xFF163A66), waterFar: Color(0xFF7C5C7A),
    sunColor: Color(0xFFFFB36B), sunGlow: Color(0xFFFF6B3D),
    fog: Color(0xFFE0A28A), ambient: 0.85);
  static const _dusk = ScenePalette(
    skyTop: Color(0xFF0D1A4A), skyHorizon: Color(0xFF4A3A7A),
    waterNear: Color(0xFF0B1E3A), waterFar: Color(0xFF2A2A55),
    sunColor: Color(0xFFDDE6FF), sunGlow: Color(0xFF8FA3FF),
    fog: Color(0xFF30335A), ambient: 0.5);
  static const _night = ScenePalette(
    skyTop: Color(0xFF050A1E), skyHorizon: Color(0xFF121C3A),
    waterNear: Color(0xFF06122A), waterFar: Color(0xFF0E1E3C),
    sunColor: Color(0xFFE6EEFF), sunGlow: Color(0xFFA6B8FF),
    fog: Color(0xFF0F1730), ambient: 0.35);

  // Keyframes cíclicos: 22 h → 5 h del día siguiente (29)
  static const _keys = <(double, ScenePalette)>[
    (5, _dawn), (7, _morning), (12, _noon), (18, _sunset), (20, _dusk), (22, _night), (29, _dawn),
  ];

  static ScenePalette paletteFor(double hour) {
    var h = hour % 24;
    if (h < 5) h += 24;
    for (var i = 0; i < _keys.length - 1; i++) {
      final (h0, p0) = _keys[i];
      final (h1, p1) = _keys[i + 1];
      if (h >= h0 && h <= h1) return ScenePalette.lerp(p0, p1, (h - h0) / (h1 - h0));
    }
    return _night;
  }
}
```

- [ ] **Step 4: Verificar y commitear**

Run: `flutter test test/scene` → PASS. `flutter analyze lib/features/workout/scene test/scene` → sin issues.

```bash
git add lib/features/workout/scene/stroke_cycle.dart lib/features/workout/scene/time_of_day.dart test/scene/stroke_cycle_test.dart test/scene/time_of_day_test.dart
git commit -m "feat(scene): add StrokeCycle and TimeOfDay"
```

---

### Task 3: `Environment` y los 4 escenarios

**Files:** Create `lib/features/workout/scene/environment.dart`, `lib/features/workout/scene/environments/lake_environment.dart`, `river_environment.dart`, `coast_environment.dart`, `regatta_environment.dart`; Test `test/scene/environment_test.dart`

- [ ] **Step 1: Test que falla**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/environment.dart';

String _key(ShoreProp p) => '${p.kind}:${p.x}:${p.z}:${p.seed}';

void main() {
  for (final id in EnvironmentId.values) {
    final env = Environment.of(id);

    test('$id: propsForSegment es determinista', () {
      final a = env.propsForSegment(7).map(_key).toList();
      final b = env.propsForSegment(7).map(_key).toList();
      expect(a, b);
      expect(a, isNot(env.propsForSegment(8).map(_key).toList()));
    });

    test('$id: cada segmento tiene objetos y quedan dentro del segmento', () {
      for (var k = 0; k < 30; k++) {
        final props = env.propsForSegment(k);
        expect(props, isNotEmpty, reason: 'segmento $k vacío');
        for (final p in props) {
          expect(p.z, inInclusiveRange(k * Environment.segmentLength, (k + 1) * Environment.segmentLength));
          if (p.kind != PropKind.bridge && p.kind != PropKind.laneBuoy) {
            expect(p.x.abs(), greaterThanOrEqualTo(Environment.bankX), reason: '${p.kind} en el agua');
          }
        }
      }
    });

    test('$id: visibleProps ordena de lejos a cerca y acota a 40', () {
      final props = env.visibleProps(1234);
      expect(props.length, lessThanOrEqualTo(Environment.maxVisibleProps));
      for (var i = 1; i < props.length; i++) {
        expect(props[i].z, lessThanOrEqualTo(props[i - 1].z));
      }
      for (final p in props) {
        expect(p.z, inInclusiveRange(1235, 1234 + Environment.visibleRange));
      }
    });
  }

  test('el canal de regata tiene boyas cada 10 m', () {
    final buoys = Environment.of(EnvironmentId.regatta)
        .propsForSegment(3)
        .where((p) => p.kind == PropKind.laneBuoy)
        .map((p) => p.z)
        .toSet()
        .toList()
      ..sort();
    expect(buoys.length, 5);
    expect(buoys[1] - buoys[0], 10);
  });

  test('el río urbano tiene un puente cada 800 m', () {
    final env = Environment.of(EnvironmentId.river);
    final withBridge = List.generate(32, (k) => k)
        .where((k) => env.propsForSegment(k).any((p) => p.kind == PropKind.bridge))
        .toList();
    expect(withBridge, [5, 21]);
  });
}
```

Run: `flutter test test/scene/environment_test.dart` → falla.

- [ ] **Step 2: Implementar `environment.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import 'environments/coast_environment.dart';
import 'environments/lake_environment.dart';
import 'environments/regatta_environment.dart';
import 'environments/river_environment.dart';
import 'scene_camera.dart';
import 'time_of_day.dart';

enum EnvironmentId { lake, river, coast, regatta }

enum PropKind {
  pine, cabin, pier, building, boathouse, bridge, laneBuoy, lamp, cliff,
  lighthouse, beachUmbrella, grandstand, finishTower, flag, distanceMarker,
}

/// Objeto de la orilla en coordenadas de mundo (metros absolutos).
class ShoreProp {
  const ShoreProp({
    required this.x,
    required this.z,
    required this.kind,
    this.scale = 1.0,
    this.seed = 0,
  });

  /// Lateral: negativo = orilla izquierda.
  final double x;

  /// Distancia absoluta desde el inicio del recorrido.
  final double z;
  final PropKind kind;
  final double scale;

  /// Variación de forma/color; en distanceMarker, los metros a mostrar.
  final int seed;
}

/// Un escenario: paleta de agua, silueta lejana y objetos de la orilla.
abstract class Environment {
  const Environment();

  static const double segmentLength = 50;

  /// |x| mínimo de la orilla (el río tiene 18 m de ancho).
  static const double bankX = 9;
  static const double visibleRange = 400;
  static const int maxVisibleProps = 40;

  EnvironmentId get id;

  /// 0–1, amplitud del oleaje para el shader.
  double get waveAmplitude;

  /// Metros entre crestas.
  double get waveScale;

  Color tintWater(Color base) => base;

  static Environment of(EnvironmentId id) => switch (id) {
        EnvironmentId.lake => const LakeEnvironment(),
        EnvironmentId.river => const RiverEnvironment(),
        EnvironmentId.coast => const CoastEnvironment(),
        EnvironmentId.regatta => const RegattaEnvironment(),
      };

  /// Objetos del segmento k (z ∈ [k·50, (k+1)·50]). Determinista: el mismo
  /// paisaje a la misma distancia en cada sesión.
  List<ShoreProp> propsForSegment(int k) {
    // Semilla propia: Object.hash no es estable entre ejecuciones
    final rnd = math.Random(id.index * 1000003 + k * 7919 + 17);
    return generate(k, rnd);
  }

  List<ShoreProp> generate(int k, math.Random rnd);

  /// Objetos visibles desde `distance`, de lejos a cerca, máximo 40
  /// (se descartan primero los más lejanos).
  List<ShoreProp> visibleProps(double distance) {
    final zMin = distance + 1;
    final zMax = distance + visibleRange;
    final first = math.max(0, (zMin / segmentLength).floor());
    final last = (zMax / segmentLength).floor();
    final out = <ShoreProp>[];
    for (var k = first; k <= last; k++) {
      for (final p in propsForSegment(k)) {
        if (p.z >= zMin && p.z <= zMax) out.add(p);
      }
    }
    out.sort((a, b) => b.z.compareTo(a.z));
    if (out.length > maxVisibleProps) {
      return out.sublist(out.length - maxVisibleProps);
    }
    return out;
  }

  /// Silueta lejana entre horizonY − 0.12·h y horizonY.
  void paintHorizon(Canvas canvas, Size size, SceneCamera cam, ScenePalette p,
      double distance, double time);
}

/// Color de la silueta: un tono propio mezclado con la niebla.
Color horizonColor(ScenePalette p, Color tone, double depth) =>
    Color.lerp(tone, p.fog, 0.35 + 0.4 * depth)!;
```

- [ ] **Step 3: Implementar `environments/lake_environment.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Lago alpino: agua calma, montañas nevadas, pinos, muelles y cabañas.
class LakeEnvironment extends Environment {
  const LakeEnvironment();

  @override
  EnvironmentId get id => EnvironmentId.lake;
  @override
  double get waveAmplitude => 0.25;
  @override
  double get waveScale => 2.5;

  @override
  List<ShoreProp> generate(int k, math.Random rnd) {
    final out = <ShoreProp>[];
    final z0 = k * Environment.segmentLength;
    for (final side in [-1.0, 1.0]) {
      var z = z0 + rnd.nextDouble() * 6;
      while (z < z0 + 50) {
        out.add(ShoreProp(
          x: side * (Environment.bankX + 1 + rnd.nextDouble() * 6),
          z: z,
          kind: PropKind.pine,
          scale: 0.7 + rnd.nextDouble() * 0.6,
          seed: rnd.nextInt(1000),
        ));
        z += 6 + rnd.nextDouble() * 6;
      }
    }
    if (k % 8 == 3) out.add(ShoreProp(x: -Environment.bankX, z: z0 + 25, kind: PropKind.pier));
    if (k % 12 == 7) {
      out.add(ShoreProp(x: Environment.bankX + 4, z: z0 + 10, kind: PropKind.cabin, seed: k));
    }
    return out;
  }

  @override
  void paintHorizon(Canvas canvas, Size size, SceneCamera cam, ScenePalette p,
      double distance, double time) {
    final w = size.width;
    final hMax = size.height * 0.12;
    // Dos cordones: lejano claro y cercano más oscuro, con parallax distinto
    _mountains(canvas, w, cam.horizonY, hMax, distance * 0.004, 0.0, 1.0,
        horizonColor(p, const Color(0xFF5C6E8A), 1.0), true, p);
    _mountains(canvas, w, cam.horizonY, hMax * 0.7, distance * 0.008, 3.1, 1.6,
        horizonColor(p, const Color(0xFF2F4A3A), 0.3), false, p);
  }

  void _mountains(Canvas canvas, double w, double horizonY, double hMax, double shift,
      double phase, double freq, Color color, bool snow, ScenePalette p) {
    final path = Path()..moveTo(0, horizonY);
    const steps = 48;
    final heights = <double>[];
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final u = (x + shift * 60) / w * freq;
      final h = hMax * (0.45 + 0.35 * math.sin(u * 6.3 + phase) + 0.2 * math.sin(u * 15.1 + phase * 2));
      heights.add(h);
      path.lineTo(x, horizonY - h);
    }
    path
      ..lineTo(w, horizonY)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    if (snow) {
      // Nieve en las cumbres: picos por encima del 75 % de la altura máxima
      final snowPaint = Paint()..color = Color.lerp(const Color(0xFFF2F6FA), p.fog, 0.3)!;
      for (var i = 1; i < steps; i++) {
        if (heights[i] > hMax * 0.75 && heights[i] >= heights[i - 1] && heights[i] >= heights[i + 1]) {
          final x = w * i / steps;
          final cap = Path()
            ..moveTo(x, horizonY - heights[i])
            ..lineTo(x - w / steps * 0.9, horizonY - heights[i] * 0.82)
            ..lineTo(x + w / steps * 0.9, horizonY - heights[i] * 0.82)
            ..close();
          canvas.drawPath(cap, snowPaint);
        }
      }
    }
  }
}
```

- [ ] **Step 4: Implementar `environments/river_environment.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Río urbano: boathouses, edificios, faroles, puentes de piedra, boyas.
class RiverEnvironment extends Environment {
  const RiverEnvironment();

  @override
  EnvironmentId get id => EnvironmentId.river;
  @override
  double get waveAmplitude => 0.35;
  @override
  double get waveScale => 2.0;

  @override
  List<ShoreProp> generate(int k, math.Random rnd) {
    final out = <ShoreProp>[];
    final z0 = k * Environment.segmentLength;
    for (final side in [-1.0, 1.0]) {
      var z = z0 + rnd.nextDouble() * 8;
      while (z < z0 + 50) {
        final boathouse = rnd.nextDouble() < 0.3;
        out.add(ShoreProp(
          x: side * (Environment.bankX + 2 + rnd.nextDouble() * 3),
          z: z,
          kind: boathouse ? PropKind.boathouse : PropKind.building,
          scale: 0.8 + rnd.nextDouble() * 0.5,
          seed: rnd.nextInt(1000),
        ));
        z += 15 + rnd.nextDouble() * 15;
      }
      for (var z = z0 + 12.5; z < z0 + 50; z += 25) {
        out.add(ShoreProp(x: side * (Environment.bankX + 0.5), z: z, kind: PropKind.lamp));
      }
      out.add(ShoreProp(x: side * 3, z: z0 + 25, kind: PropKind.laneBuoy, seed: 1));
    }
    if (k % 16 == 5) out.add(ShoreProp(x: 0, z: z0 + 20, kind: PropKind.bridge, seed: k));
    return out;
  }

  @override
  void paintHorizon(Canvas canvas, Size size, SceneCamera cam, ScenePalette p,
      double distance, double time) {
    final w = size.width;
    final hMax = size.height * 0.12;
    final shift = distance * 0.004 * 60;
    final night = p.ambient < 0.6;
    final body = Paint()..color = horizonColor(p, const Color(0xFF3A4660), 0.8);
    final window = Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.85);
    const bw = 34.0;
    final count = (w / bw).ceil() + 2;
    final first = (shift / bw).floor();
    for (var i = first; i < first + count; i++) {
      final rnd = math.Random(i * 31 + 7);
      final x = i * bw - shift;
      final h = hMax * (0.3 + rnd.nextDouble() * 0.7);
      final bwidth = bw * (0.6 + rnd.nextDouble() * 0.4);
      canvas.drawRect(Rect.fromLTWH(x, cam.horizonY - h, bwidth, h), body);
      if (night) {
        for (var wy = cam.horizonY - h + 6; wy < cam.horizonY - 4; wy += 7) {
          for (var wx = x + 4; wx < x + bwidth - 4; wx += 8) {
            if (rnd.nextDouble() < 0.5) canvas.drawRect(Rect.fromLTWH(wx, wy, 3, 4), window);
          }
        }
      }
    }
  }
}
```

- [ ] **Step 5: Implementar `environments/coast_environment.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Costa: horizonte abierto, acantilados y faro a la izquierda, playa, gaviotas.
class CoastEnvironment extends Environment {
  const CoastEnvironment();

  /// La orilla izquierda está más lejos que en el río; a la derecha, mar abierto.
  static const double cliffX = -14;

  @override
  EnvironmentId get id => EnvironmentId.coast;
  @override
  double get waveAmplitude => 0.8;
  @override
  double get waveScale => 4.0;
  @override
  Color tintWater(Color base) => Color.lerp(base, const Color(0xFF0E6B7A), 0.3)!;

  @override
  List<ShoreProp> generate(int k, math.Random rnd) {
    final out = <ShoreProp>[];
    final z0 = k * Environment.segmentLength;
    if (k % 5 == 2) {
      // Playa: sombrillas en vez de acantilado
      for (var i = 0; i < 3; i++) {
        out.add(ShoreProp(
          x: cliffX + 1 + rnd.nextDouble() * 3,
          z: z0 + 8 + i * 14 + rnd.nextDouble() * 6,
          kind: PropKind.beachUmbrella,
          seed: rnd.nextInt(1000),
        ));
      }
    } else {
      for (final z in [z0 + 0.0, z0 + 25.0]) {
        out.add(ShoreProp(x: cliffX, z: z, kind: PropKind.cliff, scale: 0.8 + rnd.nextDouble() * 0.5, seed: rnd.nextInt(1000)));
      }
    }
    if (k % 20 == 10) out.add(ShoreProp(x: cliffX, z: z0 + 30, kind: PropKind.lighthouse));
    return out;
  }

  @override
  void paintHorizon(Canvas canvas, Size size, SceneCamera cam, ScenePalette p,
      double distance, double time) {
    final w = size.width;
    final hMax = size.height * 0.08;
    // Acantilado lejano a la izquierda que se desvanece hacia el centro
    final shift = (distance * 0.003 * 60) % (w * 0.3);
    final path = Path()..moveTo(0, cam.horizonY);
    const steps = 20;
    for (var i = 0; i <= steps; i++) {
      final x = w * 0.35 * i / steps - shift * 0.2;
      final fade = 1 - i / steps;
      final h = hMax * fade * (0.6 + 0.4 * math.sin(i * 1.7 + 0.5));
      path.lineTo(x, cam.horizonY - h);
    }
    path
      ..lineTo(w * 0.35, cam.horizonY)
      ..close();
    canvas.drawPath(path, Paint()..color = horizonColor(p, const Color(0xFF4A3F3A), 0.9));
    // Gaviotas: "M" pequeñas que cruzan el cielo con el tiempo
    final gull = Paint()
      ..color = const Color(0xFF2B2B2B).withValues(alpha: 0.5 + 0.4 * p.ambient)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 5; i++) {
      final gx = ((time * (8 + i * 3) + i * 170) % (w + 60)) - 30;
      final gy = cam.horizonY * (0.35 + 0.1 * i) + math.sin(time * 2 + i) * 4;
      final flap = math.sin(time * 6 + i) * 3;
      final s = 5.0 + i;
      canvas.drawPath(
        Path()
          ..moveTo(gx - s, gy + flap)
          ..quadraticBezierTo(gx - s / 2, gy - 2, gx, gy)
          ..quadraticBezierTo(gx + s / 2, gy - 2, gx + s, gy + flap),
        gull,
      );
    }
  }
}
```

- [ ] **Step 6: Implementar `environments/regatta_environment.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Canal de regata: carriles con boyas, marcas cada 250 m, tribunas y torre.
class RegattaEnvironment extends Environment {
  const RegattaEnvironment();

  @override
  EnvironmentId get id => EnvironmentId.regatta;
  @override
  double get waveAmplitude => 0.3;
  @override
  double get waveScale => 1.5;

  @override
  List<ShoreProp> generate(int k, math.Random rnd) {
    final out = <ShoreProp>[];
    final z0 = k * Environment.segmentLength;
    // Boyas cada 10 m en 4 líneas (3 carriles visibles); el color cambia cada 250 m
    final color = (k ~/ 5) % 3;
    for (var z = z0; z < z0 + 50; z += 10) {
      for (final x in [-9.0, -3.0, 3.0, 9.0]) {
        out.add(ShoreProp(x: x, z: z.toDouble(), kind: PropKind.laneBuoy, seed: color));
      }
    }
    if (k % 5 == 0) {
      out.add(ShoreProp(x: -10.5, z: z0, kind: PropKind.distanceMarker, seed: (k * Environment.segmentLength).round()));
    }
    if (k % 20 == 4) out.add(ShoreProp(x: 12, z: z0 + 10, kind: PropKind.grandstand));
    if (k % 20 == 12) out.add(ShoreProp(x: -12, z: z0 + 10, kind: PropKind.finishTower));
    out.add(ShoreProp(x: k.isEven ? 10.5 : -10.5, z: z0 + 30, kind: PropKind.flag, seed: k));
    return out;
  }

  @override
  void paintHorizon(Canvas canvas, Size size, SceneCamera cam, ScenePalette p,
      double distance, double time) {
    final w = size.width;
    final hMax = size.height * 0.06;
    final shift = (distance * 0.006 * 60) % w;
    final land = Paint()..color = horizonColor(p, const Color(0xFF55704A), 0.9);
    canvas.drawRect(Rect.fromLTWH(0, cam.horizonY - hMax * 0.25, w, hMax * 0.25), land);
    // Bloques de tribuna y torre, repetidos a lo ancho
    final stand = Paint()..color = horizonColor(p, const Color(0xFF6E7B8C), 0.8);
    final tower = Paint()..color = horizonColor(p, const Color(0xFFB8C0CC), 0.8);
    const flagColors = [Color(0xFFE53935), Color(0xFFFFB300), Color(0xFF1E88E5), Color(0xFF43A047)];
    for (var x = -shift; x < w; x += w * 0.5) {
      canvas.drawRect(Rect.fromLTWH(x + w * 0.08, cam.horizonY - hMax * 0.7, w * 0.16, hMax * 0.5), stand);
      canvas.drawRect(Rect.fromLTWH(x + w * 0.36, cam.horizonY - hMax, w * 0.025, hMax), tower);
      for (var i = 0; i < 4; i++) {
        final fx = x + w * 0.42 + i * w * 0.015;
        final wave = math.sin(time * 3 + i) * 2;
        canvas.drawLine(Offset(fx, cam.horizonY - hMax * 0.6), Offset(fx, cam.horizonY - hMax * 0.25), tower);
        canvas.drawPath(
          Path()
            ..moveTo(fx, cam.horizonY - hMax * 0.6)
            ..lineTo(fx + 6, cam.horizonY - hMax * 0.55 + wave)
            ..lineTo(fx, cam.horizonY - hMax * 0.5)
            ..close(),
          Paint()..color = flagColors[i],
        );
      }
    }
  }
}
```

- [ ] **Step 7: Verificar y commitear**

Run: `flutter test test/scene/environment_test.dart` → PASS. `flutter analyze lib/features/workout/scene` → sin issues.

```bash
git add lib/features/workout/scene/environment.dart lib/features/workout/scene/environments test/scene/environment_test.dart
git commit -m "feat(scene): add Environment with lake, river, coast and regatta"
```

---

### Task 4: `SceneState`

**Files:** Create `lib/features/workout/scene/scene_state.dart`; Test `test/scene/scene_state_test.dart`

- [ ] **Step 1: Test que falla**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/scene_state.dart';

void main() {
  /// Avanza `seconds` en pasos de 0,05 s.
  void run(SceneState s, double seconds,
      {double pace = 107, double spm = 24, bool active = true}) {
    final steps = (seconds / 0.05).round();
    for (var i = 0; i < steps; i++) {
      s.update(dt: 0.05, pace500m: pace, spm: spm, isActive: active);
    }
  }

  test('la velocidad sale del split y se alcanza en unos segundos', () {
    final s = SceneState();
    expect(s.targetSpeedFor(pace500m: 107, isActive: true), closeTo(4.67, 0.01));
    expect(s.targetSpeedFor(pace500m: 107, isActive: false), 0);
    expect(s.targetSpeedFor(pace500m: 0, isActive: true), 0);
    run(s, 8);
    expect(s.speed, closeTo(4.67, 0.05));
    expect(s.distance, greaterThan(25));
  });

  test('al dejar de remar desacelera hasta detenerse', () {
    final s = SceneState();
    run(s, 8);
    final d = s.distance;
    run(s, 6, pace: 0);
    expect(s.speed, lessThan(0.1));
    expect(s.distance, greaterThan(d));
    run(s, 10, pace: 0);
    expect(s.speed, 0);
  });

  test('la fase de palada avanza a spm/60 ciclos por segundo', () {
    final s = SceneState();
    run(s, 1, spm: 24);
    expect(s.strokePhase, closeTo(0.4, 1e-6));
    run(s, 1.5, spm: 24);
    // Un ciclo completo: por redondeo puede quedar en 0.0 o en 0.999…
    expect(s.strokePhase, anyOf(closeTo(0.0, 1e-6), closeTo(1.0, 1e-6)));
  });

  test('en pausa no avanza la palada ni la velocidad', () {
    final s = SceneState();
    run(s, 0.5);
    final phase = s.strokePhase;
    run(s, 2, active: false);
    expect(s.strokePhase, phase);
    expect(s.speed, lessThan(0.5));
  });

  test('al soltar la pala aparecen dos charcos que envejecen y desaparecen', () {
    final s = SceneState();
    run(s, 0.8, spm: 24); // fase ≈ 0.32, pala en el agua
    expect(s.puddles, isEmpty);
    run(s, 0.3, spm: 24); // cruza 0.38
    expect(s.puddles, hasLength(2));
    expect(s.puddles.first.x, lessThan(0));
    expect(s.puddles.last.x, greaterThan(0));
    run(s, 5, spm: 0);
    expect(s.puddles, isEmpty);
  });
}
```

Run: `flutter test test/scene/scene_state_test.dart` → falla.

- [ ] **Step 2: Implementar**

```dart
import 'dart:math' as math;
import 'scene_camera.dart';
import 'stroke_cycle.dart';

/// Charco que deja la pala al salir del agua; se queda atrás con la distancia.
class Puddle {
  Puddle({required this.x, required this.worldZ});
  final double x;
  final double worldZ;
  double age = 0;
}

/// Estado dinámico de la escena, integrado una vez por frame.
class SceneState {
  /// Constante de tiempo (s) con la que la velocidad sigue al objetivo.
  static const double speedTau = 1.5;
  static const double puddleLife = 4.0;
  static const double oarLength = 2.9;
  static const double riggerX = 0.85;

  double speed = 0; // m/s
  double distance = 0; // m de mundo recorridos
  double strokePhase = 0; // 0–1
  double pitch = 0; // rad, + = proa arriba
  double time = 0; // s desde el inicio
  final List<Puddle> puddles = [];
  bool _bladeWasIn = true;

  double targetSpeedFor({required double pace500m, required bool isActive}) =>
      isActive && pace500m > 0 ? 500 / pace500m : 0;

  void update({
    required double dt,
    required double pace500m,
    required double spm,
    required bool isActive,
  }) {
    time += dt;
    final target = targetSpeedFor(pace500m: pace500m, isActive: isActive);
    speed += (target - speed) * math.min(1.0, dt / speedTau);
    if (target == 0 && speed < 0.01) speed = 0;
    distance += speed * dt;

    if (isActive && spm > 0) {
      strokePhase = (strokePhase + spm / 60 * dt) % 1.0;
    }

    final bladeIn = StrokeCycle.bladeInWater(strokePhase);
    if (_bladeWasIn && !bladeIn) {
      // Soltó la pala: un charco a cada lado, a la altura de las palas
      final sweep = StrokeCycle.oarSweep(strokePhase);
      final bladeZ = SceneCamera.boatZ - math.sin(sweep) * oarLength;
      for (final side in [-1.0, 1.0]) {
        puddles.add(Puddle(
          x: side * (riggerX + math.cos(sweep) * oarLength),
          worldZ: distance + bladeZ,
        ));
      }
    }
    _bladeWasIn = bladeIn;
    for (final p in puddles) {
      p.age += dt;
    }
    puddles.removeWhere((p) => p.age > puddleLife);

    pitch = 0.02 * math.sin(strokePhase * 2 * math.pi) + 0.006 * math.sin(time * 0.8);
  }
}
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/scene/scene_state_test.dart` → PASS. `flutter analyze lib/features/workout/scene` → sin issues.

```bash
git add lib/features/workout/scene/scene_state.dart test/scene/scene_state_test.dart
git commit -m "feat(scene): add SceneState (speed, distance, stroke phase, puddles)"
```

---

### Task 5: Shader de agua, carga y `WaterPainter` con fallback

**Files:** Create `shaders/water.frag`, `lib/features/workout/scene/water_shader.dart`, `lib/features/workout/scene/painters/water_painter.dart`; Modify `pubspec.yaml`; Test `test/scene/water_painter_test.dart`

- [ ] **Step 1: Declarar el shader en `pubspec.yaml`**

En la sección `flutter:`, después de `generate: true`:

```yaml
  shaders:
    - shaders/water.frag
```

- [ ] **Step 2: Escribir `shaders/water.frag`**

```glsl
#version 460 core
#include <flutter/runtime_effect.glsl>

// Agua en perspectiva: ondas, reflejo del cielo, brillo del sol, estela y niebla.
// Las coordenadas se invierten con la misma cámara que usa SceneCamera.

uniform vec2 uSize;
uniform float uHorizonY;
uniform float uFocal;
uniform float uCamHeight;
uniform float uDistance;
uniform float uTime;
uniform float uWaveAmp;
uniform float uWaveScale;
uniform float uSunX;
uniform float uSunY;
uniform float uLight;        // fuerza del brillo (0–1)
uniform vec3 uWaterNear;
uniform vec3 uWaterFar;
uniform vec3 uSkyHorizon;
uniform vec3 uSunColor;
uniform vec3 uFog;
uniform float uWakeStrength;
uniform float uSternZ;       // z de la popa: donde nace la estela

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float waveH(float x, float zw) {
  float s = uWaveScale;
  return sin(zw / s + uTime * 0.6) * 0.6
       + sin((zw * 0.7 + x * 1.3) / s + uTime * 0.9) * 0.4
       + (vnoise(vec2(x, zw) * 0.8 + uTime * 0.15) - 0.5) * 0.8;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  if (px.y <= uHorizonY + 0.5) {
    fragColor = vec4(0.0);
    return;
  }
  float z = uFocal * uCamHeight / (px.y - uHorizonY);
  float x = (px.x - uSize.x * 0.5) * z / uFocal;
  float zw = z + uDistance;

  float h = waveH(x, zw);
  float e = 0.15;
  float nx = (waveH(x + e, zw) - h) / e;
  float nz = (waveH(x, zw + e) - h) / e;

  vec3 col = mix(uWaterNear, uWaterFar, smoothstep(2.0, 120.0, z));
  col *= 1.0 + h * uWaveAmp * 0.25;

  // Fresnel: más espejo cuanto más rasante la mirada (lejos)
  float fres = pow(1.0 - clamp(uCamHeight / length(vec2(z, uCamHeight)), 0.0, 1.0), 3.0);
  col = mix(col, uSkyHorizon, fres * 0.6);

  // Brillo del sol/luna: columna bajo el astro, solo en las crestas
  float colW = 40.0 + z * 6.0;
  float dxs = (px.x - uSunX) / colW;
  float column = exp(-dxs * dxs);
  float crest = smoothstep(0.3, 0.9, h * 0.5 + 0.5 - abs(nx + nz) * 0.1);
  float sparkle = 0.3 + 0.7 * hash(floor(vec2(x * 4.0, zw * 4.0)));
  float glitter = column * crest * sparkle * uLight;
  col += uSunColor * glitter * 0.9;

  // Estela: dos líneas de espuma en V y turbulencia en el centro
  if (z < uSternZ) {
    float back = uSternZ - z;
    float wv = 0.3 + back * 0.35;
    float edge = 1.0 - smoothstep(0.0, 0.35, abs(abs(x) - wv));
    float center = (1.0 - smoothstep(0.0, 0.5, abs(x))) * 0.6;
    float fade = 1.0 - smoothstep(0.0, uSternZ, back);
    float n = 0.6 + 0.4 * vnoise(vec2(x * 3.0, zw * 2.0) + uTime);
    float foam = (edge + center) * fade * uWakeStrength * n;
    col = mix(col, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.5);
  }

  col = mix(col, uFog, smoothstep(80.0, 400.0, z));
  fragColor = vec4(col, 1.0);
}
```

- [ ] **Step 3: Test que falla (fallback y uniforms)**

`test/scene/water_painter_test.dart`:

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/painters/water_painter.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';
import 'package:rowmate/features/workout/scene/scene_state.dart';
import 'package:rowmate/features/workout/scene/time_of_day.dart';

void main() {
  test('sin shader pinta el fallback sin excepciones', () {
    const size = Size(390, 844);
    final cam = SceneCamera(size);
    final painter = WaterPainter(
      program: null,
      camera: cam,
      state: SceneState(),
      palette: TimeOfDay.paletteFor(12),
      light: TimeOfDay.lightFor(12, cam),
      environment: Environment.of(EnvironmentId.lake),
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    expect(recorder.endRecording(), isNotNull);
  });

  test('WaterPainter.uniforms devuelve 29 floats en el orden del shader', () {
    const size = Size(844, 390);
    final cam = SceneCamera(size);
    final state = SceneState()..speed = 2;
    final u = WaterPainter.uniforms(
      camera: cam,
      state: state,
      palette: TimeOfDay.paletteFor(12),
      light: TimeOfDay.lightFor(12, cam),
      environment: Environment.of(EnvironmentId.coast),
    );
    // uSize(2) + 10 floats + 5 vec3 (15) + wake + popa = 29
    expect(u, hasLength(29));
    expect(u[0], 844);
    expect(u[1], 390);
    expect(u[2], cam.horizonY);
    expect(u[7], 0.8); // waveAmplitude de la costa
    expect(u[27], closeTo(0.5, 1e-9)); // wake = speed / 4
    expect(u[28], SceneCamera.boatZ - 4.2); // popa
  });
}
```

Run: `flutter test test/scene/water_painter_test.dart` → falla.

- [ ] **Step 4: Implementar `water_shader.dart`**

```dart
import 'dart:ui';
import 'package:flutter/foundation.dart';

/// Carga y cachea el programa del shader de agua. Si falla (GPU sin soporte,
/// asset ausente), devuelve null y la escena usa el fallback pintado.
class WaterShader {
  WaterShader._();

  static Future<FragmentProgram?>? _loading;
  static FragmentProgram? program;

  static Future<FragmentProgram?> load() {
    return _loading ??= () async {
      try {
        program = await FragmentProgram.fromAsset('shaders/water.frag');
        return program;
      } catch (e) {
        debugPrint('[Scene] Shader de agua no disponible, usando fallback: $e');
        return null;
      }
    }();
  }
}
```

- [ ] **Step 5: Implementar `painters/water_painter.dart`**

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../environment.dart';
import '../scene_camera.dart';
import '../scene_state.dart';
import '../time_of_day.dart';

/// Agua bajo el horizonte: shader en GPU o, sin programa, un degradé con brillos.
class WaterPainter extends CustomPainter {
  WaterPainter({
    required this.program,
    required this.camera,
    required this.state,
    required this.palette,
    required this.light,
    required this.environment,
  });

  final ui.FragmentProgram? program;
  final SceneCamera camera;
  final SceneState state;
  final ScenePalette palette;
  final SceneLight light;
  final Environment environment;

  static const double sternOffset = 4.2;

  // Un FragmentShader por programa; se reutiliza entre frames
  static ui.FragmentShader? _shader;
  static ui.FragmentProgram? _shaderProgram;

  /// Uniforms en el orden exacto de `water.frag` (los vec se expanden).
  static List<double> uniforms({
    required SceneCamera camera,
    required SceneState state,
    required ScenePalette palette,
    required SceneLight light,
    required Environment environment,
  }) {
    final near = environment.tintWater(palette.waterNear);
    final far = environment.tintWater(palette.waterFar);
    return [
      camera.size.width, camera.size.height,
      camera.horizonY,
      camera.focal,
      SceneCamera.camHeight,
      state.distance,
      state.time,
      environment.waveAmplitude,
      environment.waveScale,
      light.position.dx,
      light.position.dy,
      light.strength,
      near.r, near.g, near.b,
      far.r, far.g, far.b,
      palette.skyHorizon.r, palette.skyHorizon.g, palette.skyHorizon.b,
      palette.sunColor.r, palette.sunColor.g, palette.sunColor.b,
      palette.fog.r, palette.fog.g, palette.fog.b,
      (state.speed / 4).clamp(0.0, 1.0),
      SceneCamera.boatZ - sternOffset,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, camera.horizonY, size.width, size.height - camera.horizonY);
    final p = program;
    if (p == null) {
      _paintFallback(canvas, rect);
      return;
    }
    if (_shaderProgram != p) {
      _shader = p.fragmentShader();
      _shaderProgram = p;
    }
    final shader = _shader!;
    final values = uniforms(
      camera: camera, state: state, palette: palette, light: light, environment: environment,
    );
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  void _paintFallback(Canvas canvas, Rect rect) {
    final near = environment.tintWater(palette.waterNear);
    final far = environment.tintWater(palette.waterFar);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(far, palette.fog, 0.5)!, far, near],
        ).createShader(rect),
    );
    // Brillos horizontales que avanzan con la distancia
    final shimmer = Paint()..strokeWidth = 1.5;
    for (var i = 0; i < 10; i++) {
      final t = ((i / 10) + (state.distance * 0.02) % 0.1) % 1.0;
      final y = rect.top + rect.height * t * t;
      final halfW = rect.width * (0.15 + 0.35 * t);
      shimmer.color = palette.sunColor.withValues(alpha: 0.05 + 0.1 * (1 - t) * light.strength);
      canvas.drawLine(
        Offset(light.position.dx - halfW, y),
        Offset(light.position.dx + halfW, y),
        shimmer,
      );
    }
  }

  @override
  bool shouldRepaint(WaterPainter old) => true;
}
```

- [ ] **Step 6: Verificar y commitear**

Run: `flutter test test/scene/water_painter_test.dart` → PASS. `flutter analyze lib/features/workout/scene` → sin issues. Run también `flutter build windows --debug --dart-define=SIMULATOR=true 2>&1 | tail -5` para comprobar que el shader compila (si hay un `rower_app.exe` corriendo y bloquea el build, cerrarlo con `Get-Process rower_app | Stop-Process`; es la app de desarrollo). Un error de GLSL aparece acá como `ShaderCompilerException`.

```bash
git add pubspec.yaml shaders/water.frag lib/features/workout/scene/water_shader.dart lib/features/workout/scene/painters/water_painter.dart test/scene/water_painter_test.dart
git commit -m "feat(scene): add GPU water shader with painted fallback"
```

---

### Task 6: `SkyPainter` y `ShorePainter`

**Files:** Create `lib/features/workout/scene/painters/sky_painter.dart`, `lib/features/workout/scene/painters/shore_painter.dart`; Test `test/scene/sky_shore_painter_test.dart`

- [ ] **Step 1: Test que falla**

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/painters/shore_painter.dart';
import 'package:rowmate/features/workout/scene/painters/sky_painter.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';
import 'package:rowmate/features/workout/scene/time_of_day.dart';

void main() {
  const sizes = [Size(390, 844), Size(844, 390)];

  for (final id in EnvironmentId.values) {
    for (final size in sizes) {
      for (final hour in [12.0, 23.0]) {
        test('$id ${size.width.toInt()}x${size.height.toInt()} ${hour}h pinta sin excepciones', () {
          final env = Environment.of(id);
          final cam = SceneCamera(size);
          final palette = TimeOfDay.paletteFor(hour);
          final light = TimeOfDay.lightFor(hour, cam);
          for (final distance in [0.0, 1234.0]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            SkyPainter(
              camera: cam, palette: palette, light: light, hour: hour,
              environment: env, distance: distance, time: 3.2,
            ).paint(canvas, size);
            ShorePainter(
              camera: cam, props: env.visibleProps(distance), distance: distance,
              palette: palette, time: 3.2,
            ).paint(canvas, size);
            expect(recorder.endRecording(), isNotNull);
          }
        });
      }
    }
  }

  test('objetos detrás de la cámara se omiten y un puente encima no rompe', () {
    const size = Size(390, 844);
    final cam = SceneCamera(size);
    final props = [
      const ShoreProp(x: 0, z: 100.3, kind: PropKind.bridge),   // relZ 0.3 → omitido
      const ShoreProp(x: 0, z: 101.0, kind: PropKind.bridge),   // relZ 1.0 → gigante
      const ShoreProp(x: -10.5, z: 130, kind: PropKind.distanceMarker, seed: 750),
      for (final k in PropKind.values) ShoreProp(x: 12, z: 120, kind: k, seed: 3),
    ];
    final recorder = ui.PictureRecorder();
    ShorePainter(
      camera: cam, props: props, distance: 100,
      palette: TimeOfDay.paletteFor(22), time: 0,
    ).paint(Canvas(recorder), size);
    expect(recorder.endRecording(), isNotNull);
  });
}
```

Run: `flutter test test/scene/sky_shore_painter_test.dart` → falla.

- [ ] **Step 2: Implementar `painters/sky_painter.dart`**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Cielo: degradé por hora, sol o luna, estrellas, nubes con parallax y la
/// silueta lejana del escenario.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.camera,
    required this.palette,
    required this.light,
    required this.hour,
    required this.environment,
    required this.distance,
    required this.time,
  });

  final SceneCamera camera;
  final ScenePalette palette;
  final SceneLight light;
  final double hour;
  final Environment environment;
  final double distance;
  final double time;

  // (x, y) como fracción de pantalla, tamaño en px, velocidad propia
  static const _cloudData = [
    (0.08, 0.10, 34.0, 1.0), (0.26, 0.18, 22.0, 1.4), (0.42, 0.07, 40.0, 0.8),
    (0.58, 0.22, 26.0, 1.2), (0.72, 0.12, 36.0, 0.9), (0.88, 0.20, 24.0, 1.3),
    (0.97, 0.05, 30.0, 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final hz = camera.horizonY;
    final skyRect = Rect.fromLTWH(0, 0, w, hz + 1);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.skyTop, palette.skyHorizon],
        ).createShader(skyRect),
    );
    if (TimeOfDay.isNight(hour)) _stars(canvas, w, hz);
    _sunOrMoon(canvas);
    _clouds(canvas, w, hz);
    environment.paintHorizon(canvas, size, camera, palette, distance, time);
  }

  void _stars(Canvas canvas, double w, double hz) {
    final rnd = math.Random(42);
    final paint = Paint();
    for (var i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * hz * 0.85;
      final r = 0.6 + rnd.nextDouble();
      final twinkle = 0.5 + 0.5 * math.sin(time * 2 + i);
      paint.color = Colors.white.withValues(alpha: 0.4 + 0.5 * twinkle);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _sunOrMoon(Canvas canvas) {
    final pos = light.position;
    const r = 22.0;
    canvas.drawCircle(
      pos,
      r * 4,
      Paint()
        ..shader = RadialGradient(colors: [
          palette.sunGlow.withValues(alpha: 0.7),
          palette.sunGlow.withValues(alpha: 0.25),
          palette.sunGlow.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: pos, radius: r * 4)),
    );
    canvas.drawCircle(pos, r, Paint()..color = palette.sunColor);
    if (light.isMoon) {
      // Luna en cuarto: un disco del color del cielo tapa parte del astro
      canvas.drawCircle(pos.translate(r * 0.4, -r * 0.15), r * 0.92, Paint()..color = palette.skyTop);
    }
  }

  void _clouds(Canvas canvas, double w, double hz) {
    final body = Paint()..color = Colors.white.withValues(alpha: 0.15 + 0.55 * palette.ambient);
    final shade = Paint()..color = palette.skyTop.withValues(alpha: 0.18);
    for (final (fx, fy, s, speed) in _cloudData) {
      final x = ((fx + distance * 0.0004 * speed + time * 0.004 * speed) % 1.2) * w - w * 0.1;
      final y = hz * fy;
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y + s * 0.25), width: s * 2.6, height: s * 0.9), body);
      canvas.drawCircle(Offset(x - s * 0.6, y), s * 0.6, body);
      canvas.drawCircle(Offset(x, y - s * 0.2), s * 0.8, body);
      canvas.drawCircle(Offset(x + s * 0.7, y + s * 0.05), s * 0.55, body);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y + s * 0.5), width: s * 2.2, height: s * 0.4), shade);
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) => true;
}
```

- [ ] **Step 3: Implementar `painters/shore_painter.dart`**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Objetos de la orilla proyectados por la cámara. Cada objeto se dibuja en
/// un sistema local en metros (y negativo = arriba) escalado a su distancia.
class ShorePainter extends CustomPainter {
  ShorePainter({
    required this.camera,
    required this.props,
    required this.distance,
    required this.palette,
    required this.time,
  });

  final SceneCamera camera;

  /// Ya ordenados de lejos a cerca.
  final List<ShoreProp> props;
  final double distance;
  final ScenePalette palette;
  final double time;

  bool get _night => palette.ambient < 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    for (final prop in props) {
      final relZ = prop.z - distance;
      final base = camera.project(prop.x, 0, relZ);
      if (base == null) continue;
      final s = camera.scaleAt(relZ) * prop.scale;
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.scale(s, s);
      _draw(canvas, prop, relZ);
      canvas.restore();
      if (prop.kind == PropKind.distanceMarker) _markerText(canvas, prop, base, s);
    }
  }

  /// Color teñido por la luz ambiente y la niebla de distancia.
  Color _c(Color c, double relZ) {
    final a = palette.ambient;
    final lit = Color.from(alpha: 1, red: c.r * a, green: c.g * a, blue: c.b * math.min(1.0, a + 0.12));
    final f = ((relZ - 80) / 320).clamp(0.0, 1.0);
    return Color.lerp(lit, palette.fog, f * 0.8)!;
  }

  Paint _p(Color c, double relZ) => Paint()..color = _c(c, relZ);

  void _draw(Canvas c, ShoreProp prop, double z) {
    switch (prop.kind) {
      case PropKind.pine:
        _pine(c, prop, z);
      case PropKind.cabin:
        _cabin(c, z);
      case PropKind.pier:
        _pier(c, prop, z);
      case PropKind.building:
        _building(c, prop, z);
      case PropKind.boathouse:
        _boathouse(c, z);
      case PropKind.bridge:
        _bridge(c, z);
      case PropKind.laneBuoy:
        _buoy(c, prop, z);
      case PropKind.lamp:
        _lamp(c, z);
      case PropKind.cliff:
        _cliff(c, prop, z);
      case PropKind.lighthouse:
        _lighthouse(c, z);
      case PropKind.beachUmbrella:
        _umbrella(c, prop, z);
      case PropKind.grandstand:
        _grandstand(c, z);
      case PropKind.finishTower:
        _finishTower(c, z);
      case PropKind.flag:
        _flag(c, prop, z);
      case PropKind.distanceMarker:
        _marker(c, z);
    }
  }

  void _pine(Canvas c, ShoreProp prop, double z) {
    const greens = [
      [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)],
      [Color(0xFF145A32), Color(0xFF1E8449), Color(0xFF27AE60)],
      [Color(0xFF2E5E2A), Color(0xFF3E7B38), Color(0xFF4F9A48)],
    ][prop.seed % 3];
    c.drawRect(const Rect.fromLTWH(-0.15, -1.0, 0.3, 1.0), _p(const Color(0xFF5D4037), z));
    for (var i = 0; i < 3; i++) {
      final base = -0.8 - i * 1.5;
      final half = 1.3 - i * 0.3;
      c.drawPath(
        Path()
          ..moveTo(0, base - 2.2)
          ..lineTo(-half, base)
          ..lineTo(half, base)
          ..close(),
        _p(greens[i], z),
      );
    }
  }

  void _cabin(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-2, -2.6, 4, 2.6), _p(const Color(0xFF6D4C41), z));
    c.drawPath(
      Path()
        ..moveTo(-2.4, -2.6)
        ..lineTo(0, -4.2)
        ..lineTo(2.4, -2.6)
        ..close(),
      _p(const Color(0xFF4E342E), z),
    );
    c.drawRect(const Rect.fromLTWH(-0.4, -1.4, 0.8, 1.4), _p(const Color(0xFF3E2723), z));
    c.drawRect(const Rect.fromLTWH(0.7, -2.0, 0.8, 0.7),
        Paint()..color = _night ? const Color(0xFFFFE082) : _c(const Color(0xFF90CAF9), z));
  }

  void _pier(Canvas c, ShoreProp prop, double z) {
    final dir = prop.x < 0 ? 1.0 : -1.0; // hacia el centro del río
    c.drawRect(Rect.fromLTWH(dir < 0 ? -3 : 0, -0.4, 3, 0.4), _p(const Color(0xFF8D6E63), z));
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(dir * (0.3 + i * 1.2) - 0.1, -0.1, 0.2, 0.7), _p(const Color(0xFF5D4037), z));
    }
  }

  void _building(Canvas c, ShoreProp prop, double z) {
    final floors = 3 + prop.seed % 4;
    final h = floors * 3.0;
    final tone = [const Color(0xFF78909C), const Color(0xFF8D6E63), const Color(0xFFB0BEC5)][prop.seed % 3];
    c.drawRect(Rect.fromLTWH(-3, -h, 6, h), _p(tone, z));
    final rnd = math.Random(prop.seed);
    for (var f = 0; f < floors; f++) {
      for (var i = 0; i < 3; i++) {
        final lit = _night && rnd.nextDouble() < 0.6;
        c.drawRect(
          Rect.fromLTWH(-2.4 + i * 1.8, -h + 0.8 + f * 3, 1.0, 1.2),
          Paint()..color = lit ? const Color(0xFFFFE082) : _c(const Color(0xFF263238), z),
        );
      }
    }
  }

  void _boathouse(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-4, -4, 8, 4), _p(const Color(0xFFB0BEC5), z));
    c.drawPath(
      Path()
        ..moveTo(-4.5, -4)
        ..lineTo(0, -6)
        ..lineTo(4.5, -4)
        ..close(),
      _p(const Color(0xFF546E7A), z),
    );
    c.drawRect(const Rect.fromLTWH(-1.5, -2.8, 3, 2.8), _p(const Color(0xFF37474F), z));
    c.drawRect(const Rect.fromLTWH(-3.6, -3.6, 7.2, 0.4), _p(const Color(0xFF1565C0), z));
  }

  void _bridge(Canvas c, double z) {
    // Cara de piedra con el arco recortado, pilares, tablero y parapeto
    c.drawPath(
      Path()
        ..moveTo(-9.5, -6)
        ..lineTo(-9.5, -1.5)
        ..lineTo(-8.5, -1.5)
        ..quadraticBezierTo(0, -8.5, 8.5, -1.5)
        ..lineTo(9.5, -1.5)
        ..lineTo(9.5, -6)
        ..close(),
      _p(const Color(0xFF9E9E9E), z),
    );
    final pillar = _p(const Color(0xFF757575), z);
    c.drawRect(const Rect.fromLTWH(-9.5, -1.5, 1, 1.5), pillar);
    c.drawRect(const Rect.fromLTWH(8.5, -1.5, 1, 1.5), pillar);
    c.drawRect(const Rect.fromLTWH(-12, -7.2, 24, 1.2), _p(const Color(0xFF7A7A7A), z));
    c.drawRect(const Rect.fromLTWH(-12, -7.7, 24, 0.5), _p(const Color(0xFF616161), z));
  }

  void _buoy(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFE53935), const Color(0xFFFDD835), const Color(0xFFECEFF1)][prop.seed % 3];
    c.drawCircle(const Offset(0, -0.2), 0.25, _p(color, z));
    c.drawLine(const Offset(-0.2, 0.2), const Offset(0.2, 0.2),
        Paint()..color = Colors.white.withValues(alpha: 0.25)..strokeWidth = 0.08);
  }

  void _lamp(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-0.06, -4, 0.12, 4), _p(const Color(0xFF455A64), z));
    if (_night) {
      c.drawCircle(const Offset(0, -4.1), 1.5,
          Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.35));
      c.drawCircle(const Offset(0, -4.1), 0.3, Paint()..color = const Color(0xFFFFF8E1));
    } else {
      c.drawCircle(const Offset(0, -4.1), 0.3, _p(const Color(0xFF90A4AE), z));
    }
  }

  void _cliff(Canvas c, ShoreProp prop, double z) {
    final dir = prop.x < 0 ? -1.0 : 1.0; // se extiende hacia afuera del agua
    final rnd = math.Random(prop.seed);
    final path = Path()..moveTo(0, 0)..lineTo(0, -8);
    for (var i = 1; i <= 5; i++) {
      path.lineTo(dir * i * 1.4, -8 - rnd.nextDouble() * 1.5 + 0.4 * i);
    }
    path
      ..lineTo(dir * 7, 0)
      ..close();
    c.drawPath(path, _p(const Color(0xFF5D4A42), z));
    c.drawRect(Rect.fromLTWH(dir < 0 ? -7 : 0, -8.6, 7, 0.9), _p(const Color(0xFF556B2F), z));
    c.drawRect(const Rect.fromLTWH(-0.3, -1.2, 0.6, 1.2), _p(const Color(0xFF3E2F2A), z));
  }

  void _lighthouse(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-1.1, -9, 2.2, 9), _p(const Color(0xFFECEFF1), z));
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(-1.1, -8 + i * 3.0, 2.2, 1.0), _p(const Color(0xFFD32F2F), z));
    }
    c.drawRect(const Rect.fromLTWH(-0.8, -10.2, 1.6, 1.2), _p(const Color(0xFF37474F), z));
    if (_night) {
      c.drawCircle(const Offset(0, -9.6), 3,
          Paint()..color = const Color(0xFFFFF59D).withValues(alpha: 0.35));
    }
  }

  void _umbrella(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFF06292), const Color(0xFF4FC3F7), const Color(0xFFFFD54F)][prop.seed % 3];
    c.drawRect(const Rect.fromLTWH(-0.04, -2.2, 0.08, 2.2), _p(const Color(0xFF5D4037), z));
    c.drawArc(const Rect.fromLTWH(-0.9, -3.1, 1.8, 1.8), math.pi, math.pi, true, _p(color, z));
    c.drawRect(const Rect.fromLTWH(0.3, -0.1, 1.2, 0.1), _p(const Color(0xFFFFF3E0), z));
  }

  void _grandstand(Canvas c, double z) {
    for (var i = 0; i < 4; i++) {
      c.drawRect(Rect.fromLTWH(-6, -1.2 * (i + 1), 12, 1.2),
          _p(i.isEven ? const Color(0xFF8D9DAE) : const Color(0xFF6E7B8C), z));
    }
    c.drawRect(const Rect.fromLTWH(-6.5, -5.3, 13, 0.5), _p(const Color(0xFF37474F), z));
  }

  void _finishTower(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-1.5, -10, 3, 10), _p(const Color(0xFFCFD8DC), z));
    c.drawRect(const Rect.fromLTWH(-1.5, -9, 3, 1.2), _p(const Color(0xFF263238), z));
    c.drawCircle(const Offset(0, -6.5), 0.6, _p(Colors.white, z));
    c.drawLine(const Offset(0, -6.5), const Offset(0, -7.0), Paint()..color = Colors.black..strokeWidth = 0.08);
    c.drawLine(const Offset(0, -6.5), const Offset(0.35, -6.5), Paint()..color = Colors.black..strokeWidth = 0.08);
    c.drawLine(const Offset(0, -10), const Offset(0, -11.5), Paint()..color = _c(const Color(0xFF90A4AE), z)..strokeWidth = 0.1);
  }

  void _flag(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFE53935), const Color(0xFFFFB300), const Color(0xFF1E88E5), const Color(0xFF43A047)][prop.seed % 4];
    final wave = math.sin(time * 4 + prop.seed) * 0.2;
    c.drawRect(const Rect.fromLTWH(-0.05, -5, 0.1, 5), _p(const Color(0xFF9E9E9E), z));
    c.drawPath(
      Path()
        ..moveTo(0, -5)
        ..lineTo(1.6, -4.6 + wave)
        ..lineTo(0, -4.0)
        ..close(),
      _p(color, z),
    );
  }

  void _marker(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-0.05, -1.5, 0.1, 1.5), _p(const Color(0xFF9E9E9E), z));
    c.drawRect(const Rect.fromLTWH(-0.9, -2.5, 1.8, 1.0), _p(const Color(0xFFFAFAFA), z));
  }

  /// El texto del cartel se pinta en píxeles de pantalla (TextPainter no
  /// trabaja bien con tamaños en metros).
  void _markerText(Canvas canvas, ShoreProp prop, Offset base, double s) {
    final fontSize = 0.55 * s;
    if (fontSize < 4) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '${prop.seed} m',
        style: TextStyle(color: Colors.black87, fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(base.dx - tp.width / 2, base.dy - 2.0 * s - tp.height / 2));
  }

  @override
  bool shouldRepaint(ShorePainter old) => true;
}
```

- [ ] **Step 4: Verificar y commitear**

Run: `flutter test test/scene/sky_shore_painter_test.dart` → PASS. `flutter analyze lib/features/workout/scene test/scene` → sin issues.

```bash
git add lib/features/workout/scene/painters/sky_painter.dart lib/features/workout/scene/painters/shore_painter.dart test/scene/sky_shore_painter_test.dart
git commit -m "feat(scene): add SkyPainter and ShorePainter"
```

---

### Task 7: `BoatPainter` (bote, remero, remos, salpicaduras, charcos)

**Files:** Create `lib/features/workout/scene/painters/boat_painter.dart`; Test `test/scene/boat_painter_test.dart`

Nota de geometría (corrige el spec, que decía "de espaldas"): el remero rema **mirando hacia la popa**, es decir, de cara a la cámara. Los pies van hacia la popa (`z` menor, más cerca de la cámara) y la espalda hacia la proa. En el catch el carro está cerca de los pies y el tronco inclinado hacia la cámara; en el finish el carro va hacia la proa y el tronco se inclina hacia atrás (alejándose). La pala entra hacia la proa (`z` mayor) y sale hacia la popa. `z` crece hacia la proa.

- [ ] **Step 1: Test que falla**

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/painters/boat_painter.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';
import 'package:rowmate/features/workout/scene/scene_state.dart';
import 'package:rowmate/features/workout/scene/time_of_day.dart';

void main() {
  test('geometría de la palada: catch hacia la cámara, pala hacia la proa', () {
    const bz = SceneCamera.boatZ;
    // Carro: en el catch está más cerca de la cámara (z menor) que en el finish
    expect(BoatPainter.seatZ(0), lessThan(BoatPainter.seatZ(0.36)));
    // Mango: en el catch más cerca de la cámara; en el finish hacia la proa
    expect(BoatPainter.handle(1, 0).$3, lessThan(bz));
    expect(BoatPainter.handle(1, 0.36).$3, greaterThan(bz));
    // Pala: en el catch hacia la proa, en el finish hacia la popa
    expect(BoatPainter.bladeTip(1, 0).$3, greaterThan(bz + 2));
    expect(BoatPainter.bladeTip(1, 0.36).$3, lessThan(bz));
    // Lados espejados
    expect(BoatPainter.bladeTip(-1, 0.1).$1, -BoatPainter.bladeTip(1, 0.1).$1);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    test('${size.width.toInt()}x${size.height.toInt()} pinta todas las fases sin excepciones', () {
      final cam = SceneCamera(size);
      final state = SceneState();
      // Charcos a ambos lados y uno ya detrás de la cámara
      state.puddles.addAll([
        Puddle(x: -3.0, worldZ: 6.3)..age = 1,
        Puddle(x: 3.0, worldZ: 6.3)..age = 3.5,
        Puddle(x: 3.0, worldZ: 0.2)..age = 2,
      ]);
      for (final p in [0.0, 0.05, 0.2, 0.36, 0.39, 0.5, 0.8, 0.99]) {
        state.strokePhase = p;
        final recorder = ui.PictureRecorder();
        BoatPainter(
          camera: cam, state: state,
          palette: TimeOfDay.paletteFor(12), light: TimeOfDay.lightFor(12, cam),
        ).paint(Canvas(recorder), size);
        expect(recorder.endRecording(), isNotNull);
      }
    });
  }
}
```

Run: `flutter test test/scene/boat_painter_test.dart` → falla.

- [ ] **Step 2: Implementar `painters/boat_painter.dart`**

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../scene_camera.dart';
import '../scene_state.dart';
import '../stroke_cycle.dart';
import '../time_of_day.dart';

typedef _P3 = (double x, double y, double z);

/// Single visto desde atrás con el remero de cara a la cámara (rema mirando
/// a la popa), remos con pala que entra y sale, salpicaduras y charcos.
class BoatPainter extends CustomPainter {
  BoatPainter({
    required this.camera,
    required this.state,
    required this.palette,
    required this.light,
  });

  final SceneCamera camera;
  final SceneState state;
  final ScenePalette palette;
  final SceneLight light;

  static const double hullY = 0.08;
  static const double sternZ = SceneCamera.boatZ - 4.2;
  static const double bowZ = SceneCamera.boatZ + 4.0;
  static const double riggerX = SceneState.riggerX;
  static const double oarLength = SceneState.oarLength;
  static const double inboard = 0.9;
  static const double feetZ = SceneCamera.boatZ - 1.15;
  static const double hipY = 0.25;

  /// z del carro: en el catch (legs = 0) va hacia la popa, cerca de los pies.
  static double seatZ(double p) => SceneCamera.boatZ - 0.6 * (1 - StrokeCycle.legs(p));

  /// Mango del remo (donde van las manos).
  static _P3 handle(double side, double p) {
    final sweep = StrokeCycle.oarSweep(p);
    return (
      side * (riggerX - math.cos(sweep) * inboard),
      0.45,
      SceneCamera.boatZ + math.sin(sweep) * inboard,
    );
  }

  /// Punta de la pala.
  static _P3 bladeTip(double side, double p) {
    final sweep = StrokeCycle.oarSweep(p);
    final inWater = StrokeCycle.bladeInWater(p);
    return (
      side * (riggerX + math.cos(sweep) * oarLength),
      inWater ? -0.05 : 0.35,
      SceneCamera.boatZ - math.sin(sweep) * oarLength,
    );
  }

  Color _c(Color c) {
    final a = palette.ambient;
    return Color.from(alpha: 1, red: c.r * a, green: c.g * a, blue: c.b * math.min(1.0, a + 0.12));
  }

  Paint _paint(Color c) => Paint()..color = _c(c);

  /// Altura del casco en z, con cabeceo (+ = proa arriba).
  double _hy(double z) => hullY + (z - SceneCamera.boatZ) * math.sin(state.pitch);

  Offset? _pr(_P3 p) => camera.project(p.$1, p.$2, p.$3);

  @override
  void paint(Canvas canvas, Size size) {
    final p = state.strokePhase;
    _puddles(canvas);
    _shadow(canvas);
    _hull(canvas);
    _rower(canvas, p);
    _oars(canvas, p);
  }

  void _line(Canvas c, _P3 a, _P3 b, double widthM, Paint paint) {
    final pa = _pr(a);
    final pb = _pr(b);
    if (pa == null || pb == null) return;
    paint
      ..strokeWidth = math.max(1, widthM * camera.scaleAt((a.$3 + b.$3) / 2))
      ..strokeCap = StrokeCap.round;
    c.drawLine(pa, pb, paint);
  }

  void _fillQuad(Canvas c, List<_P3> pts, Paint paint) {
    final screen = <Offset>[];
    for (final p in pts) {
      final o = _pr(p);
      if (o == null) return;
      screen.add(o);
    }
    c.drawPath(Path()..addPolygon(screen, true), paint);
  }

  void _puddles(Canvas c) {
    for (final pd in state.puddles) {
      final relZ = pd.worldZ - state.distance;
      final o = camera.project(pd.x, 0, relZ);
      if (o == null) continue;
      final s = camera.scaleAt(relZ);
      final t = pd.age / SceneState.puddleLife;
      final r = (0.3 + 0.9 * t) * s;
      c.drawOval(
        Rect.fromCenter(center: o, width: r * 2, height: r * 0.7),
        Paint()
          ..color = Colors.white.withValues(alpha: (1 - t) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 0.06 * s),
      );
    }
  }

  void _shadow(Canvas c) {
    final ox = light.position.dx < camera.centerX ? 0.7 : -0.7;
    final a = camera.project(ox, 0, bowZ);
    final b = camera.project(ox, 0, sternZ);
    if (a == null || b == null) return;
    final w = 0.9 * camera.scaleAt(SceneCamera.boatZ);
    c.drawOval(
      Rect.fromLTRB(math.min(a.dx, b.dx) - w / 2, a.dy, math.max(a.dx, b.dx) + w / 2, b.dy),
      Paint()..color = Colors.black.withValues(alpha: 0.22 * palette.ambient),
    );
  }

  void _hull(Canvas c) {
    const bz = SceneCamera.boatZ;
    const left = <(double, double)>[
      (-0.14, sternZ), (-0.28, bz - 1.5), (-0.26, bz + 0.5), (-0.12, bz + 2.5), (0.0, bowZ),
    ];
    final pts = <Offset>[];
    for (final (x, z) in left) {
      final o = camera.project(x, _hy(z), z);
      if (o == null) return;
      pts.add(o);
    }
    for (final (x, z) in left.reversed.skip(1)) {
      pts.add(camera.project(-x, _hy(z), z)!);
    }
    final path = Path()..addPolygon(pts, true);
    c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_c(const Color(0xFFF5F5F5)), _c(const Color(0xFFB0BEC5))],
        ).createShader(path.getBounds()),
    );
    c.drawPath(
      path,
      Paint()
        ..color = _c(const Color(0xFF00B4D8))
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 0.03 * camera.scaleAt(bz)),
    );
    // Hueco del remero
    _fillQuad(c, [
      (-0.17, _hy(bz - 1.4) + 0.02, bz - 1.4),
      (0.17, _hy(bz - 1.4) + 0.02, bz - 1.4),
      (0.17, _hy(bz + 0.3) + 0.02, bz + 0.3),
      (-0.17, _hy(bz + 0.3) + 0.02, bz + 0.3),
    ], _paint(const Color(0xFF263238)));
  }

  void _rower(Canvas c, double p) {
    final legs = StrokeCycle.legs(p);
    final lean = StrokeCycle.torsoLean(p); // + hacia la popa (hacia la cámara)
    final sz = seatZ(p);
    final kneeZ = (sz + feetZ) / 2 - 0.1 * (1 - legs);
    final kneeY = 0.25 + 0.4 * (1 - legs);
    final shZ = sz - 0.55 * math.sin(lean);
    final shY = hipY + 0.55 * math.cos(lean);
    final headZ = shZ - 0.08 * math.sin(lean);
    final headY = shY + 0.24;
    final suit = _paint(const Color(0xFF1565C0));
    final skin = _paint(const Color(0xFFFFCC80));
    final hair = _paint(const Color(0xFF3E2723));
    final dark = _paint(const Color(0xFF0D3B6E));

    // Carro
    _fillQuad(c, [
      (-0.2, hipY - 0.03, sz - 0.2), (0.2, hipY - 0.03, sz - 0.2),
      (0.2, hipY - 0.03, sz + 0.2), (-0.2, hipY - 0.03, sz + 0.2),
    ], dark);
    // Tronco: trapecio cadera → hombros
    _fillQuad(c, [
      (-0.17, hipY, sz), (0.17, hipY, sz), (0.24, shY, shZ), (-0.24, shY, shZ),
    ], suit);
    // Cabeza con pelo
    final head = camera.project(0, headY, headZ);
    if (head != null) {
      final r = 0.12 * camera.scaleAt(headZ);
      c.drawCircle(head, r, skin);
      c.drawArc(Rect.fromCircle(center: head, radius: r * 1.02), math.pi, math.pi, true, hair);
    }
    // Brazos: hombro → mango del remo
    for (final side in [-1.0, 1.0]) {
      final h = handle(side, p);
      _line(c, (side * 0.22, shY, shZ), h, 0.09, suit);
      final hp = _pr(h);
      if (hp != null) c.drawCircle(hp, 0.05 * camera.scaleAt(h.$3), skin);
    }
    // Piernas: muslo cadera → rodilla, pantorrilla rodilla → pie (lo más cercano)
    for (final side in [-1.0, 1.0]) {
      _line(c, (side * 0.12, hipY, sz), (side * 0.14, kneeY, kneeZ), 0.16, suit);
      _line(c, (side * 0.14, kneeY, kneeZ), (side * 0.12, 0.15, feetZ), 0.12, skin);
      final f = camera.project(side * 0.12, 0.15, feetZ);
      if (f != null) c.drawCircle(f, 0.07 * camera.scaleAt(feetZ), dark);
    }
  }

  void _oars(Canvas c, double p) {
    const bz = SceneCamera.boatZ;
    final inWater = StrokeCycle.bladeInWater(p);
    final shaft = _paint(const Color(0xFFBCAAA4));
    final blade = _paint(const Color(0xFF00B4D8));
    final rigger = _paint(const Color(0xFF90A4AE));
    for (final side in [-1.0, 1.0]) {
      final pivot = (side * riggerX, 0.15, bz);
      final tip = bladeTip(side, p);
      final h = handle(side, p);
      _line(c, (side * 0.3, 0.12, bz), pivot, 0.05, rigger);
      _line(c, h, pivot, 0.06, shaft);
      _line(c, pivot, tip, 0.06, shaft);
      final tp = _pr(tip);
      if (tp == null) continue;
      final s = camera.scaleAt(tip.$3);
      if (inWater) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: tp, width: 0.25 * s, height: 0.5 * s),
            Radius.circular(0.05 * s),
          ),
          blade,
        );
        if (p < 0.08) _splash(c, tp, s, p / 0.08);
      } else {
        c.drawOval(Rect.fromCenter(center: tp, width: 0.5 * s, height: 0.12 * s), blade);
      }
    }
  }

  /// Gotas que suben y caen en el catch; t ∈ [0, 1].
  void _splash(Canvas c, Offset tp, double s, double t) {
    final paint = Paint()..color = Colors.white.withValues(alpha: (1 - t) * 0.8);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (i - 2.5) * 0.35;
      final d = (0.15 + 0.35 * t) * s;
      final rise = math.sin(t * math.pi) * 0.25 * s;
      c.drawCircle(
        Offset(tp.dx + math.cos(a) * d, tp.dy + math.sin(a) * d * 0.5 - rise),
        (0.03 + 0.02 * (1 - t)) * s,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BoatPainter old) => true;
}
```

- [ ] **Step 3: Verificar y commitear**

Run: `flutter test test/scene/boat_painter_test.dart` → PASS. `flutter analyze lib/features/workout/scene test/scene` → sin issues.

```bash
git add lib/features/workout/scene/painters/boat_painter.dart test/scene/boat_painter_test.dart
git commit -m "feat(scene): add BoatPainter with articulated rower and oars"
```

---

### Task 8: Selección de escenario, miniaturas, l10n y hora forzada en el simulador

**Files:** Create `lib/features/workout/scene/scene_settings.dart`, `lib/features/workout/scene/painters/thumbnail_painter.dart`, `lib/features/workout/scene/environment_picker.dart`; Modify `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/main.dart`, `lib/features/workout/workout_screen.dart`, `lib/core/dev/simulator_overlay.dart`, `test/simulator_overlay_test.dart`; Test `test/scene/environment_picker_test.dart`

- [ ] **Step 1: Textos**

En `lib/l10n/app_en.arb`, después de la línea `"workoutInProgress": ...,` agregar:

```json
  "workoutScene": "Scenery",
  "sceneLake": "Alpine lake",
  "sceneRiver": "City river",
  "sceneCoast": "Coast",
  "sceneRegatta": "Regatta course",
```

En `lib/l10n/app_es.arb`, en el mismo lugar:

```json
  "workoutScene": "Escenario",
  "sceneLake": "Lago alpino",
  "sceneRiver": "Río urbano",
  "sceneCoast": "Costa",
  "sceneRegatta": "Canal de regata",
```

Run: `flutter gen-l10n` → regenera `lib/l10n/app_localizations*.dart` (están versionados: incluirlos en el commit).

- [ ] **Step 2: Test que falla**

`test/scene/environment_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/environment_picker.dart';
import 'package:rowmate/features/workout/scene/scene_settings.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tocar una tarjeta cambia el escenario y lo persiste', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SceneSettings();
    await tester.pumpWidget(
      ChangeNotifierProvider<SceneSettings>.value(
        value: settings,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: EnvironmentPicker()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.environmentId, EnvironmentId.lake);
    expect(find.text('Lago alpino'), findsOneWidget);

    await tester.tap(find.text('Río urbano'));
    await tester.pumpAndSettle();
    expect(settings.environmentId, EnvironmentId.river);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SceneSettings.prefKey), 'river');
  });

  testWidgets('arranca con el escenario guardado', (tester) async {
    SharedPreferences.setMockInitialValues({SceneSettings.prefKey: 'coast'});
    final settings = SceneSettings();
    await tester.pump(const Duration(milliseconds: 50));
    expect(settings.environmentId, EnvironmentId.coast);
  });
}
```

Run: `flutter test test/scene/environment_picker_test.dart` → falla.

- [ ] **Step 3: Implementar `scene_settings.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'environment.dart';

/// Escenario elegido (persistido) y hora forzada para el modo simulador.
class SceneSettings extends ChangeNotifier {
  SceneSettings() {
    _load();
  }

  static const prefKey = 'scene.environment';

  EnvironmentId _environmentId = EnvironmentId.lake;
  double? _hourOverride;
  bool _touched = false; // si el usuario eligió antes de que termine _load, gana él

  EnvironmentId get environmentId => _environmentId;

  /// Solo en modo simulador: hora de la escena en lugar de la real.
  double? get hourOverride => _hourOverride;
  set hourOverride(double? h) {
    _hourOverride = h;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = EnvironmentId.values.asNameMap()[prefs.getString(prefKey)];
    if (!_touched && id != null && id != _environmentId) {
      _environmentId = id;
      notifyListeners();
    }
  }

  Future<void> setEnvironment(EnvironmentId id) async {
    _touched = true;
    if (id == _environmentId) return;
    _environmentId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, id.name);
  }
}
```

- [ ] **Step 4: Implementar `painters/thumbnail_painter.dart`**

```dart
import 'package:flutter/material.dart';
import '../environment.dart';
import '../scene_camera.dart';
import '../scene_state.dart';
import '../time_of_day.dart';
import 'shore_painter.dart';
import 'sky_painter.dart';
import 'water_painter.dart';

/// Miniatura estática de un escenario a las 12:00, sin remero.
class ThumbnailPainter extends CustomPainter {
  ThumbnailPainter(this.environment);

  final Environment environment;

  static const double _distance = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = SceneCamera(size);
    final palette = TimeOfDay.paletteFor(12);
    final light = TimeOfDay.lightFor(12, cam);
    SkyPainter(
      camera: cam, palette: palette, light: light, hour: 12,
      environment: environment, distance: _distance, time: 0,
    ).paint(canvas, size);
    WaterPainter(
      program: null, camera: cam, state: SceneState()..distance = _distance,
      palette: palette, light: light, environment: environment,
    ).paint(canvas, size);
    ShorePainter(
      camera: cam, props: environment.visibleProps(_distance), distance: _distance,
      palette: palette, time: 0,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) => old.environment.id != environment.id;
}
```

- [ ] **Step 5: Implementar `environment_picker.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'environment.dart';
import 'painters/thumbnail_painter.dart';
import 'scene_settings.dart';

String environmentName(EnvironmentId id, AppLocalizations l10n) => switch (id) {
      EnvironmentId.lake => l10n.sceneLake,
      EnvironmentId.river => l10n.sceneRiver,
      EnvironmentId.coast => l10n.sceneCoast,
      EnvironmentId.regatta => l10n.sceneRegatta,
    };

/// Fila horizontal de tarjetas con miniatura para elegir el escenario.
class EnvironmentPicker extends StatelessWidget {
  const EnvironmentPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SceneSettings>();
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EnvironmentId.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final id = EnvironmentId.values[i];
          final selected = id == settings.environmentId;
          return GestureDetector(
            onTap: () => settings.setEnvironment(id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 80,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? const Color(0xFF00B4D8) : Colors.white12,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: CustomPaint(painter: ThumbnailPainter(Environment.of(id))),
                ),
                const SizedBox(height: 6),
                Text(
                  environmentName(id, l10n),
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Registrar el provider y mostrar el selector**

`lib/main.dart`: agregar `import 'features/workout/scene/scene_settings.dart';` junto a los imports de features, y en la lista de providers, después de `ChangeNotifierProvider(create: (_) => HistoryProvider(db)),`:

```dart
        ChangeNotifierProvider(create: (_) => SceneSettings()),
```

`lib/features/workout/workout_screen.dart`: agregar `import 'scene/environment_picker.dart';` después de `import 'immersive_workout_screen.dart';`. En `_IdleView.build`, justo antes de `FilledButton.icon(`:

```dart
            Text(l10n.workoutScene,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 8),
            const EnvironmentPicker(),
            const SizedBox(height: 16),

```

- [ ] **Step 7: Hora forzada en el panel del simulador**

`lib/core/dev/simulator_overlay.dart`: agregar `import '../../features/workout/scene/scene_settings.dart';`. En `_SimulatorPanelState.build`, al principio: `final scene = context.read<SceneSettings>(); final hour = scene.hourOverride;`. Después del `_StepperRow` de 'Ritmo' agregar:

```dart
              _StepperRow(
                label: 'Hora escena',
                value: hour == null ? 'real' : '${hour.round() % 24}:00',
                keyPrefix: 'sim-hour',
                onMinus: () => setState(() => scene.hourOverride = ((hour ?? _nowHour()) - 1) % 24),
                onPlus: () => setState(() => scene.hourOverride = ((hour ?? _nowHour()) + 1) % 24),
              ),
              if (hour != null)
                TextButton(
                  onPressed: () => setState(() => scene.hourOverride = null),
                  child: const Text('Hora real'),
                ),
```

y el método `double _nowHour() => DateTime.now().hour.toDouble();` en `_SimulatorPanelState`.

`test/simulator_overlay_test.dart`: en ambos tests envolver con `MultiProvider` y mockear prefs:

```dart
    SharedPreferences.setMockInitialValues({});
    ...
      MultiProvider(
        providers: [
          Provider<BleService>.value(value: ble),
          ChangeNotifierProvider(create: (_) => SceneSettings()),
        ],
        child: MaterialApp(...igual que antes...),
      ),
```

(imports: `package:shared_preferences/shared_preferences.dart`, `package:rowmate/features/workout/scene/scene_settings.dart`). En el primer test, después del tap a `sim-spm-plus`, agregar:

```dart
    await tester.tap(find.byKey(const Key('sim-hour-plus')));
    await tester.pump();
    expect(find.text('Hora real'), findsOneWidget);
```

- [ ] **Step 8: Verificar y commitear**

Run: `flutter test` (toda la suite) → PASS. `flutter analyze lib test` → sin issues nuevos de nivel error/warning.

```bash
git add lib/l10n lib/features/workout/scene/scene_settings.dart lib/features/workout/scene/painters/thumbnail_painter.dart lib/features/workout/scene/environment_picker.dart lib/main.dart lib/features/workout/workout_screen.dart lib/core/dev/simulator_overlay.dart test/simulator_overlay_test.dart test/scene/environment_picker_test.dart
git commit -m "feat(scene): add scenery picker, SceneSettings and simulator hour override"
```

---

### Task 9: `SceneView`, integración en la pantalla inmersiva y verificación

**Files:** Create `lib/features/workout/scene/scene_view.dart`; Modify `lib/features/workout/immersive_workout_screen.dart`, `CLAUDE.md`; Test `test/scene/scene_view_test.dart`

- [ ] **Step 1: Test que falla**

`test/scene/scene_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/rowing_data.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/scene_view.dart';

void main() {
  for (final id in EnvironmentId.values) {
    for (final size in const [Size(390, 844), Size(844, 390)]) {
      for (final hour in [12.0, 23.0]) {
        testWidgets('$id ${size.width.toInt()}x${size.height.toInt()} ${hour}h anima sin excepciones',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SceneView(
                environment: Environment.of(id),
                data: const RowingData(strokeRate: 24, pace500mSeconds: 110, distanceMeters: 300),
                isActive: true,
                hourOverride: hour,
              ),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          // Desmontar: el Ticker y la carga del shader no deben romper
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
```

Run: `flutter test test/scene/scene_view_test.dart` → falla.

- [ ] **Step 2: Implementar `scene_view.dart`**

```dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/models/rowing_data.dart';
import 'environment.dart';
import 'painters/boat_painter.dart';
import 'painters/shore_painter.dart';
import 'painters/sky_painter.dart';
import 'painters/water_painter.dart';
import 'scene_camera.dart';
import 'scene_state.dart';
import 'time_of_day.dart';
import 'water_shader.dart';

/// Escena 2.5D completa (cielo, agua, orilla, bote) animada con un solo Ticker.
class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.environment,
    required this.data,
    required this.isActive,
    this.hourOverride,
  });

  final Environment environment;
  final RowingData data;

  /// true solo con el entrenamiento en marcha (ni en pausa ni terminado).
  final bool isActive;

  /// Hora de la escena en lugar de la real (modo simulador).
  final double? hourOverride;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final SceneState _state = SceneState();
  Duration _last = Duration.zero;
  ui.FragmentProgram? _program = WaterShader.program;

  @override
  void initState() {
    super.initState();
    if (_program == null) {
      WaterShader.load().then((p) {
        if (mounted && p != null) setState(() => _program = p);
      });
    }
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // dt acotado: tras una pausa del sistema no saltar la escena
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _state.update(
      dt: dt,
      pace500m: widget.data.pace500mSeconds.toDouble(),
      spm: widget.data.strokeRate,
      isActive: widget.isActive,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double get _hour {
    final o = widget.hourOverride;
    if (o != null) return o;
    final n = DateTime.now();
    return n.hour + n.minute / 60;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final cam = SceneCamera(size);
      final hour = _hour;
      final palette = TimeOfDay.paletteFor(hour);
      final light = TimeOfDay.lightFor(hour, cam);
      final env = widget.environment;
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: SkyPainter(
              camera: cam, palette: palette, light: light, hour: hour,
              environment: env, distance: _state.distance, time: _state.time,
            ),
          ),
          CustomPaint(
            painter: WaterPainter(
              program: _program, camera: cam, state: _state,
              palette: palette, light: light, environment: env,
            ),
          ),
          CustomPaint(
            painter: ShorePainter(
              camera: cam, props: env.visibleProps(_state.distance),
              distance: _state.distance, palette: palette, time: _state.time,
            ),
          ),
          CustomPaint(
            painter: BoatPainter(camera: cam, state: _state, palette: palette, light: light),
          ),
        ],
      );
    });
  }
}
```

- [ ] **Step 3: Integrar en `immersive_workout_screen.dart`**

1. Imports: después de `import 'series_panels.dart';` agregar
   ```dart
   import 'scene/environment.dart';
   import 'scene/scene_settings.dart';
   import 'scene/scene_view.dart';
   ```
2. `_ImmersiveWorkoutPageState`: quitar `with TickerProviderStateMixin`, los campos `_strokeController`, `_cloudController`, `_wakeController`, `_lastSpm`, su creación en `initState` y su `dispose`, y el método `_updateAvatarAnimationFromSpm` completo. `initState` queda solo con `super.initState()` y `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`; `dispose` solo con `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` y `super.dispose()`.
3. En `build`: eliminar la llamada `_updateAvatarAnimationFromSpm(...)`. Después de `final sp = w.stepProgress;` agregar `final scene = context.watch<SceneSettings>();`.
4. Reemplazar los dos primeros hijos del `Stack` (los bloques `// ── 1. Outdoor background` y `// ── 2. Rowing avatar`, cada uno un `AnimatedBuilder` con `CustomPaint`) por:
   ```dart
            // ── 1+2. Escena 2.5D: cielo, agua, orilla y bote ───────
            SceneView(
              environment: Environment.of(scene.environmentId),
              data: w.data,
              isActive: w.phase == WorkoutPhase.active,
              hourOverride: scene.hourOverride,
            ),
   ```
5. Borrar las clases `_OutdoorScenePainter` y `_RowingAvatarPainter` completas (desde el banner `// OUTDOOR SCENE PAINTER` hasta justo antes del banner `// STAGE TIMELINE BAR`).
6. `flutter analyze lib/features/workout/immersive_workout_screen.dart`: si `dart:math` quedó sin uso, quitar el import. El warning preexistente de `device_provider.dart` sin uso se deja como está.

- [ ] **Step 4: Documentar en `CLAUDE.md`**

En la sección "Feature Layer", en el bullet de **workout/**, después de la frase sobre `ImmersiveWorkoutPage`, agregar:

```markdown
  - **[scene/](lib/features/workout/scene/)**: 2.5D chase-camera scene engine used by the immersive page. `SceneCamera` projects world meters (x lateral, z forward, y up; camera 2.2 m high, rower at z = 8) to pixels; `SceneState` integrates real speed (`500 / split`), distance, stroke phase and oar puddles once per frame from a single `Ticker` in `SceneView`; `StrokeCycle` encodes the legs → back → arms sequence (drive 0–0.40, recovery 0.40–1.0); `TimeOfDay` gives the palette/light for the wall-clock hour; `Environment` (lake, river, coast, regatta) generates shore props deterministically per 50 m segment. Painters: `SkyPainter`, `WaterPainter` (GLSL `shaders/water.frag` via `WaterShader`, with a painted fallback when the program can't load), `ShorePainter`, `BoatPainter` (rower faces the camera: rowers face the stern). Scenery is chosen in the idle view (`EnvironmentPicker` → `SceneSettings`, persisted in SharedPreferences `scene.environment`); the simulator panel can force the scene hour (`SceneSettings.hourOverride`).
```

- [ ] **Step 5: Verificar**

Run: `flutter test` → toda la suite PASS. `flutter analyze` → ningún `error`; no agregar warnings nuevos.

Run (controller): `flutter run -d windows --dart-define=SIMULATOR=true` y capturar la pantalla inmersiva con el mecanismo de `PrintWindow` ya usado, en los 4 escenarios y con "Hora escena" en 6, 12, 18 y 22. Confirmar: el paisaje viene hacia la cámara y acelera con el preset "Fuerte"; el agua refleja el cielo y brilla bajo el sol; el bote cabecea; el remero hace piernas → espalda → brazos; las palas entran (salpicadura) y salen (charco); la estela aparece detrás de la popa; el HUD y los paneles siguen iguales.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workout/scene/scene_view.dart lib/features/workout/immersive_workout_screen.dart test/scene/scene_view_test.dart CLAUDE.md
git commit -m "feat(scene): render immersive page with the 2.5D scene engine"
```
