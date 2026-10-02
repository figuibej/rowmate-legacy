import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/rowing_data.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/scene_view.dart';

void main() {
  for (final id in EnvironmentId.values) {
    for (final size in const [Size(390, 844), Size(844, 390)]) {
      for (final hour in [12.0, 23.0]) {
        testWidgets('$id ${size.width.toInt()}x${size.height.toInt()} ${hour}h anima sin excepciones',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: SceneView(
                environment: Environment.of(id),
                data: const RowingData(strokeRate: 24, pace500mSeconds: 110, distanceMeters: 300),
                isActive: true,
                hourOverride: hour,
              ),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          // Desmontar: el Ticker y la carga del shader no deben romper
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
