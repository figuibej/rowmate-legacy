import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/scene_camera.dart';

void main() {
  const portrait = Size(390, 844);
  const landscape = Size(844, 390);

  test('horizonte y focal según orientación', () {
    expect(SceneCamera(portrait).horizonY, closeTo(844 * 0.40, 0.001));
    expect(SceneCamera(landscape).horizonY, closeTo(390 * 0.42, 0.001));
    expect(SceneCamera(portrait).focal, 390);
    expect(SceneCamera(landscape).focal, 390);
  });

  test('lo lejano queda más cerca del horizonte, centrado y más chico', () {
    final cam = SceneCamera(portrait);
    final near = cam.project(3, 0, 10)!;
    final far = cam.project(3, 0, 200)!;
    expect(far.dy, lessThan(near.dy));
    expect(far.dy, greaterThan(cam.horizonY));
    expect((far.dx - cam.centerX).abs(), lessThan((near.dx - cam.centerX).abs()));
    expect(cam.scaleAt(200), lessThan(cam.scaleAt(10)));
    // z → ∞ converge al punto de fuga
    final vp = cam.project(3, 0, 1e9)!;
    expect(vp.dx, closeTo(cam.centerX, 0.01));
    expect(vp.dy, closeTo(cam.horizonY, 0.01));
  });

  test('detrás de la cámara no se proyecta', () {
    expect(SceneCamera(portrait).project(0, 0, 0.2), isNull);
  });

  test('unprojectWater invierte project para y = 0', () {
    final cam = SceneCamera(landscape);
    for (final (x, z) in [(-4.0, 6.0), (0.0, 30.0), (7.5, 120.0)]) {
      final s = cam.project(x, 0, z)!;
      final w = cam.unprojectWater(s);
      expect(w.dx, closeTo(x, 1e-6));
      expect(w.dy, closeTo(z, 1e-6));
    }
  });
}
