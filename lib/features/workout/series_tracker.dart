import '../../core/models/interval_step.dart';
import '../../core/models/routine.dart';

/// Vuelta de 500 m completada dentro de un paso de trabajo.
class Lap {
  const Lap(this.number, this.seconds);

  /// 1, 2, 3… dentro del paso.
  final int number;

  /// Tiempo en remar esos 500 m.
  final double seconds;
}

/// Resumen de una repetición completa de la serie.
class RepSummary {
  const RepSummary({
    required this.rep,
    required this.totalMeters,
    required this.workMeters,
    required this.workSeconds,
  });

  final int rep;

  /// Metros de todos los pasos de la repetición (trabajo + enfriamiento…).
  final int totalMeters;
  final int workMeters;
  final double workSeconds;

  /// Split promedio de trabajo en s/500m, o null si no hubo metros de trabajo.
  double? get workSplitSeconds =>
      workMeters > 0 ? workSeconds / workMeters * 500 : null;
}

/// Lleva las vueltas de 500 m de los pasos de trabajo y los totales de cada
/// repetición de la serie en curso. WorkoutProvider lo alimenta una vez por
/// segundo con la distancia del monitor y los segundos activos (sin pausas).
class SeriesTracker {
  static const lapMeters = 500;
  static const maxPreviousReps = 3;

  // Última lectura
  double _lastDistance = 0;
  double _lastTime = 0;

  int? _stepIndex;
  StepPosition? _position;
  bool _isWork = false;

  // Paso actual
  double _stepStartDistance = 0;
  double _lastLapEndTime = 0;
  final List<Lap> _laps = [];

  // Repetición actual
  double _repStartDistance = 0;
  double _repWorkMeters = 0;
  double _repWorkSeconds = 0;
  final List<RepSummary> _previousReps = []; // la más reciente primero

  List<Lap> get laps => List.unmodifiable(_laps);
  bool get isWorkStep => _isWork;

  /// Metros recorridos en la vuelta en curso (0 fuera de pasos de trabajo).
  int get currentLapMeters => _isWork
      ? ((_lastDistance - _stepStartDistance) - _laps.length * lapMeters).floor()
      : 0;

  /// Segundos de la vuelta en curso (0 fuera de pasos de trabajo).
  double get currentLapSeconds => _isWork ? _lastTime - _lastLapEndTime : 0;

  bool get inSeries => _position?.groupId != null;
  int get rep => _position?.rep ?? 0;
  int get repCount => _position?.repCount ?? 0;
  int get repMeters => (_lastDistance - _repStartDistance).floor();
  List<RepSummary> get previousReps => List.unmodifiable(_previousReps);

  /// Reinicia todo. [distanceMeters] es la distancia del monitor al iniciar.
  void begin(int distanceMeters) {
    _lastDistance = distanceMeters.toDouble();
    _lastTime = 0;
    _stepIndex = null;
    _position = null;
    _isWork = false;
    _stepStartDistance = _lastDistance;
    _lastLapEndTime = 0;
    _laps.clear();
    _repStartDistance = _lastDistance;
    _repWorkMeters = 0;
    _repWorkSeconds = 0;
    _previousReps.clear();
  }

  /// Registra una lectura del paso [stepIndex].
  void update({
    required int stepIndex,
    required IntervalStep step,
    required StepPosition position,
    required int distanceMeters,
    required int elapsedSeconds,
  }) {
    if (stepIndex != _stepIndex) _enterStep(stepIndex, step, position);

    final d = distanceMeters.toDouble();
    final t = elapsedSeconds.toDouble();
    final dd = d - _lastDistance;
    final dt = t - _lastTime;

    if (_isWork) {
      if (dd > 0) _repWorkMeters += dd;
      _repWorkSeconds += dt;
      // Puede completarse más de una vuelta en una lectura
      while (d - _stepStartDistance >= (_laps.length + 1) * lapMeters) {
        final target = _stepStartDistance + (_laps.length + 1) * lapMeters;
        // Interpolación lineal del instante en que se cruzó la marca
        final crossTime =
            dd > 0 ? _lastTime + (target - _lastDistance) / dd * dt : t;
        _laps.add(Lap(_laps.length + 1, crossTime - _lastLapEndTime));
        _lastLapEndTime = crossTime;
      }
    }

    _lastDistance = d;
    _lastTime = t;
  }

  void _enterStep(int stepIndex, IntervalStep step, StepPosition position) {
    final prev = _position;
    final isNewRep = prev == null ||
        position.groupId != prev.groupId ||
        position.rep != prev.rep;

    if (isNewRep) {
      final sameSeries =
          prev != null && prev.groupId != null && position.groupId == prev.groupId;
      if (sameSeries) {
        _previousReps.insert(
          0,
          RepSummary(
            rep: prev.rep,
            totalMeters: (_lastDistance - _repStartDistance).floor(),
            workMeters: _repWorkMeters.floor(),
            workSeconds: _repWorkSeconds,
          ),
        );
        if (_previousReps.length > maxPreviousReps) _previousReps.removeLast();
      } else {
        // La comparación es dentro de la serie en curso
        _previousReps.clear();
      }
      _repStartDistance = _lastDistance;
      _repWorkMeters = 0;
      _repWorkSeconds = 0;
    }

    _stepIndex = stepIndex;
    _position = position;
    _isWork = step.type == StepType.work;
    _stepStartDistance = _lastDistance;
    _lastLapEndTime = _lastTime;
    _laps.clear();
  }
}
