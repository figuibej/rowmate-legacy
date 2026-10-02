import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';
import 'package:rowmate/features/workout/scene/time_of_day.dart';

void main() {
  final cam = SceneCamera(const Size(390, 844));

  test('12:00 es día con el sol arriba', () {
    expect(TimeOfDay.isNight(12), isFalse);
    final light = TimeOfDay.lightFor(12, cam);
    expect(light.isMoon, isFalse);
    expect(light.position.dy, lessThan(cam.horizonY * 0.2));
    expect(light.strength, 1.0);
  });

  test('23:00 es noche con luna', () {
    expect(TimeOfDay.isNight(23), isTrue);
    final light = TimeOfDay.lightFor(23, cam);
    expect(light.isMoon, isTrue);
    expect(light.position.dy, lessThan(cam.horizonY));
    expect(TimeOfDay.paletteFor(23).ambient, lessThan(0.5));
  });

  test('18:30 interpola entre atardecer y anochecer', () {
    final p = TimeOfDay.paletteFor(18.5);
    expect(p.ambient, closeTo(0.85 + (0.5 - 0.85) * 0.25, 1e-9));
    expect(p.skyHorizon, isNot(TimeOfDay.paletteFor(18).skyHorizon));
    expect(p.skyHorizon, isNot(TimeOfDay.paletteFor(20).skyHorizon));
  });

  test('la paleta es continua a medianoche y al amanecer', () {
    expect(TimeOfDay.paletteFor(23.99).ambient, closeTo(TimeOfDay.paletteFor(0).ambient, 0.01));
    expect(TimeOfDay.paletteFor(4.99).ambient, closeTo(TimeOfDay.paletteFor(5).ambient, 0.01));
  });
}
