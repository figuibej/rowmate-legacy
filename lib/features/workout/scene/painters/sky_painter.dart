import 'dart:math' as math;
import 'package:flutter/material.dart' hide TimeOfDay;
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Cielo: degradé por hora, sol o luna, estrellas, nubes con parallax y la
/// silueta lejana del escenario.
class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.camera,
    required this.palette,
    required this.light,
    required this.hour,
    required this.environment,
    required this.distance,
    required this.time,
  });

  final SceneCamera camera;
  final ScenePalette palette;
  final SceneLight light;
  final double hour;
  final Environment environment;
  final double distance;
  final double time;

  // (x, y) como fracción de pantalla, tamaño en px, velocidad propia
  static const _cloudData = [
    (0.08, 0.10, 34.0, 1.0), (0.26, 0.18, 22.0, 1.4), (0.42, 0.07, 40.0, 0.8),
    (0.58, 0.22, 26.0, 1.2), (0.72, 0.12, 36.0, 0.9), (0.88, 0.20, 24.0, 1.3),
    (0.97, 0.05, 30.0, 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final hz = camera.horizonY;
    final skyRect = Rect.fromLTWH(0, 0, w, hz + 1);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.skyTop, palette.skyHorizon],
        ).createShader(skyRect),
    );
    // Las estrellas aparecen a medida que oscurece (ambient 1 → 0.35), no
    // recién con la noche cerrada: así el atardecer las va revelando.
    final darkness = ((1 - palette.ambient) / 0.65).clamp(0.0, 1.0);
    if (darkness > 0) _stars(canvas, w, hz, darkness);
    _sunOrMoon(canvas);
    _clouds(canvas, w, hz);
    environment.paintHorizon(canvas, size, camera, palette, distance, time);
  }

  void _stars(Canvas canvas, double w, double hz, double darkness) {
    final rnd = math.Random(42);
    final paint = Paint();
    for (var i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * hz * 0.85;
      final r = 0.6 + rnd.nextDouble();
      final twinkle = 0.5 + 0.5 * math.sin(time * 2 + i);
      paint.color = Colors.white.withValues(alpha: (0.4 + 0.5 * twinkle) * darkness);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _sunOrMoon(Canvas canvas) {
    final pos = light.position;
    const r = 22.0;
    canvas.drawCircle(
      pos,
      r * 4,
      Paint()
        ..shader = RadialGradient(colors: [
          palette.sunGlow.withValues(alpha: 0.7),
          palette.sunGlow.withValues(alpha: 0.25),
          palette.sunGlow.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: pos, radius: r * 4)),
    );
    // Luna: disco pálido algo más chico; sol: disco pleno
    canvas.drawCircle(pos, light.isMoon ? r * 0.8 : r, Paint()..color = palette.sunColor);
  }

  void _clouds(Canvas canvas, double w, double hz) {
    // Nubes suaves: el borde se funde con un degradé radial (sin MaskFilter,
    // que costaba una pasada offscreen por figura) y casi invisibles de noche
    final alpha = 0.08 + 0.5 * palette.ambient * palette.ambient;
    final body = Color.lerp(Colors.white, palette.skyHorizon, 0.25)!.withValues(alpha: alpha);
    final shade = palette.skyTop.withValues(alpha: 0.12 * palette.ambient);
    for (final (fx, fy, s, speed) in _cloudData) {
      final x = ((fx + distance * 0.0004 * speed + time * 0.004 * speed) % 1.2) * w - w * 0.1;
      final y = hz * (0.12 + fy * 0.6);
      _blob(canvas, Rect.fromCenter(center: Offset(x, y + s * 0.25), width: s * 2.6, height: s * 0.8), body);
      _blob(canvas, Rect.fromCircle(center: Offset(x - s * 0.6, y), radius: s * 0.5), body);
      _blob(canvas, Rect.fromCircle(center: Offset(x, y - s * 0.15), radius: s * 0.65), body);
      _blob(canvas, Rect.fromCircle(center: Offset(x + s * 0.7, y + s * 0.05), radius: s * 0.45), body);
      _blob(canvas, Rect.fromCenter(center: Offset(x, y + s * 0.5), width: s * 2.0, height: s * 0.3), shade);
    }
  }

  /// Óvalo que ocupa [rect], opaco hasta el 55 % del radio y transparente en
  /// el borde. Se dibuja como círculo bajo una escala no uniforme porque
  /// `RadialGradient.createShader` toma el lado más corto del rect como radio.
  void _blob(Canvas canvas, Rect rect, Color color) {
    final r = rect.height / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.55, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(rect.width / rect.height, 1);
    canvas.drawCircle(Offset.zero, r, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPainter old) => true;
}
