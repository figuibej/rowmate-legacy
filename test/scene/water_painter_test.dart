import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide TimeOfDay;
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
      shader: null,
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

  test('WaterPainter.uniforms devuelve 28 floats en el orden del shader', () {
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
    // uSize(2) + 9 floats + 5 vec3 (15) + wake + popa = 28
    expect(u, hasLength(28));
    expect(u[0], 844);
    expect(u[1], 390);
    expect(u[2], cam.horizonY);
    expect(u[7], 0.8); // waveAmplitude de la costa
    expect(u[9], cam.size.width / 2, reason: 'uSunX al mediodía'); // sol centrado
    expect(u[26], closeTo(0.5, 1e-9)); // wake = speed / 4
    expect(u[27], SceneCamera.boatZ - 4.2); // popa
  });
}
