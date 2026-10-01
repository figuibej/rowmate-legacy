import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/bluetooth/ble_service.dart';
import '../../core/database/database_service.dart';
import '../../core/models/rowing_data.dart';
import '../../core/models/routine.dart';
import '../../core/models/interval_step.dart';
import '../../core/models/workout_session.dart';
import 'series_tracker.dart';

enum WorkoutPhase { idle, active, paused, finished }

/// Estado del paso actual en la rutina
class StepProgress {
  final IntervalStep step;
  final int stepIndex;
  final int totalSteps;
  final int elapsedInStep;   // segundos transcurridos en este paso
  final int remainingInStep; // segundos restantes (-1 si es por distancia)

  const StepProgress({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.elapsedInStep,
    this.remainingInStep = -1,
  });

  double get progress {
    if (step.durationSeconds != null && step.durationSeconds! > 0) {
      return (elapsedInStep / step.durationSeconds!).clamp(0.0, 1.0);
    }
    return 0;
  }

  /// Verdadero si quedan 5 segundos o menos para terminar el paso
  bool get isEndingSoon {
    return remainingInStep >= 0 && remainingInStep <= 5 && remainingInStep > 0;
  }
}

class WorkoutProvider extends ChangeNotifier {
  final BleService _ble;
  final DatabaseService _db;

  WorkoutPhase _phase = WorkoutPhase.idle;
  RowingData _data = const RowingData();
  Routine? _routine;
  int _currentStepIndex = 0;
  int _stepElapsedSeconds = 0;
  int _totalElapsedSeconds = 0;
  int _distanceAtStepStart = 0;

  // Parciales de 500 m y repeticiones de la serie (solo en memoria)
  final SeriesTracker _series = SeriesTracker();
  List<StepPosition> _stepPositions = const [];

  Timer? _timer;
  StreamSubscription<RowingData>? _dataSub;

  // Datos acumulados para guardar la sesión
  int? _sessionId;
  DateTime? _startedAt;
  final List<DataPoint> _dataBuffer = [];
  int _sampleTick = 0;

  // Strava auto-upload: ID de la última sesión terminada
  int? _lastFinishedSessionId;
  int? get lastFinishedSessionId => _lastFinishedSessionId;

  WorkoutProvider(this._ble, this._db) {
    _dataSub = _ble.dataStream.listen(_onData);
  }

  WorkoutPhase get phase => _phase;
  RowingData get data => _data;
  int get totalElapsedSeconds => _totalElapsedSeconds;
  SeriesTracker get series => _series;
  Routine? get routine => _routine;
  bool get isActive => _phase == WorkoutPhase.active;
  bool get isPaused => _phase == WorkoutPhase.paused;
  bool get isIdle => _phase == WorkoutPhase.idle;

  StepProgress? get stepProgress {
    if (_routine == null || _phase == WorkoutPhase.idle) return null;
    final step = _routine!.steps[_currentStepIndex];
    int remaining = -1;
    if (step.durationSeconds != null) {
      remaining = (step.durationSeconds! - _stepElapsedSeconds).clamp(0, step.durationSeconds!);
    }
    return StepProgress(
      step: step,
      stepIndex: _currentStepIndex,
      totalSteps: _routine!.steps.length,
      elapsedInStep: _stepElapsedSeconds,
      remainingInStep: remaining,
    );
  }

  /// Inicia un entrenamiento libre (sin rutina)
  Future<void> startFree() async {
    await _begin(null);
  }

  /// Inicia un entrenamiento con rutina
  Future<void> startWithRoutine(Routine routine) async {
    // Expandir series en pasos individuales
    final expanded = routine.copyWith(steps: routine.flattenedSteps);
    _routine = expanded;
    _currentStepIndex = 0;
    _stepElapsedSeconds = 0;
    _distanceAtStepStart = _data.distanceMeters;
    _stepPositions = routine.flattenedStepPositions;
    _series.begin(_data.distanceMeters, elapsedSeconds: _totalElapsedSeconds);
    await _begin(routine);  // usa routine original para el nombre/id
  }

  Future<void> _begin(Routine? routine) async {
    _phase = WorkoutPhase.active;
    _startedAt = DateTime.now();
    _dataBuffer.clear();
    _sampleTick = 0;

    // Crea sesión en la base de datos
    final session = WorkoutSession(
      routineId: routine?.id,
      routineName: routine?.name,
      startedAt: _startedAt!,
    );
    _sessionId = await _db.insertSession(session);

    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    notifyListeners();
  }

