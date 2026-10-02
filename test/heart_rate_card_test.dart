import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/core/bluetooth/ble_service.dart';
import 'package:rowmate/core/bluetooth/heart_rate_service.dart';
import 'package:rowmate/core/bluetooth/simulated_ble_service.dart';
import 'package:rowmate/core/bluetooth/simulated_heart_rate_service.dart';
import 'package:rowmate/core/dev/rowing_simulator.dart';
import 'package:rowmate/features/device/device_provider.dart';
import 'package:rowmate/features/device/device_screen.dart';
import 'package:rowmate/features/device/heart_rate_provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Services = ({
  RowingSimulator sim,
  SimulatedBleService ble,
  SimulatedHeartRateService hrm,
});

/// Remo falso cuyo estado controla el test: el simulador real nunca pasa por
/// `scanning` (su `startScan()` reconecta al instante). Al sustituir
/// `statusStream` tampoco se auto-conecta, así que arranca en la vista de escaneo.
class _ControllableBleService extends SimulatedBleService {
  _ControllableBleService(RowingSimulator sim) : super(simulator: sim);

  // sync: el evento llega al provider en el mismo `emit` y el siguiente
  // pump ya lo pinta (si no, llega en un microtask tras ese frame).
  final statusController = StreamController<BleStatus>.broadcast(sync: true);
  BleStatus _fakeStatus = BleStatus.disconnected;

  @override
  Stream<BleStatus> get statusStream => statusController.stream;
  @override
  BleStatus get status => _fakeStatus;

  void emit(BleStatus s) {
    _fakeStatus = s;
    statusController.add(s);
  }

  @override
  void dispose() {
    statusController.close();
    super.dispose();
  }
}

Future<_Services> _pump(WidgetTester tester,
    {SimulatedBleService Function(RowingSimulator)? bleFactory}) async {
  SharedPreferences.setMockInitialValues({});
  final sim = RowingSimulator(noise: false);
  final ble = bleFactory?.call(sim) ?? SimulatedBleService(simulator: sim);
  final hrm = SimulatedHeartRateService(sim);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<BleService>.value(value: ble),
        Provider<HeartRateService>.value(value: hrm),
        ChangeNotifierProvider(create: (_) => DeviceProvider(ble)),
        ChangeNotifierProvider(create: (_) => HeartRateProvider(hrm)),
      ],
      child: const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DeviceScreen(),
      ),
    ),
  );
  await tester.pump(); // el remo simulado se conecta en un microtask
  return (sim: sim, ble: ble, hrm: hrm);
}

Future<void> _teardown(WidgetTester tester, _Services s) async {
  await tester.pumpWidget(const SizedBox()); // dispone los providers
  s.ble.dispose();
  s.hrm.dispose();
}

void main() {
  testWidgets('sin sensor → buscar → conectar → bpm → desconectar', (tester) async {
    final s = await _pump(tester);

    // Vista conectada del remo + tarjeta en "sin sensor"
    expect(find.text('PULSÓMETRO'), findsOneWidget);
    expect(find.text('Sin sensor'), findsOneWidget);
    expect(find.textContaining('Heart for Bluetooth'), findsOneWidget);

    // La tarjeta queda bajo la rejilla de métricas: hay que desplazarse.
    await tester.ensureVisible(find.byKey(const Key('hrm-search')));
    await tester.tap(find.byKey(const Key('hrm-search')));
    await tester.pump();
    expect(find.text('Buscando sensores...'), findsOneWidget);
    expect(find.text('Pulsómetro simulado'), findsOneWidget);

    await tester.ensureVisible(find.text('Pulsómetro simulado'));
    await tester.tap(find.text('Pulsómetro simulado'));
    await tester.pump();
    expect(s.hrm.status, HrmStatus.connected);
    expect(find.text('Pulsómetro simulado'), findsOneWidget);
    expect(find.text('--'), findsOneWidget, reason: 'todavía sin lectura');

    s.sim.tick();
    await tester.pump(const Duration(seconds: 1));
    // Se compara con el bpm que emitió el servicio (el remo simulado también
    // hace tick() en ese segundo, así que sim.heartRate puede ir un paso adelante).
    expect(s.hrm.bpm, greaterThan(0));
    expect(find.text('${s.hrm.bpm}'), findsOneWidget);
    expect(find.text('--'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('hrm-disconnect')));
    await tester.tap(find.byKey(const Key('hrm-disconnect')));
    await tester.pump();
    expect(find.text('Sin sensor'), findsOneWidget);

    await _teardown(tester, s);
  });

  testWidgets('los escaneos del remo y del pulsómetro se excluyen', (tester) async {
    final s = await _pump(tester);

    await s.ble.disconnect(); // pasa a la vista de escaneo del remo
    await tester.pump();
    final rowerSearch = find.widgetWithText(FilledButton, 'Buscar dispositivos');
    expect(rowerSearch, findsOneWidget);
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('hrm-search')));
    await tester.pump();
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNull,
        reason: 'mientras el pulsómetro escanea no se puede escanear el remo');

    await s.hrm.stopScan();
    await tester.pump();
    expect(tester.widget<FilledButton>(rowerSearch).onPressed, isNotNull);

    await _teardown(tester, s);
  });

  testWidgets('en landscape la vista de escaneo no desborda', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = await _pump(tester);
    await s.ble.disconnect(); // vista de escaneo del remo + tarjeta
    await tester.pump();
    expect(tester.takeException(), isNull);
    // El botón queda bajo el borde visible del scroll de la tarjeta.
    await tester.ensureVisible(find.byKey(const Key('hrm-search')));
    await tester.tap(find.byKey(const Key('hrm-search')));
    await tester.pump();
    expect(s.hrm.status, HrmStatus.scanning);
    // La lista queda dentro del scroll propio de la tarjeta, fuera de la vista.
    expect(find.text('Pulsómetro simulado', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'la lista de sensores tampoco desborda');
    await _teardown(tester, s);
  });

  testWidgets('mientras el remo escanea no se puede buscar pulsómetro', (tester) async {
    late _ControllableBleService ble;
    final s = await _pump(tester,
        bleFactory: (sim) => ble = _ControllableBleService(sim));
    final hrmSearch = find.byKey(const Key('hrm-search'));
    expect(tester.widget<FilledButton>(hrmSearch).onPressed, isNotNull);

    ble.emit(BleStatus.scanning);
    await tester.pump();
    expect(tester.widget<FilledButton>(hrmSearch).onPressed, isNull);

    ble.emit(BleStatus.connecting);
    await tester.pump();
    expect(tester.widget<FilledButton>(hrmSearch).onPressed, isNull);

    ble.emit(BleStatus.disconnected);
    await tester.pump();
    expect(tester.widget<FilledButton>(hrmSearch).onPressed, isNotNull);

    await _teardown(tester, s);
  });
}
