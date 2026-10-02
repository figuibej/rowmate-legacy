import 'dart:math' as math;
import 'dart:ui';
import 'scene_camera.dart';

/// Colores de la escena para una hora dada.
class ScenePalette {
  const ScenePalette({
    required this.skyTop,
    required this.skyHorizon,
    required this.waterNear,
    required this.waterFar,
    required this.sunColor,
    required this.sunGlow,
    required this.fog,
    required this.ambient,
  });

  final Color skyTop;
  final Color skyHorizon;
  final Color waterNear;
  final Color waterFar;
  final Color sunColor;
  final Color sunGlow;
  final Color fog;

  /// Multiplicador de luz para orilla y bote (1 = día, 0.35 = noche).
  final double ambient;

  static ScenePalette lerp(ScenePalette a, ScenePalette b, double t) => ScenePalette(
        skyTop: Color.lerp(a.skyTop, b.skyTop, t)!,
        skyHorizon: Color.lerp(a.skyHorizon, b.skyHorizon, t)!,
        waterNear: Color.lerp(a.waterNear, b.waterNear, t)!,
        waterFar: Color.lerp(a.waterFar, b.waterFar, t)!,
        sunColor: Color.lerp(a.sunColor, b.sunColor, t)!,
        sunGlow: Color.lerp(a.sunGlow, b.sunGlow, t)!,
        fog: Color.lerp(a.fog, b.fog, t)!,
        ambient: a.ambient + (b.ambient - a.ambient) * t,
      );
}

/// Sol o luna: posición en pantalla y fuerza del brillo sobre el agua.
class SceneLight {
  const SceneLight({required this.position, required this.strength, required this.isMoon});
  final Offset position;
  final double strength; // 0–1
  final bool isMoon;
}

class TimeOfDay {
  TimeOfDay._();

  static double sunElevation(double hour) => math.sin((hour - 6) / 12 * math.pi);
  /// Luna en vez de sol recién cuando el cielo dejó de ser atardecer
  /// (elevación ≤ −0.4: ≈19:35 a ≈4:25).
  static bool isNight(double hour) => sunElevation(hour) <= -0.4;

  static SceneLight lightFor(double hour, SceneCamera cam) {
    final night = isNight(hour);
    final h = night ? (hour + 12) % 24 : hour;
    final elev = math.sin((h - 6) / 12 * math.pi).clamp(0.0, 1.0);
    final fx = (0.25 + 0.5 * (h - 6) / 12).clamp(0.15, 0.85);
    return SceneLight(
      position: Offset(cam.size.width * fx, cam.horizonY - elev * cam.horizonY * 0.9),
      strength: night ? 0.45 : (elev * 1.2).clamp(0.2, 1.0),
      isMoon: night,
    );
  }

  static const _dawn = ScenePalette(
    skyTop: Color(0xFF2A1B5E), skyHorizon: Color(0xFFFF9A5C),
    waterNear: Color(0xFF1A2B4A), waterFar: Color(0xFF3A2F55),
    sunColor: Color(0xFFFFB070), sunGlow: Color(0xFFFF7A3D),
    fog: Color(0xFFC98A7A), ambient: 0.7);
  static const _morning = ScenePalette(
    skyTop: Color(0xFF3A7BD5), skyHorizon: Color(0xFFFFD9A0),
    waterNear: Color(0xFF1E5A9E), waterFar: Color(0xFF5C8FC9),
    sunColor: Color(0xFFFFE4A0), sunGlow: Color(0xFFFFC46B),
    fog: Color(0xFFDCE8F5), ambient: 0.95);
  static const _noon = ScenePalette(
    skyTop: Color(0xFF0B4FA8), skyHorizon: Color(0xFF8FD3FF),
    waterNear: Color(0xFF0E4F8F), waterFar: Color(0xFF2F8FD6),
    sunColor: Color(0xFFFFF6D5), sunGlow: Color(0xFFFFE9A6),
    fog: Color(0xFFCFE9FF), ambient: 1.0);
  static const _sunset = ScenePalette(
    skyTop: Color(0xFF2E3C8C), skyHorizon: Color(0xFFFF8C5A),
    waterNear: Color(0xFF163A66), waterFar: Color(0xFF7C5C7A),
    sunColor: Color(0xFFFFB36B), sunGlow: Color(0xFFFF6B3D),
    fog: Color(0xFFE0A28A), ambient: 0.85);
  static const _dusk = ScenePalette(
    skyTop: Color(0xFF0D1A4A), skyHorizon: Color(0xFF4A3A7A),
    waterNear: Color(0xFF0B1E3A), waterFar: Color(0xFF2A2A55),
    sunColor: Color(0xFFDDE6FF), sunGlow: Color(0xFF8FA3FF),
    fog: Color(0xFF30335A), ambient: 0.5);
  static const _night = ScenePalette(
    skyTop: Color(0xFF050A1E), skyHorizon: Color(0xFF121C3A),
    waterNear: Color(0xFF06122A), waterFar: Color(0xFF0E1E3C),
    sunColor: Color(0xFFE6EEFF), sunGlow: Color(0xFFA6B8FF),
    fog: Color(0xFF0F1730), ambient: 0.35);

  // Keyframes cíclicos: 22 h → 5 h del día siguiente (29). La noche se mantiene
  // cerrada hasta las 4 h (28) para que la medianoche no sea un falso amanecer.
  static const _keys = <(double, ScenePalette)>[
    (5, _dawn), (7, _morning), (12, _noon), (18, _sunset), (20, _dusk), (22, _night),
    (28, _night), (29, _dawn),
  ];

  static ScenePalette paletteFor(double hour) {
    var h = hour % 24;
    if (h < 5) h += 24;
    for (var i = 0; i < _keys.length - 1; i++) {
      final (h0, p0) = _keys[i];
      final (h1, p1) = _keys[i + 1];
      if (h >= h0 && h <= h1) return ScenePalette.lerp(p0, p1, (h - h0) / (h1 - h0));
    }
    return _night;
  }
}
