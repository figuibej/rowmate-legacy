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
