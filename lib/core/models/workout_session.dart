/// Sesión de entrenamiento completada
class WorkoutSession {
  final int? id;
  final int? routineId;
  final String? routineName;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int totalDistanceMeters;
  final int totalTimeSeconds;
  final int avgPowerWatts;
  final double avgStrokeRate;
  final int totalCalories;
  final String? stravaActivityId;

  const WorkoutSession({
    this.id,
    this.routineId,
    this.routineName,
    required this.startedAt,
    this.finishedAt,
    this.totalDistanceMeters = 0,
    this.totalTimeSeconds = 0,
    this.avgPowerWatts = 0,
    this.avgStrokeRate = 0,
    this.totalCalories = 0,
    this.stravaActivityId,
  });

  String get durationFormatted {
    final h = totalTimeSeconds ~/ 3600;
    final m = (totalTimeSeconds % 3600) ~/ 60;
    final s = totalTimeSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'routine_id': routineId,
    'routine_name': routineName,
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt?.toUtc().toIso8601String(),
    'total_distance_meters': totalDistanceMeters,
    'total_time_seconds': totalTimeSeconds,
    'avg_power_watts': avgPowerWatts,
    'avg_stroke_rate': avgStrokeRate,
    'total_calories': totalCalories,
    'strava_activity_id': stravaActivityId,
  };

  factory WorkoutSession.fromMap(Map<String, dynamic> map) => WorkoutSession(
    id: map['id'] as int?,
    routineId: map['routine_id'] as int?,
    routineName: map['routine_name'] as String?,
    startedAt: DateTime.parse(map['started_at'] as String).toLocal(),
    finishedAt: map['finished_at'] != null
        ? DateTime.parse(map['finished_at'] as String).toLocal()
        : null,
    totalDistanceMeters: map['total_distance_meters'] as int? ?? 0,
    totalTimeSeconds: map['total_time_seconds'] as int? ?? 0,
    avgPowerWatts: map['avg_power_watts'] as int? ?? 0,
    avgStrokeRate: (map['avg_stroke_rate'] as num?)?.toDouble() ?? 0,
    totalCalories: map['total_calories'] as int? ?? 0,
    stravaActivityId: map['strava_activity_id'] as String?,
  );
}

/// Estadísticas computadas desde data_points (percentil 99)
class SessionStats {
  final int p99Watts;
  final double p99Spm;
  final int p99SplitSeconds;
  final int totalDistance;
  final int totalTimeSeconds;
  final int totalCalories;
  final int avgHeartRate; // bpm, media de los puntos con pulso > 0 (0 si no hubo)
  final int maxHeartRate; // bpm (0 si no hubo)

  const SessionStats({
    this.p99Watts = 0,
    this.p99Spm = 0,
    this.p99SplitSeconds = 0,
    this.totalDistance = 0,
    this.totalTimeSeconds = 0,
    this.totalCalories = 0,
    this.avgHeartRate = 0,
    this.maxHeartRate = 0,
  });

  bool get hasHeartRate => maxHeartRate > 0;

  String get splitFormatted {
    if (p99SplitSeconds <= 0) return '--:--';
    final m = p99SplitSeconds ~/ 60;
    final s = p99SplitSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get durationFormatted {
    final h = totalTimeSeconds ~/ 3600;
    final m = (totalTimeSeconds % 3600) ~/ 60;
    final s = totalTimeSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double _percentile99(List<num> values) {
    if (values.isEmpty) return 0;
    final sorted = List<num>.from(values)..sort();
    final index = ((sorted.length - 1) * 0.99).floor();
    return sorted[index].toDouble();
  }

  static SessionStats compute(List<DataPoint> points) {
    if (points.isEmpty) return const SessionStats();

    final watts = points.map((p) => p.powerWatts).where((v) => v > 0).toList();
    final spms = points.map((p) => p.strokeRate).where((v) => v > 0).toList();
    final splits = points.map((p) => p.pace500mSeconds).where((v) => v > 0).toList();
    final hrs = points.map((p) => p.heartRate).where((v) => v > 0).toList();

    return SessionStats(
      p99Watts: _percentile99(watts).round(),
      p99Spm: _percentile99(spms),
      p99SplitSeconds: _percentile99(splits).round(),
      totalDistance: points.map((p) => p.distanceMeters).reduce((a, b) => a > b ? a : b),
      totalTimeSeconds: points.map((p) => p.elapsedSeconds).reduce((a, b) => a > b ? a : b),
      totalCalories: points.map((p) => p.calories).reduce((a, b) => a > b ? a : b),
      avgHeartRate: hrs.isEmpty ? 0 : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
      maxHeartRate: hrs.isEmpty ? 0 : hrs.reduce((a, b) => a > b ? a : b),
    );
  }
}

/// Punto de telemetría individual dentro de una sesión
class DataPoint {
  final int? id;
  final int sessionId;
  final int elapsedSeconds;
  final double strokeRate;
  final int strokeCount;
  final int distanceMeters;
  final int pace500mSeconds;
  final int powerWatts;
  final int calories;
  final int heartRate;
  final int? stepIndex;
  final String? stepType;    // warmup, work, rest, cooldown

  const DataPoint({
    this.id,
    required this.sessionId,
    required this.elapsedSeconds,
    this.strokeRate = 0,
    this.strokeCount = 0,
    this.distanceMeters = 0,
    this.pace500mSeconds = 0,
    this.powerWatts = 0,
    this.calories = 0,
    this.heartRate = 0,
    this.stepIndex,
    this.stepType,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'session_id': sessionId,
    'elapsed_seconds': elapsedSeconds,
    'stroke_rate': strokeRate,
    'stroke_count': strokeCount,
    'distance_meters': distanceMeters,
    'pace_500m_seconds': pace500mSeconds,
    'power_watts': powerWatts,
    'calories': calories,
    'heart_rate': heartRate,
    'step_index': stepIndex,
    'step_type': stepType,
  };
}