  void _tick(Timer _) {
    if (_phase != WorkoutPhase.active) return;

    _stepElapsedSeconds++;
    _totalElapsedSeconds++;
    _sampleTick++;

    // Guarda punto de telemetría cada 5 segundos
    if (_sampleTick % 5 == 0 && _sessionId != null) {
      _dataBuffer.add(DataPoint(
        sessionId: _sessionId!,
        elapsedSeconds: _data.elapsedSeconds,
        strokeRate: _data.strokeRate,
        strokeCount: _data.strokeCount,
        distanceMeters: _data.distanceMeters,
        pace500mSeconds: _data.pace500mSeconds,
        powerWatts: _data.powerWatts,
        calories: _data.totalCalories,
        heartRate: _data.heartRate,
        stepIndex: _routine != null ? _currentStepIndex : null,
        stepType: _routine != null ? _routine!.steps[_currentStepIndex].type.name : null,
      ));
    }

    // Avanza al siguiente paso si se cumplió el objetivo
    if (_routine != null) {
      // Antes de avanzar: esta lectura pertenece al paso actual
      _series.update(
        stepIndex: _currentStepIndex,
        step: _routine!.steps[_currentStepIndex],
        position: _stepPositions[_currentStepIndex],
        distanceMeters: _data.distanceMeters,
        elapsedSeconds: _totalElapsedSeconds,
      );
      _checkStepCompletion();
    }

    notifyListeners();
  }

  void _checkStepCompletion() {
    final step = _routine!.steps[_currentStepIndex];
    bool completed = false;

    if (step.durationSeconds != null) {
      completed = _stepElapsedSeconds >= step.durationSeconds!;
    } else if (step.distanceMeters != null) {
      final traveledInStep = _data.distanceMeters - _distanceAtStepStart;
      completed = traveledInStep >= step.distanceMeters!;
    }

    if (completed) {
      final nextIndex = _currentStepIndex + 1;
      if (nextIndex < _routine!.steps.length) {
        _currentStepIndex = nextIndex;
        _stepElapsedSeconds = 0;
        _distanceAtStepStart = _data.distanceMeters;
      } else {
        // Última etapa completada → fin de la rutina
        // Set phase immediately to prevent re-entrant calls from timer
        _phase = WorkoutPhase.finished;
        _timer?.cancel();
        finish();
      }
    }
  }

  void _onData(RowingData d) {
    _data = d;
    notifyListeners();
  }

  void pause() {
    _phase = WorkoutPhase.paused;
    _timer?.cancel();
    notifyListeners();
  }

  void resume() {
    _phase = WorkoutPhase.active;
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    _series.rebase(_data.distanceMeters); // lo remado en pausa no cuenta para parciales
    notifyListeners();
  }

  Future<void> finish() async {
    _phase = WorkoutPhase.finished;
    _timer?.cancel();

    if (_sessionId != null && _startedAt != null) {
      try {
        // Captura último data point antes de guardar
        _dataBuffer.add(DataPoint(
          sessionId: _sessionId!,
          elapsedSeconds: _data.elapsedSeconds,
          strokeRate: _data.strokeRate,
          strokeCount: _data.strokeCount,
          distanceMeters: _data.distanceMeters,
          pace500mSeconds: _data.pace500mSeconds,
          powerWatts: _data.powerWatts,
          calories: _data.totalCalories,
          heartRate: _data.heartRate,
          stepIndex: _routine != null ? _currentStepIndex : null,
          stepType: _routine != null && _currentStepIndex < _routine!.steps.length
              ? _routine!.steps[_currentStepIndex].type.name
              : null,
        ));

        // Computa stats desde el buffer completo
        final stats = SessionStats.compute(_dataBuffer);

        // Guarda los data points
        await _db.insertDataPoints(_dataBuffer);
        _dataBuffer.clear();

        // Actualiza la sesión con stats computadas
        final session = WorkoutSession(
          id: _sessionId,
          routineId: _routine?.id,
          routineName: _routine?.name,
          startedAt: _startedAt!,
          finishedAt: DateTime.now(),
          totalDistanceMeters: stats.totalDistance,
          totalTimeSeconds: stats.totalTimeSeconds,
          avgPowerWatts: stats.p99Watts,
          avgStrokeRate: stats.p99Spm,
          totalCalories: stats.totalCalories,
        );
        await _db.updateSession(session);
        _lastFinishedSessionId = _sessionId;
      } catch (e) {
        debugPrint('[Workout] Error saving session: $e');
      }
    }

    notifyListeners();
  }

  void reset() {
    _phase = WorkoutPhase.idle;
    _routine = null;
    _currentStepIndex = 0;
    _stepElapsedSeconds = 0;
    _totalElapsedSeconds = 0;
    _sessionId = null;
    _startedAt = null;
    _dataBuffer.clear();
    _stepPositions = const [];
    _series.begin(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }
}
