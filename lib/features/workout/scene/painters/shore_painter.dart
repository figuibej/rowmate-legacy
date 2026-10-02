import 'dart:math' as math;
import 'package:flutter/material.dart' hide TimeOfDay;
import '../environment.dart';
import '../scene_camera.dart';
import '../time_of_day.dart';

/// Objetos de la orilla proyectados por la cámara. Cada objeto se dibuja en
/// un sistema local en metros (y negativo = arriba) escalado a su distancia.
class ShorePainter extends CustomPainter {
  ShorePainter({
    required this.camera,
    required this.props,
    required this.distance,
    required this.palette,
    required this.time,
  });

  final SceneCamera camera;

  /// Ya ordenados de lejos a cerca.
  final List<ShoreProp> props;
  final double distance;
  final ScenePalette palette;
  final double time;

  bool get _night => palette.ambient < 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    for (final prop in props) {
      final relZ = prop.z - distance;
      final base = camera.project(prop.x, 0, relZ);
      if (base == null) continue;
      final s = camera.scaleAt(relZ) * prop.scale;
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.scale(s, s);
      _draw(canvas, prop, relZ);
      canvas.restore();
      if (prop.kind == PropKind.distanceMarker) _markerText(canvas, prop, base, s);
    }
  }

  /// Color teñido por la luz ambiente y la niebla de distancia.
  Color _c(Color c, double relZ) {
    final a = palette.ambient;
    final lit = Color.from(alpha: 1, red: c.r * a, green: c.g * a, blue: c.b * math.min(1.0, a + 0.12));
    final f = ((relZ - 80) / 320).clamp(0.0, 1.0);
    return Color.lerp(lit, palette.fog, f * 0.8)!;
  }

  Paint _p(Color c, double relZ) => Paint()..color = _c(c, relZ);

  void _draw(Canvas c, ShoreProp prop, double z) {
    switch (prop.kind) {
      case PropKind.pine:
        _pine(c, prop, z);
      case PropKind.cabin:
        _cabin(c, z);
      case PropKind.pier:
        _pier(c, prop, z);
      case PropKind.building:
        _building(c, prop, z);
      case PropKind.boathouse:
        _boathouse(c, z);
      case PropKind.bridge:
        _bridge(c, z);
      case PropKind.laneBuoy:
        _buoy(c, prop, z);
      case PropKind.lamp:
        _lamp(c, z);
      case PropKind.cliff:
        _cliff(c, prop, z);
      case PropKind.lighthouse:
        _lighthouse(c, z);
      case PropKind.beachUmbrella:
        _umbrella(c, prop, z);
      case PropKind.grandstand:
        _grandstand(c, z);
      case PropKind.finishTower:
        _finishTower(c, z);
      case PropKind.flag:
        _flag(c, prop, z);
      case PropKind.distanceMarker:
        _marker(c, z);
    }
  }

  void _pine(Canvas c, ShoreProp prop, double z) {
    final greens = const [
      [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)],
      [Color(0xFF145A32), Color(0xFF1E8449), Color(0xFF27AE60)],
      [Color(0xFF2E5E2A), Color(0xFF3E7B38), Color(0xFF4F9A48)],
    ][prop.seed % 3];
    c.drawRect(const Rect.fromLTWH(-0.15, -1.0, 0.3, 1.0), _p(const Color(0xFF5D4037), z));
    for (var i = 0; i < 3; i++) {
      final base = -0.8 - i * 1.5;
      final half = 1.3 - i * 0.3;
      c.drawPath(
        Path()
          ..moveTo(0, base - 2.2)
          ..lineTo(-half, base)
          ..lineTo(half, base)
          ..close(),
        _p(greens[i], z),
      );
    }
  }

  void _cabin(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-2, -2.6, 4, 2.6), _p(const Color(0xFF6D4C41), z));
    c.drawPath(
      Path()
        ..moveTo(-2.4, -2.6)
        ..lineTo(0, -4.2)
        ..lineTo(2.4, -2.6)
        ..close(),
      _p(const Color(0xFF4E342E), z),
    );
    c.drawRect(const Rect.fromLTWH(-0.4, -1.4, 0.8, 1.4), _p(const Color(0xFF3E2723), z));
    c.drawRect(const Rect.fromLTWH(0.7, -2.0, 0.8, 0.7),
        Paint()..color = _night ? const Color(0xFFFFE082) : _c(const Color(0xFF90CAF9), z));
  }

  void _pier(Canvas c, ShoreProp prop, double z) {
    final dir = prop.x < 0 ? 1.0 : -1.0; // hacia el centro del río
    c.drawRect(Rect.fromLTWH(dir < 0 ? -3 : 0, -0.4, 3, 0.4), _p(const Color(0xFF8D6E63), z));
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(dir * (0.3 + i * 1.2) - 0.1, -0.1, 0.2, 0.7), _p(const Color(0xFF5D4037), z));
    }
  }

  void _building(Canvas c, ShoreProp prop, double z) {
    final floors = 3 + prop.seed % 4;
    final h = floors * 3.0;
    final tone = [const Color(0xFF78909C), const Color(0xFF8D6E63), const Color(0xFFB0BEC5)][prop.seed % 3];
    c.drawRect(Rect.fromLTWH(-3, -h, 6, h), _p(tone, z));
    final rnd = math.Random(prop.seed);
    for (var f = 0; f < floors; f++) {
      for (var i = 0; i < 3; i++) {
        final lit = _night && rnd.nextDouble() < 0.6;
        c.drawRect(
          Rect.fromLTWH(-2.4 + i * 1.8, -h + 0.8 + f * 3, 1.0, 1.2),
          Paint()..color = lit ? const Color(0xFFFFE082) : _c(const Color(0xFF263238), z),
        );
      }
    }
  }

  void _boathouse(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-4, -4, 8, 4), _p(const Color(0xFFB0BEC5), z));
    c.drawPath(
      Path()
        ..moveTo(-4.5, -4)
        ..lineTo(0, -6)
        ..lineTo(4.5, -4)
        ..close(),
      _p(const Color(0xFF546E7A), z),
    );
    c.drawRect(const Rect.fromLTWH(-1.5, -2.8, 3, 2.8), _p(const Color(0xFF37474F), z));
    c.drawRect(const Rect.fromLTWH(-3.6, -3.6, 7.2, 0.4), _p(const Color(0xFF1565C0), z));
  }

  void _bridge(Canvas c, double z) {
    // Cara de piedra con el arco recortado, pilares, tablero y parapeto
    c.drawPath(
      Path()
        ..moveTo(-9.5, -6)
        ..lineTo(-9.5, -1.5)
        ..lineTo(-8.5, -1.5)
        ..quadraticBezierTo(0, -8.5, 8.5, -1.5)
        ..lineTo(9.5, -1.5)
        ..lineTo(9.5, -6)
        ..close(),
      _p(const Color(0xFF9E9E9E), z),
    );
    final pillar = _p(const Color(0xFF757575), z);
    c.drawRect(const Rect.fromLTWH(-9.5, -1.5, 1, 1.5), pillar);
    c.drawRect(const Rect.fromLTWH(8.5, -1.5, 1, 1.5), pillar);
    c.drawRect(const Rect.fromLTWH(-12, -7.2, 24, 1.2), _p(const Color(0xFF7A7A7A), z));
    c.drawRect(const Rect.fromLTWH(-12, -7.7, 24, 0.5), _p(const Color(0xFF616161), z));
  }

  void _buoy(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFE53935), const Color(0xFFFDD835), const Color(0xFFECEFF1)][prop.seed % 3];
    c.drawCircle(const Offset(0, -0.2), 0.25, _p(color, z));
    c.drawLine(const Offset(-0.2, 0.2), const Offset(0.2, 0.2),
        Paint()..color = Colors.white.withValues(alpha: 0.25)..strokeWidth = 0.08);
  }

  void _lamp(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-0.06, -4, 0.12, 4), _p(const Color(0xFF455A64), z));
    if (_night) {
      c.drawCircle(const Offset(0, -4.1), 1.5,
          Paint()..color = const Color(0xFFFFE082).withValues(alpha: 0.35));
      c.drawCircle(const Offset(0, -4.1), 0.3, Paint()..color = const Color(0xFFFFF8E1));
    } else {
      c.drawCircle(const Offset(0, -4.1), 0.3, _p(const Color(0xFF90A4AE), z));
    }
  }

  void _cliff(Canvas c, ShoreProp prop, double z) {
    final dir = prop.x < 0 ? -1.0 : 1.0; // se extiende hacia afuera del agua
    final rnd = math.Random(prop.seed);
    final path = Path()..moveTo(0, 0)..lineTo(0, -8);
    for (var i = 1; i <= 5; i++) {
      path.lineTo(dir * i * 1.4, -8 - rnd.nextDouble() * 1.5 + 0.4 * i);
    }
    path
      ..lineTo(dir * 7, 0)
      ..close();
    c.drawPath(path, _p(const Color(0xFF5D4A42), z));
    c.drawRect(Rect.fromLTWH(dir < 0 ? -7 : 0, -8.6, 7, 0.9), _p(const Color(0xFF556B2F), z));
    c.drawRect(const Rect.fromLTWH(-0.3, -1.2, 0.6, 1.2), _p(const Color(0xFF3E2F2A), z));
  }

  void _lighthouse(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-1.1, -9, 2.2, 9), _p(const Color(0xFFECEFF1), z));
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(-1.1, -8 + i * 3.0, 2.2, 1.0), _p(const Color(0xFFD32F2F), z));
    }
    c.drawRect(const Rect.fromLTWH(-0.8, -10.2, 1.6, 1.2), _p(const Color(0xFF37474F), z));
    if (_night) {
      c.drawCircle(const Offset(0, -9.6), 3,
          Paint()..color = const Color(0xFFFFF59D).withValues(alpha: 0.35));
    }
  }

  void _umbrella(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFF06292), const Color(0xFF4FC3F7), const Color(0xFFFFD54F)][prop.seed % 3];
    c.drawRect(const Rect.fromLTWH(-0.04, -2.2, 0.08, 2.2), _p(const Color(0xFF5D4037), z));
    c.drawArc(const Rect.fromLTWH(-0.9, -3.1, 1.8, 1.8), math.pi, math.pi, true, _p(color, z));
    c.drawRect(const Rect.fromLTWH(0.3, -0.1, 1.2, 0.1), _p(const Color(0xFFFFF3E0), z));
  }

  void _grandstand(Canvas c, double z) {
    for (var i = 0; i < 4; i++) {
      c.drawRect(Rect.fromLTWH(-6, -1.2 * (i + 1), 12, 1.2),
          _p(i.isEven ? const Color(0xFF8D9DAE) : const Color(0xFF6E7B8C), z));
    }
    c.drawRect(const Rect.fromLTWH(-6.5, -5.3, 13, 0.5), _p(const Color(0xFF37474F), z));
  }

  void _finishTower(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-1.5, -10, 3, 10), _p(const Color(0xFFCFD8DC), z));
    c.drawRect(const Rect.fromLTWH(-1.5, -9, 3, 1.2), _p(const Color(0xFF263238), z));
    c.drawCircle(const Offset(0, -6.5), 0.6, _p(Colors.white, z));
    c.drawLine(const Offset(0, -6.5), const Offset(0, -7.0), Paint()..color = Colors.black..strokeWidth = 0.08);
    c.drawLine(const Offset(0, -6.5), const Offset(0.35, -6.5), Paint()..color = Colors.black..strokeWidth = 0.08);
    c.drawLine(const Offset(0, -10), const Offset(0, -11.5), Paint()..color = _c(const Color(0xFF90A4AE), z)..strokeWidth = 0.1);
  }

  void _flag(Canvas c, ShoreProp prop, double z) {
    final color = [const Color(0xFFE53935), const Color(0xFFFFB300), const Color(0xFF1E88E5), const Color(0xFF43A047)][prop.seed % 4];
    final wave = math.sin(time * 4 + prop.seed) * 0.2;
    c.drawRect(const Rect.fromLTWH(-0.05, -5, 0.1, 5), _p(const Color(0xFF9E9E9E), z));
    c.drawPath(
      Path()
        ..moveTo(0, -5)
        ..lineTo(1.6, -4.6 + wave)
        ..lineTo(0, -4.0)
        ..close(),
      _p(color, z),
    );
  }

  void _marker(Canvas c, double z) {
    c.drawRect(const Rect.fromLTWH(-0.05, -1.5, 0.1, 1.5), _p(const Color(0xFF9E9E9E), z));
    c.drawRect(const Rect.fromLTWH(-0.9, -2.5, 1.8, 1.0), _p(const Color(0xFFFAFAFA), z));
  }

  /// El texto del cartel se pinta en píxeles de pantalla (TextPainter no
  /// trabaja bien con tamaños en metros).
  void _markerText(Canvas canvas, ShoreProp prop, Offset base, double s) {
    final fontSize = 0.55 * s;
    if (fontSize < 4) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '${prop.seed} m',
        style: TextStyle(color: Colors.black87, fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(base.dx - tp.width / 2, base.dy - 2.0 * s - tp.height / 2));
  }

  @override
  bool shouldRepaint(ShorePainter old) => true;
}
