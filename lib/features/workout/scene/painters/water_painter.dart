import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../environment.dart';
import '../scene_camera.dart';
import '../scene_state.dart';
import '../time_of_day.dart';

/// Agua bajo el horizonte: shader en GPU o, sin él, un degradé con brillos.
///
/// El [shader] lo crea y libera quien posee el painter (`_SceneViewState`);
/// acá solo se le cargan los uniforms de cada frame.
class WaterPainter extends CustomPainter {
  WaterPainter({
    required this.shader,
    required this.camera,
    required this.state,
    required this.palette,
    required this.light,
    required this.environment,
  });

  final ui.FragmentShader? shader;
  final SceneCamera camera;
  final SceneState state;
  final ScenePalette palette;
  final SceneLight light;
  final Environment environment;

  static const double sternOffset = 4.2;

  /// Uniforms en el orden exacto de `water.frag` (los vec se expanden).
  static List<double> uniforms({
    required SceneCamera camera,
    required SceneState state,
    required ScenePalette palette,
    required SceneLight light,
    required Environment environment,
  }) {
    final near = environment.tintWater(palette.waterNear);
    final far = environment.tintWater(palette.waterFar);
    return [
      camera.size.width, camera.size.height,
      camera.horizonY,
      camera.focal,
      SceneCamera.camHeight,
      state.shaderDistance,
      state.time,
      environment.waveAmplitude,
      environment.waveScale,
      light.position.dx,
      light.strength,
      near.r, near.g, near.b,
      far.r, far.g, far.b,
      palette.skyHorizon.r, palette.skyHorizon.g, palette.skyHorizon.b,
      palette.sunColor.r, palette.sunColor.g, palette.sunColor.b,
      palette.fog.r, palette.fog.g, palette.fog.b,
      (state.speed / 4).clamp(0.0, 1.0),
      SceneCamera.boatZ - sternOffset,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, camera.horizonY, size.width, size.height - camera.horizonY);
    final s = shader;
    if (s == null) {
      _paintFallback(canvas, rect);
      return;
    }
    final values = uniforms(
      camera: camera, state: state, palette: palette, light: light, environment: environment,
    );
    for (var i = 0; i < values.length; i++) {
      s.setFloat(i, values[i]);
    }
    canvas.drawRect(rect, Paint()..shader = s);
  }

  void _paintFallback(Canvas canvas, Rect rect) {
    final near = environment.tintWater(palette.waterNear);
    final far = environment.tintWater(palette.waterFar);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(far, palette.fog, 0.5)!, far, near],
        ).createShader(rect),
    );
    // Brillos horizontales que avanzan con la distancia
    final shimmer = Paint()..strokeWidth = 1.5;
    for (var i = 0; i < 10; i++) {
      final t = ((i / 10) + (state.distance * 0.02) % 0.1) % 1.0;
      final y = rect.top + rect.height * t * t;
      final halfW = rect.width * (0.15 + 0.35 * t);
      shimmer.color = palette.sunColor.withValues(alpha: 0.05 + 0.1 * (1 - t) * light.strength);
      canvas.drawLine(
        Offset(light.position.dx - halfW, y),
        Offset(light.position.dx + halfW, y),
        shimmer,
      );
    }
  }

  @override
  bool shouldRepaint(WaterPainter old) => true;
}
