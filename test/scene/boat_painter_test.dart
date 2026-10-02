import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide TimeOfDay;
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
