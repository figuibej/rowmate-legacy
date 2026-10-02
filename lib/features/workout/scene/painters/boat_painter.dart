import 'dart:math' as math;
import 'package:flutter/material.dart' hide TimeOfDay;
import '../scene_camera.dart';
import '../scene_state.dart';
import '../stroke_cycle.dart';
import '../time_of_day.dart';

typedef BoatPoint3 = (double x, double y, double z);

/// Single visto desde atrás con el remero de cara a la cámara (rema mirando
/// a la popa), remos con pala que entra y sale, salpicaduras y charcos.
class BoatPainter extends CustomPainter {
  BoatPainter({
    required this.camera,
    required this.state,
    required this.palette,
    required this.light,
  });

  final SceneCamera camera;
  final SceneState state;
  final ScenePalette palette;
  final SceneLight light;

  static const double hullY = 0.08;
  static const double sternZ = SceneCamera.boatZ - 4.2;
  static const double bowZ = SceneCamera.boatZ + 4.0;
  static const double riggerX = SceneState.riggerX;
  static const double oarLength = SceneState.oarLength;
  static const double inboard = 0.9;
  static const double feetZ = SceneCamera.boatZ - 1.15;
  static const double hipY = 0.25;

  /// z del carro: en el catch (legs = 0) va hacia la popa, cerca de los pies.
  static double seatZ(double p) => SceneCamera.boatZ - 0.6 * (1 - StrokeCycle.legs(p));

  /// Mango del remo (donde van las manos).
  static BoatPoint3 handle(double side, double p) {
    final sweep = StrokeCycle.oarSweep(p);
    return (
      side * (riggerX - math.cos(sweep) * inboard),
      0.45,
      SceneCamera.boatZ + math.sin(sweep) * inboard,
    );
  }

  /// Punta de la pala.
  static BoatPoint3 bladeTip(double side, double p) {
    final sweep = StrokeCycle.oarSweep(p);
    final inWater = StrokeCycle.bladeInWater(p);
    return (
      side * (riggerX + math.cos(sweep) * oarLength),
      inWater ? -0.05 : 0.35,
      SceneCamera.boatZ - math.sin(sweep) * oarLength,
    );
  }

  Color _c(Color c) {
    final a = palette.ambient;
    return Color.from(alpha: 1, red: c.r * a, green: c.g * a, blue: c.b * math.min(1.0, a + 0.12));
  }

  Paint _paint(Color c) => Paint()..color = _c(c);

  /// Altura del casco en z, con cabeceo (+ = proa arriba).
  double _hy(double z) => hullY + (z - SceneCamera.boatZ) * math.sin(state.pitch);

  Offset? _pr(BoatPoint3 p) => camera.project(p.$1, p.$2, p.$3);

  @override
  void paint(Canvas canvas, Size size) {
    final p = state.strokePhase;
    _puddles(canvas);
    _shadow(canvas);
    _hull(canvas);
    _rower(canvas, p);
    _oars(canvas, p);
  }

  void _line(Canvas c, BoatPoint3 a, BoatPoint3 b, double widthM, Paint paint) {
    final pa = _pr(a);
    final pb = _pr(b);
    if (pa == null || pb == null) return;
    paint
      ..strokeWidth = math.max(1, widthM * camera.scaleAt((a.$3 + b.$3) / 2))
      ..strokeCap = StrokeCap.round;
    c.drawLine(pa, pb, paint);
  }

  void _fillQuad(Canvas c, List<BoatPoint3> pts, Paint paint) {
    final screen = <Offset>[];
    for (final p in pts) {
      final o = _pr(p);
      if (o == null) return;
      screen.add(o);
    }
    c.drawPath(Path()..addPolygon(screen, true), paint);
  }

  void _puddles(Canvas c) {
    for (final pd in state.puddles) {
      final relZ = pd.worldZ - state.distance;
      final o = camera.project(pd.x, 0, relZ);
      if (o == null) continue;
      final s = camera.scaleAt(relZ);
      final t = pd.age / SceneState.puddleLife;
      final r = (0.3 + 0.9 * t) * s;
      c.drawOval(
        Rect.fromCenter(center: o, width: r * 2, height: r * 0.7),
        Paint()
          ..color = Colors.white.withValues(alpha: (1 - t) * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 0.06 * s),
      );
    }
  }

  void _shadow(Canvas c) {
    final ox = light.position.dx < camera.centerX ? 0.7 : -0.7;
    final a = camera.project(ox, 0, bowZ);
    final b = camera.project(ox, 0, sternZ);
    if (a == null || b == null) return;
    final w = 0.9 * camera.scaleAt(SceneCamera.boatZ);
    c.drawOval(
      Rect.fromLTRB(math.min(a.dx, b.dx) - w / 2, a.dy, math.max(a.dx, b.dx) + w / 2, b.dy),
      Paint()..color = Colors.black.withValues(alpha: 0.22 * palette.ambient),
    );
  }

