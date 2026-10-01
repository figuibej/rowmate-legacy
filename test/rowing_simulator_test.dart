import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/models/rowing_data.dart';

void main() {
  group('RowingSimulator', () {
    test('más watts → pace más rápido', () {
      expect(
        RowingSimulator.paceForWatts(300),
        lessThan(RowingSimulator.paceForWatts(150)),
      );
    });

    test('203 W ≈ 2:00 /500m (fórmula Concept2)', () {
      expect(RowingSimulator.paceForWatts(203), closeTo(120, 0.5));
    });

    test('acumula distancia, remadas y tiempo mientras rema', () {
      final sim = RowingSimulator(noise: false)
        ..targetWatts = 150
        ..targetSpm = 24;
      late RowingData d;
      for (var i = 0; i < 60; i++) {
        d = sim.tick();
      }
      expect(d.powerWatts, 150);
      expect(d.strokeRate, 24);
      expect(d.pace500mSeconds, 133); // 132.6 s redondeado
      expect(d.elapsedSeconds, 60);
      expect(d.strokeCount, 24);
      expect(d.distanceMeters, 226); // 60 * 500 / 132.6
      expect(d.totalCalories, 13); // 60 * (150*4*0.8604 + 300) / 3600
      expect(d.heartRate, greaterThan(70));
    });

    test('sin remar: 0 spm/watts/pace y totales congelados', () {
      final sim = RowingSimulator(noise: false);
      for (var i = 0; i < 10; i++) {
        sim.tick();
      }
      final before = sim.tick();
      sim.rowing = false;
      final after = sim.tick();
      expect(after.strokeRate, 0);
      expect(after.powerWatts, 0);
      expect(after.pace500mSeconds, 0);
      expect(after.distanceMeters, before.distanceMeters);
      expect(after.strokeCount, before.strokeCount);
      expect(after.elapsedSeconds, before.elapsedSeconds);
      expect(after.heartRate, lessThanOrEqualTo(before.heartRate));
    });

    test('los objetivos se limitan a su rango', () {
      final sim = RowingSimulator()
        ..targetWatts = 9999
        ..targetSpm = 1;
      expect(sim.targetWatts, RowingSimulator.maxWatts);
      expect(sim.targetSpm, RowingSimulator.minSpm);
    });

    test('con ruido, los watts quedan dentro de ±5 %', () {
      final sim = RowingSimulator()..targetWatts = 200;
      for (var i = 0; i < 100; i++) {
        expect(sim.tick().powerWatts, inInclusiveRange(190, 210));
      }
    });
  });
}
