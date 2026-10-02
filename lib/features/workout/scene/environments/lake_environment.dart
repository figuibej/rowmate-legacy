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
