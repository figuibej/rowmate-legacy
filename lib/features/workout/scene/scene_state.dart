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
