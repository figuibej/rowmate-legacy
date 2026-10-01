import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/core/models/routine.dart';
import 'package:rowmate/features/workout/series_tracker.dart';

const _g = 'g1';

IntervalStep _work(int meters, {String? group = _g}) => IntervalStep(
    routineId: 1, order: 0, type: StepType.work, distanceMeters: meters,
    groupId: group, groupRepeatCount: 5);

IntervalStep _cool(int seconds, {String? group = _g}) => IntervalStep(
    routineId: 1, order: 1, type: StepType.cooldown, durationSeconds: seconds,
    groupId: group, groupRepeatCount: 5);

StepPosition _pos(int rep, {String? group = _g}) =>
    (groupId: group, rep: rep, repCount: group == null ? 1 : 5);

/// Simula lecturas de 1 s a velocidad constante, como WorkoutProvider._tick.
class _Feeder {
  _Feeder(this.tracker) {
    tracker.begin(0);
  }
  final SeriesTracker tracker;
  int t = 0;
  double d = 0;

  void run(int stepIndex, IntervalStep step, StepPosition pos,
      {required int seconds, required double speed}) {
    for (var i = 0; i < seconds; i++) {
      t++;
      d += speed;
      tracker.update(
        stepIndex: stepIndex,
        step: step,
        position: pos,
        distanceMeters: d.floor(),
        elapsedSeconds: t,
      );
    }
  }
}

void main() {
  test('interpola el tiempo de la vuelta entre lecturas', () {
    final f = _Feeder(SeriesTracker());
    // 3 m/s: 498 m en t=166 y 501 m en t=167 → cruza 500 m en 166.67 s
    f.run(0, _work(1000), _pos(1), seconds: 170, speed: 3);
    final t = f.tracker;
    expect(t.laps, hasLength(1));
    expect(t.laps.first.number, 1);
    expect(t.laps.first.seconds, closeTo(166.67, 0.01));
    expect(t.currentLapMeters, 10); // 510 - 500
    expect(t.currentLapSeconds, closeTo(3.33, 0.01));
    expect(t.isWorkStep, isTrue);
  });

  test('dos vueltas dentro del mismo paso', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(2000), _pos(1), seconds: 220, speed: 5);
    expect(f.tracker.laps.map((l) => l.seconds), [100, 100]);
  });

  test('un paso de trabajo de menos de 500 m no genera vueltas', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(400), _pos(1), seconds: 80, speed: 5);
    expect(f.tracker.laps, isEmpty);
  });

  test('el enfriamiento no genera vueltas pero suma metros a la repetición', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _cool(60), _pos(1), seconds: 60, speed: 2);
    final t = f.tracker;
    expect(t.isWorkStep, isFalse);
    expect(t.laps, isEmpty);
    expect(t.currentLapMeters, 0);
    expect(t.inSeries, isTrue);
    expect(t.rep, 1);
    expect(t.repCount, 5);
    expect(t.repMeters, 620);
  });

  test('al cambiar de repetición guarda el resumen de la anterior', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _cool(60), _pos(1), seconds: 60, speed: 2);
    f.run(2, _work(500), _pos(2), seconds: 10, speed: 5);
    final t = f.tracker;
    expect(t.rep, 2);
    expect(t.repMeters, 50);
    expect(t.previousReps, hasLength(1));
    final r = t.previousReps.first;
    expect(r.rep, 1);
    expect(r.totalMeters, 620);
    expect(r.workMeters, 500);
    expect(r.workSeconds, 100);
    expect(r.workSplitSeconds, closeTo(100, 0.001));
  });

  test('guarda solo las últimas 3 repeticiones, la más reciente primero', () {
    final f = _Feeder(SeriesTracker());
    for (var rep = 1; rep <= 5; rep++) {
      f.run((rep - 1) * 2, _work(500), _pos(rep), seconds: 100, speed: 5);
      f.run((rep - 1) * 2 + 1, _cool(10), _pos(rep), seconds: 10, speed: 2);
    }
    expect(f.tracker.rep, 5);
    expect(f.tracker.previousReps.map((r) => r.rep), [4, 3, 2]);
  });

  test('una serie nueva o un paso suelto vacían la comparación', () {
    final f = _Feeder(SeriesTracker());
    f.run(0, _work(500), _pos(1), seconds: 100, speed: 5);
    f.run(1, _work(500), _pos(2), seconds: 10, speed: 5);
    expect(f.tracker.previousReps, hasLength(1));

    f.run(2, _work(500, group: 'g2'), _pos(1, group: 'g2'), seconds: 10, speed: 5);
    expect(f.tracker.previousReps, isEmpty);

    f.run(3, _cool(60, group: null), _pos(1, group: null), seconds: 10, speed: 2);
    expect(f.tracker.inSeries, isFalse);
    expect(f.tracker.previousReps, isEmpty);
  });

  test('una repetición sin metros de trabajo no tiene split', () {
    const r = RepSummary(rep: 1, totalMeters: 100, workMeters: 0, workSeconds: 0);
    expect(r.workSplitSeconds, isNull);
  });
}
