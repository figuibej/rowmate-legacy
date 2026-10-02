import 'dart:math' as math;

/// Secuencia de la palada en función de la fase p ∈ [0, 1).
/// Drive 0.00–0.40 (rápido), recuperación 0.40–1.00 (lenta): ratio 1:2.
class StrokeCycle {
  StrokeCycle._();

  /// Ángulo del remo en el catch: pala hacia la proa.
  static const double catchSweep = -55 * math.pi / 180;

  /// Ángulo del remo en el finish: pala hacia la popa.
  static const double finishSweep = 35 * math.pi / 180;

  /// 0 = piernas plegadas (catch), 1 = extendidas (finish).
  static double legs(double p) {
    if (p < 0.60) return _ramp(p, 0.00, 0.18);
    return 1 - _ramp(p, 0.60, 1.00);
  }

  /// 0 = tronco adelante (+25°), 1 = tronco atrás (−20°).
  static double back(double p) {
    if (p < 0.50) return _ramp(p, 0.10, 0.30);
    return 1 - _ramp(p, 0.50, 0.75);
  }

  /// 0 = brazos estirados, 1 = flexionados al pecho.
  static double arms(double p) {
    if (p < 0.40) return _ramp(p, 0.22, 0.36);
    return 1 - _ramp(p, 0.40, 0.60);
  }

  /// Inclinación del tronco en radianes (+ hacia la proa).
  static double torsoLean(double p) =>
      _lerp(25 * math.pi / 180, -20 * math.pi / 180, back(p));

  static bool bladeInWater(double p) => p < 0.38;
  static bool bladeFeathered(double p) => !bladeInWater(p);

  /// Ángulo del remo respecto de la perpendicular al bote (rad).
  /// Negativo = pala hacia la proa.
  static double oarSweep(double p) {
    if (p < 0.36) return _lerp(catchSweep, finishSweep, _smooth(p / 0.36));
    if (p < 0.40) return finishSweep;
    return _lerp(finishSweep, catchSweep, _smooth((p - 0.40) / 0.60));
  }

  static double _ramp(double p, double a, double b) =>
      _smooth(((p - a) / (b - a)).clamp(0.0, 1.0));
  static double _smooth(double t) => t * t * (3 - 2 * t);
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
