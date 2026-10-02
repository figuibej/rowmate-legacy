import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/dev/simulator_overlay.dart';
import 'package:rowmate/features/workout/scene/scene_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _shortWindowTest();

  testWidgets('el panel se abre fuera del Navigator y + sube los watts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ble = SimulatedBleService(simulator: RowingSimulator(noise: false));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BleService>.value(value: ble),
          ChangeNotifierProvider(create: (_) => SceneSettings()),
        ],
        child: MaterialApp(
          // Igual que en main.dart: por encima del Navigator.
          builder: (context, child) => SimulatorOverlay(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );

    expect(find.text('home'), findsOneWidget);
    expect(find.text('150 W'), findsNothing);

    await tester.tap(find.byIcon(Icons.build));
    await tester.pump();
    expect(find.text('150 W'), findsOneWidget);
    expect(find.text('24 spm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sim-watts-plus')));
    await tester.pump();
    expect(ble.simulator.targetWatts, 160);
    expect(find.text('160 W'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sim-spm-plus')));
    await tester.pump();
    expect(ble.simulator.targetSpm, 25);

    await tester.tap(find.byKey(const Key('sim-hour-plus')));
    await tester.pump();
    expect(find.text('Hora real'), findsOneWidget);

    await tester.tap(find.text('Simular desconexión'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Fuerte'));
    await tester.pump();
    expect(ble.simulator.targetWatts, 280);
    expect(ble.simulator.targetSpm, 30);

    await tester.tap(find.text('Remando'));
    await tester.pump();
    expect(ble.simulator.rowing, isFalse);

    await tester.tap(find.byKey(const Key('sim-close')));
    await tester.pump();
    expect(find.text('280 W'), findsNothing);

    ble.dispose();
  });
}

void _shortWindowTest() {
  testWidgets('en una ventana baja el botón de cerrar sigue accesible',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final ble = SimulatedBleService(simulator: RowingSimulator(noise: false));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BleService>.value(value: ble),
          ChangeNotifierProvider(create: (_) => SceneSettings()),
        ],
        child: MaterialApp(
          builder: (context, child) => SimulatorOverlay(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.build));
    await tester.pump();
    expect(find.text('150 W'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sim-close')));
    await tester.pump();
    expect(find.text('150 W'), findsNothing);

    ble.dispose();
  });
}
