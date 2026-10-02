import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/interval_step.dart';
import 'package:rowmate/features/workout/series_panels.dart';
import 'package:rowmate/features/workout/series_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _work = IntervalStep(
    routineId: 1, order: 0, type: StepType.work, distanceMeters: 1000,
    groupId: 'g', groupRepeatCount: 3);

SeriesTracker _trackerAt300m({String? group = 'g'}) {
  final t = SeriesTracker()..begin(0);
  t.update(
    stepIndex: 0,
    step: _work,
    position: (groupId: group, rep: 1, repCount: group == null ? 1 : 3),
    distanceMeters: 300,
    elapsedSeconds: 60,
  );
  return t;
}

Future<void> _pump(WidgetTester tester, SeriesTracker t) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SeriesPanels(tracker: t)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('formatos', () {
    expect(formatLapTime(166.667), '2:46.7');
    expect(formatLapTime(65), '1:05.0');
    expect(formatSplit(114.4), '1:54');
    expect(formatMeters(1245), '1.245 m');
  });

  testWidgets('arrancan colapsados y al tocar se expanden y se recuerda',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, _trackerAt300m());

    expect(find.text('Parciales 500 m'), findsNothing);
    expect(find.text('Series anteriores'), findsNothing);
    expect(find.text('500 m'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);

    await tester.tap(find.text('500 m'));
    await tester.pumpAndSettle();
    expect(find.text('Parciales 500 m'), findsOneWidget);
    expect(find.text('Rep 1/3 · 300 m'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SeriesPanels.lapsKey), isTrue);

    await tester.tap(find.text('Reps'));
    await tester.pumpAndSettle();
    expect(find.text('Sin repeticiones completas'), findsOneWidget);
  });

  testWidgets('respeta la preferencia guardada', (tester) async {
    SharedPreferences.setMockInitialValues({SeriesPanels.lapsKey: true});
    await _pump(tester, _trackerAt300m());
    expect(find.text('Parciales 500 m'), findsOneWidget);
  });

  testWidgets('sin serie no aparece el panel de repeticiones', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, _trackerAt300m(group: null));
    expect(find.text('500 m'), findsOneWidget);
    expect(find.text('Reps'), findsNothing);
  });
}
