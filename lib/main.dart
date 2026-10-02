import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/bluetooth/ble_service.dart';
import 'core/bluetooth/simulated_ble_service.dart';
import 'core/bluetooth/heart_rate_service.dart';
import 'core/bluetooth/simulated_heart_rate_service.dart';
import 'core/database/database_service.dart';
import 'core/dev/dev_config.dart';
import 'core/dev/simulator_overlay.dart';
import 'core/strava/strava_config.dart';
import 'core/strava/strava_auth_service.dart';
import 'core/strava/strava_api_service.dart';
import 'features/device/device_provider.dart';
import 'features/device/device_screen.dart';
import 'features/device/heart_rate_provider.dart';
import 'features/history/history_provider.dart';
import 'features/history/history_screen.dart';
import 'features/profile/profile_provider.dart';
import 'features/profile/profile_screen.dart';
import 'features/routines/routines_provider.dart';
import 'features/routines/routines_screen.dart';
import 'features/workout/scene/scene_settings.dart';
import 'features/workout/workout_provider.dart';
import 'features/workout/workout_screen.dart';
import 'shared/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite no tiene implementación nativa en desktop (salvo macOS): usar FFI
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  WakelockPlus.enable();
  runApp(const RowerApp());
}

class RowerApp extends StatelessWidget {
  const RowerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final BleService ble = kSimulator ? SimulatedBleService() : BleService();
    final HeartRateService hrm = kSimulator
        ? SimulatedHeartRateService((ble as SimulatedBleService).simulator)
        : HeartRateService();
    final db = DatabaseService();
    final stravaConfigured = StravaConfig.isConfigured;

    return MultiProvider(
      providers: [
        Provider<BleService>(
          create: (_) => ble,
          dispose: (_, s) => s.dispose(),
        ),
        Provider<DatabaseService>(
          create: (_) => db,
          dispose: (_, s) => s.close(),
        ),
        Provider<HeartRateService>(
          // lazy: false → create corre al arrancar aunque nadie lea el servicio
          // del árbol (los providers lo reciben por closure).
          lazy: false,
          create: (_) {
            // Reconecta al sensor recordado, si lo hay.
            unawaited(hrm.autoConnect().catchError(
                (Object e) => debugPrint('[HRM] autoConnect: $e')));
            return hrm;
          },
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => DeviceProvider(ble)),
        ChangeNotifierProvider(create: (_) => HeartRateProvider(hrm)),
        ChangeNotifierProvider(create: (_) => WorkoutProvider(ble, hrm, db)),
        ChangeNotifierProvider(create: (_) => RoutinesProvider(db)),
        ChangeNotifierProvider(create: (_) => HistoryProvider(db)),
        ChangeNotifierProvider(create: (_) => SceneSettings()),
        if (stravaConfigured)
          ChangeNotifierProvider(create: (_) {
            final stravaAuth = StravaAuthService();
            final stravaApi = StravaApiService(stravaAuth);
            return ProfileProvider(stravaAuth, stravaApi, db);
          }),
      ],
      child: MaterialApp(
        title: 'RowMate',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('es'),
        ],
        home: const MainShell(),
        builder: kSimulator
            ? (context, child) => SimulatorOverlay(child: child!)
            : null,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  List<Widget> _buildScreens() {
    final stravaConfigured = StravaConfig.isConfigured;
    return [
      const DeviceScreen(),
      const WorkoutScreen(),
      const RoutinesScreen(),
      const HistoryScreen(),
      if (stravaConfigured) const ProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screens = _buildScreens();
    const historyIndex = 3;
    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (i == historyIndex) context.read<HistoryProvider>().load();
          setState(() => _tab = i);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bluetooth),
            selectedIcon: const Icon(Icons.bluetooth_connected),
            label: l10n.navDevice,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timer_outlined),
            selectedIcon: const Icon(Icons.timer),
            label: l10n.navWorkout,
          ),
          NavigationDestination(
            icon: const Icon(Icons.fitness_center),
            selectedIcon: const Icon(Icons.fitness_center),
            label: l10n.navRoutines,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history),
            label: l10n.navHistory,
          ),
          if (StravaConfig.isConfigured)
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: l10n.navProfile,
            ),
        ],
      ),
    );
  }
}
