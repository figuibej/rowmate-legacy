import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/stroke_cycle.dart';

void main() {
  test('catch: piernas plegadas, brazos estirados, pala en el agua', () {
    expect(StrokeCycle.legs(0), 0);
    expect(StrokeCycle.arms(0), 0);
    expect(StrokeCycle.back(0), 0);
    expect(StrokeCycle.bladeInWater(0), isTrue);
    expect(StrokeCycle.oarSweep(0), lessThan(0));
    expect(StrokeCycle.torsoLean(0), greaterThan(0)); // inclinado hacia la cámara (popa)
  });

  test('finish: piernas extendidas, brazos flexionados, pala sale', () {
    expect(StrokeCycle.legs(0.36), 1);
    expect(StrokeCycle.arms(0.36), 1);
    expect(StrokeCycle.back(0.36), 1);
    expect(StrokeCycle.oarSweep(0.36), greaterThan(0));
    expect(StrokeCycle.bladeInWater(0.39), isFalse);
    expect(StrokeCycle.torsoLean(0.36), lessThan(0));
  });

  test('en el drive: piernas antes que espalda, espalda antes que brazos', () {
    expect(StrokeCycle.legs(0.12), greaterThan(StrokeCycle.back(0.12)));
    expect(StrokeCycle.back(0.12), greaterThan(StrokeCycle.arms(0.12)));
    expect(StrokeCycle.arms(0.12), 0);
  });

  test('la recuperación vuelve todo al catch', () {
    expect(StrokeCycle.legs(0.999), closeTo(0, 1e-3));
    expect(StrokeCycle.arms(0.999), 0);
    expect(StrokeCycle.back(0.999), 0);
    expect(StrokeCycle.oarSweep(0.999), closeTo(StrokeCycle.catchSweep, 1e-3));
    expect(StrokeCycle.bladeFeathered(0.7), isTrue);
  });
}
