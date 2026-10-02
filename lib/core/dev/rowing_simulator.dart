import 'dart:math';
import '../models/rowing_data.dart';

/// Física simplificada de un remo para el modo simulador.
/// Cada [tick] avanza 1 segundo y devuelve la lectura que emitiría el monitor.
class RowingSimulator {
  static const minWatts = 30;
  static const maxWatts = 500;
  static const minSpm = 14;
  static const maxSpm = 40;

  RowingSimulator({Random? random, this.noise = true})
      : _random = random ?? Random();

  final Random _random;

  /// Si es false, los valores emitidos son exactamente los objetivos (para tests).
  final bool noise;

  int _targetWatts = 150;
  int get targetWatts => _targetWatts;
  set targetWatts(int v) => _targetWatts = v.clamp(minWatts, maxWatts);

  int _targetSpm = 24;
  int get targetSpm => _targetSpm;
  set targetSpm(int v) => _targetSpm = v.clamp(minSpm, maxSpm);

  /// false = el remero dejó de remar (spm/watts en 0, totales congelados)
  bool rowing = true;

  /// Último pulso calculado por [tick] (bpm). Lo emite el pulsómetro simulado.
  int get heartRate => _heartRate.round();

  double _distance = 0;
  double _strokes = 0;
  double _calories = 0;
  double _heartRate = 70;
  int _elapsed = 0;

  RowingData tick() {
    var watts = 0;
    var spm = 0.0;
    var pace = 0;

    if (rowing) {
      watts = max(1, (targetWatts * (1 + _jitter(0.05))).round());
      spm = max(1.0, targetSpm + _jitter(1.0));
      final paceExact = paceForWatts(watts);
      pace = paceExact.round();
      _distance += 500 / paceExact;
      _strokes += spm / 60;
      _calories += caloriesPerSecond(watts);
      _elapsed++;
    }

    final targetHr = rowing ? min(190.0, 90 + watts * 0.35) : 70.0;
    _heartRate += (targetHr - _heartRate) * 0.1;

    return RowingData(
      strokeRate: double.parse(spm.toStringAsFixed(1)),
      // + 1e-6 evita que errores de punto flotante (23.9999…) resten una unidad
      strokeCount: (_strokes + 1e-6).floor(),
      distanceMeters: (_distance + 1e-6).floor(),
      pace500mSeconds: pace,
      powerWatts: watts,
      totalCalories: (_calories + 1e-6).floor(),
      heartRate: _heartRate.round(),
      elapsedSeconds: _elapsed,
    );
  }

  /// Valor aleatorio uniforme en [-amplitude, amplitude], o 0 sin ruido.
  double _jitter(double amplitude) =>
      noise ? (_random.nextDouble() * 2 - 1) * amplitude : 0;

  /// Segundos por 500 m para una potencia dada (fórmula de Concept2).
  static double paceForWatts(int watts) =>
      500 * pow(2.80 / watts, 1 / 3).toDouble();

  /// kcal por segundo para una potencia dada (fórmula de Concept2).
  static double caloriesPerSecond(int watts) =>
      (watts * 4 * 0.8604 + 300) / 3600;
}
