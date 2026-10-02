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
