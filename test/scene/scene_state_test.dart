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