  void _hull(Canvas c) {
    const bz = SceneCamera.boatZ;
    const left = <(double, double)>[
      (-0.14, sternZ), (-0.28, bz - 1.5), (-0.26, bz + 0.5), (-0.12, bz + 2.5), (0.0, bowZ),
    ];
    final pts = <Offset>[];
    for (final (x, z) in left) {
      final o = camera.project(x, _hy(z), z);
      if (o == null) return;
      pts.add(o);
    }
    for (final (x, z) in left.reversed.skip(1)) {
      pts.add(camera.project(-x, _hy(z), z)!);
    }
    final path = Path()..addPolygon(pts, true);
    c.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_c(const Color(0xFFF5F5F5)), _c(const Color(0xFFB0BEC5))],
        ).createShader(path.getBounds()),
    );
    c.drawPath(
      path,
      Paint()
        ..color = _c(const Color(0xFF00B4D8))
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 0.03 * camera.scaleAt(bz)),
    );
    // Hueco del remero
    _fillQuad(c, [
      (-0.17, _hy(bz - 1.4) + 0.02, bz - 1.4),
      (0.17, _hy(bz - 1.4) + 0.02, bz - 1.4),
      (0.17, _hy(bz + 0.3) + 0.02, bz + 0.3),
      (-0.17, _hy(bz + 0.3) + 0.02, bz + 0.3),
    ], _paint(const Color(0xFF263238)));
  }

  void _rower(Canvas c, double p) {
    final legs = StrokeCycle.legs(p);
    final lean = StrokeCycle.torsoLean(p); // + hacia la popa (hacia la cámara)
    final sz = seatZ(p);
    final kneeZ = (sz + feetZ) / 2 - 0.1 * (1 - legs);
    final kneeY = 0.25 + 0.4 * (1 - legs);
    final shZ = sz - 0.55 * math.sin(lean);
    final shY = hipY + 0.55 * math.cos(lean);
    final headZ = shZ - 0.08 * math.sin(lean);
    final headY = shY + 0.24;
    final suit = _paint(const Color(0xFF1565C0));
    final skin = _paint(const Color(0xFFFFCC80));
    final hair = _paint(const Color(0xFF3E2723));
    final dark = _paint(const Color(0xFF0D3B6E));

    // Carro
    _fillQuad(c, [
      (-0.2, hipY - 0.03, sz - 0.2), (0.2, hipY - 0.03, sz - 0.2),
      (0.2, hipY - 0.03, sz + 0.2), (-0.2, hipY - 0.03, sz + 0.2),
    ], dark);
    // Tronco: trapecio cadera → hombros
    _fillQuad(c, [
      (-0.17, hipY, sz), (0.17, hipY, sz), (0.24, shY, shZ), (-0.24, shY, shZ),
    ], suit);
    // Cabeza con pelo
    final head = camera.project(0, headY, headZ);
    if (head != null) {
      final r = 0.12 * camera.scaleAt(headZ);
      c.drawCircle(head, r, skin);
      c.drawArc(Rect.fromCircle(center: head, radius: r * 1.02), math.pi, math.pi, true, hair);
    }
    // Brazos: hombro → mango del remo
    for (final side in [-1.0, 1.0]) {
      final h = handle(side, p);
      _line(c, (side * 0.22, shY, shZ), h, 0.09, suit);
      final hp = _pr(h);
      if (hp != null) c.drawCircle(hp, 0.05 * camera.scaleAt(h.$3), skin);
    }
    // Piernas: muslo cadera → rodilla, pantorrilla rodilla → pie (lo más cercano)
    for (final side in [-1.0, 1.0]) {
      _line(c, (side * 0.12, hipY, sz), (side * 0.14, kneeY, kneeZ), 0.16, suit);
      _line(c, (side * 0.14, kneeY, kneeZ), (side * 0.12, 0.15, feetZ), 0.12, skin);
      final f = camera.project(side * 0.12, 0.15, feetZ);
      if (f != null) c.drawCircle(f, 0.07 * camera.scaleAt(feetZ), dark);
    }
  }

  void _oars(Canvas c, double p) {
    const bz = SceneCamera.boatZ;
    final inWater = StrokeCycle.bladeInWater(p);
    final shaft = _paint(const Color(0xFFBCAAA4));
    final blade = _paint(const Color(0xFF00B4D8));
    final rigger = _paint(const Color(0xFF90A4AE));
    for (final side in [-1.0, 1.0]) {
      final pivot = (side * riggerX, 0.15, bz);
      final tip = bladeTip(side, p);
      final h = handle(side, p);
      _line(c, (side * 0.3, 0.12, bz), pivot, 0.05, rigger);
      _line(c, h, pivot, 0.06, shaft);
      _line(c, pivot, tip, 0.06, shaft);
      final tp = _pr(tip);
      if (tp == null) continue;
      final s = camera.scaleAt(tip.$3);
      if (inWater) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: tp, width: 0.25 * s, height: 0.5 * s),
            Radius.circular(0.05 * s),
          ),
          blade,
        );
        if (p < 0.08) _splash(c, tp, s, p / 0.08);
      } else {
        c.drawOval(Rect.fromCenter(center: tp, width: 0.5 * s, height: 0.12 * s), blade);
      }
    }
  }

  /// Gotas que suben y caen en el catch; t ∈ [0, 1].
  void _splash(Canvas c, Offset tp, double s, double t) {
    final paint = Paint()..color = Colors.white.withValues(alpha: (1 - t) * 0.8);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (i - 2.5) * 0.35;
      final d = (0.15 + 0.35 * t) * s;
      final rise = math.sin(t * math.pi) * 0.25 * s;
      c.drawCircle(
        Offset(tp.dx + math.cos(a) * d, tp.dy + math.sin(a) * d * 0.5 - rise),
        (0.03 + 0.02 * (1 - t)) * s,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BoatPainter old) => true;
}
