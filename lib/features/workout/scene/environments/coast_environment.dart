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
