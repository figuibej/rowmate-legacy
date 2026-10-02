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
    if (TimeOfDay.isNight(hour)) _stars(canvas, w, hz);
    _sunOrMoon(canvas);
    _clouds(canvas, w, hz);
    environment.paintHorizon(canvas, size, camera, palette, distance, time);
  }

  void _stars(Canvas canvas, double w, double hz) {
    final rnd = math.Random(42);
    final paint = Paint();
    // Las estrellas aparecen a medida que oscurece (ambient 1 → 0.35)
    final darkness = ((1 - palette.ambient) / 0.65).clamp(0.0, 1.0);
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
    // Nubes suaves: bordes difuminados y casi invisibles de noche
    final alpha = 0.08 + 0.5 * palette.ambient * palette.ambient;
    final body = Paint()
      ..color = Color.lerp(Colors.white, palette.skyHorizon, 0.25)!.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final shade = Paint()
      ..color = palette.skyTop.withValues(alpha: 0.12 * palette.ambient)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final (fx, fy, s, speed) in _cloudData) {
      final x = ((fx + distance * 0.0004 * speed + time * 0.004 * speed) % 1.2) * w - w * 0.1;
      final y = hz * (0.12 + fy * 0.6);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y + s * 0.25), width: s * 2.6, height: s * 0.8), body);
      canvas.drawCircle(Offset(x - s * 0.6, y), s * 0.5, body);
      canvas.drawCircle(Offset(x, y - s * 0.15), s * 0.65, body);
      canvas.drawCircle(Offset(x + s * 0.7, y + s * 0.05), s * 0.45, body);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y + s * 0.5), width: s * 2.0, height: s * 0.3), shade);
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) => true;
}
