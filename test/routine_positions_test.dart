import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/core/models/routine.dart';

void main() {
  test('las posiciones quedan alineadas con flattenedSteps', () {
    final routine = Routine(
      name: 't',
      createdAt: DateTime(2026),
      steps: const [
        IntervalStep(routineId: 1, order: 0, type: StepType.warmup, durationSeconds: 300),
        IntervalStep(routineId: 1, order: 1, type: StepType.work, distanceMeters: 500, groupId: 'a', groupRepeatCount: 3),
        IntervalStep(routineId: 1, order: 2, type: StepType.cooldown, durationSeconds: 60, groupId: 'a', groupRepeatCount: 3),
        IntervalStep(routineId: 1, order: 3, type: StepType.cooldown, durationSeconds: 300),
      ],
    );

    final positions = routine.flattenedStepPositions;
    expect(positions, hasLength(routine.flattenedSteps.length));
    expect(positions, hasLength(8));
    expect(positions[0], (groupId: null, rep: 1, repCount: 1));
    expect(positions[1], (groupId: 'a', rep: 1, repCount: 3));
    expect(positions[2], (groupId: 'a', rep: 1, repCount: 3));
    expect(positions[3], (groupId: 'a', rep: 2, repCount: 3));
    expect(positions[6], (groupId: 'a', rep: 3, repCount: 3));
    expect(positions[7], (groupId: null, rep: 1, repCount: 1));
  });
}
