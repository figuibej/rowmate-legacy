import 'interval_step.dart';

/// Posición de un paso aplanado dentro de su serie: grupo, repetición (desde 1)
/// y cantidad total de repeticiones. Un paso suelto da (null, 1, 1).
typedef StepPosition = ({String? groupId, int rep, int repCount});

/// Una rutina de entrenamiento con sus pasos (intervalos/series/descanso)
class Routine {
  final int? id;
  final String name;
  final String description;
  final DateTime createdAt;
  final List<IntervalStep> steps;

  const Routine({
    this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    this.steps = const [],
  });

  /// Duración total estimada en segundos (solo pasos con duración fija)
  int get totalDurationSeconds =>
      steps.fold(0, (sum, s) => sum + (s.durationSeconds ?? 0));

  /// Expande las series en pasos individuales secuenciales
  /// Aplica progresiones a los objetivos en cada repetición del grupo
  List<IntervalStep> get flattenedSteps {
    final result = <IntervalStep>[];
    int i = 0;
    while (i < steps.length) {
      final step = steps[i];
      if (step.groupId == null) {
        result.add(step);
        i++;
      } else {
        // Recolectar todos los pasos de este grupo
        final gid = step.groupId!;
        final repeat = step.groupRepeatCount ?? 1;
        final group = <IntervalStep>[];
        while (i < steps.length && steps[i].groupId == gid) {
          group.add(steps[i]);
          i++;
        }
        // Repetir el grupo N veces, aplicando progresiones
        for (var r = 0; r < repeat; r++) {
          for (final stepInGroup in group) {
            // Aplicar progresiones según la iteración actual (r)
            final progressed = stepInGroup.copyWith(
              targetSpm: stepInGroup.targetSpm != null && stepInGroup.progressionSpm != null
                  ? stepInGroup.targetSpm! + (stepInGroup.progressionSpm! * r)
                  : stepInGroup.targetSpm,
              targetWattsMin: stepInGroup.targetWattsMin != null && stepInGroup.progressionWatts != null
                  ? stepInGroup.targetWattsMin! + (stepInGroup.progressionWatts! * r)
                  : stepInGroup.targetWattsMin,
              targetWattsMax: stepInGroup.targetWattsMax != null && stepInGroup.progressionWatts != null
                  ? stepInGroup.targetWattsMax! + (stepInGroup.progressionWatts! * r)
                  : stepInGroup.targetWattsMax,
              targetSplitSeconds: stepInGroup.targetSplitSeconds != null && stepInGroup.progressionSplitSeconds != null
                  ? stepInGroup.targetSplitSeconds! + (stepInGroup.progressionSplitSeconds! * r)
                  : stepInGroup.targetSplitSeconds,
            );
            result.add(progressed);
          }
        }
      }
    }
    return result;
  }

  /// Posiciones alineadas índice por índice con [flattenedSteps]:
  /// indica a qué repetición de qué serie pertenece cada paso.
  List<StepPosition> get flattenedStepPositions {
    final result = <StepPosition>[];
    var i = 0;
    while (i < steps.length) {
      final gid = steps[i].groupId;
      if (gid == null) {
        result.add((groupId: null, rep: 1, repCount: 1));
        i++;
        continue;
      }
      final repeat = steps[i].groupRepeatCount ?? 1;
      var size = 0;
      while (i < steps.length && steps[i].groupId == gid) {
        size++;
        i++;
      }
      for (var r = 1; r <= repeat; r++) {
        for (var k = 0; k < size; k++) {
          result.add((groupId: gid, rep: r, repCount: repeat));
        }
      }
    }
    return result;
  }

  /// Resumen breve de la rutina
  String get summary {
    final workSteps = steps.where((s) => s.type == StepType.work).length;
    final restSteps = steps.where((s) => s.type == StepType.rest).length;
    if (workSteps == 0) return '${steps.length} pasos';
    return '$workSteps series · $restSteps descansos';
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'description': description,
    'created_at': createdAt.toIso8601String(),
  };

  factory Routine.fromMap(Map<String, dynamic> map,
      {List<IntervalStep> steps = const []}) =>
      Routine(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        steps: steps,
      );

  Routine copyWith({
    int? id,
    String? name,
    String? description,
    DateTime? createdAt,
    List<IntervalStep>? steps,
  }) =>
      Routine(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt ?? this.createdAt,
        steps: steps ?? this.steps,
      );
}
