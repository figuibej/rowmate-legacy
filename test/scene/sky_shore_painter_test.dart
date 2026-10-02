import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide TimeOfDay;
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
