import 'package:flutter/material.dart' hide TimeOfDay;
import '../environment.dart';
import '../scene_camera.dart';
import '../scene_state.dart';
import '../time_of_day.dart';
import 'shore_painter.dart';
import 'sky_painter.dart';
import 'water_painter.dart';

/// Miniatura estática de un escenario a las 12:00, sin remero.
class ThumbnailPainter extends CustomPainter {
  ThumbnailPainter(this.environment);

  final Environment environment;

  static const double _distance = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = SceneCamera(size);
    final palette = TimeOfDay.paletteFor(12);
    final light = TimeOfDay.lightFor(12, cam);
    SkyPainter(
      camera: cam, palette: palette, light: light, hour: 12,
      environment: environment, distance: _distance, time: 0,
    ).paint(canvas, size);
    WaterPainter(
      shader: null, camera: cam, state: SceneState()..distance = _distance,
      palette: palette, light: light, environment: environment,
    ).paint(canvas, size);
    // En miniatura alcanza con los 150 m más cercanos: lo lejano no se distingue
    final props = environment
        .visibleProps(_distance)
        .where((p) => p.z < _distance + 150)
        .toList();
    ShorePainter(
      camera: cam, props: props, distance: _distance,
      palette: palette, time: 0,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) => old.environment.id != environment.id;
}
