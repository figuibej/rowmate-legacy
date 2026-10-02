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
