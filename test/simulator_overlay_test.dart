import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/core/dev/simulator_overlay.dart';

void main() {
  testWidgets('el panel se abre fuera del Navigator y + sube los watts',
      (tester) async {
    final ble = SimulatedBleService(simulator: RowingSimulator(noise: false));
    await tester.pumpWidget(
      Provider<BleService>.value(
        value: ble,
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
