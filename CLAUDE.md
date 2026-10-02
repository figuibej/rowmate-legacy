# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run on connected Android/iOS device
flutter run

# Run on Windows desktop
flutter run -d windows

# Run with simulated rower (dev mode: separate DB, Strava uploads blocked)
# Works on any platform; in VS Code use the "RowMate (simulador)" launch config.
flutter run -d windows --dart-define=SIMULATOR=true

# List available devices
flutter devices

# Run tests
flutter test

# Analyze code (lint)
flutter analyze

# Build release APK
flutter build apk
```

## Architecture Overview

Flutter app for monitoring a rowing machine (AMS-670B) via Bluetooth Low Energy. State managed with `provider`, navigation via `go_router`, persistence via `sqflite`.

### Layer Structure

```
lib/
├── core/           # Platform services: BLE, database, domain models, Strava
│   └── dev/        # Dev-mode simulator (only compiled in with SIMULATOR=true)
├── features/       # One folder per screen (device, workout, routines, history)
├── shared/         # Theme and reusable widgets
└── main.dart       # App entry point, Provider tree setup
```

### Core Layer

- **[BleService](lib/core/bluetooth/ble_service.dart)**: Singleton managing device scan/connect lifecycle. Emits `Stream<BleStatus>`, `Stream<RowingData>`, and `Stream<List<ScanResult>>`. Discovers the FTMS service (UUID `0x1826`) and subscribes to the Rower Data characteristic (UUID `0x2AD2`).
- **[FtmsParser](lib/core/bluetooth/ftms_parser.dart)**: Parses raw BLE notification bytes per the FTMS protocol. Uses flag bits to determine which optional fields are present (little-endian variable-length encoding).
- **[HeartRateService](lib/core/bluetooth/heart_rate_service.dart)**: generic BLE client for Heart Rate Profile sensors (service `0x180D`, characteristic `0x2A37`, parsed by [HeartRateParser](lib/core/bluetooth/heart_rate_parser.dart)). Independent from `BleService`: the phone holds two GATT connections. Emits `Stream<HrmStatus>` and `Stream<int>` (bpm; `0` = no valid reading, also after 10 s without notifications). Remembers the last sensor in SharedPreferences (`hrm.deviceId` / `hrm.deviceName`) and reconnects with [ReconnectLoop](lib/core/bluetooth/reconnect_loop.dart): on app start every 10 s for 1 minute (`autoConnect()`, fired from the eager `Provider` in `main.dart`), after a drop every 3 s until it reconnects or the user acts (`connect`/`startScan`/`forget`, or `disconnect()`, which also forgets the sensor). Connect attempts carry a generation: `connect()`, `startScan()`, `disconnect()`, `forget()` and `dispose()` supersede an in-flight attempt, which then disconnects quietly. Scans subscribe to `FlutterBluePlus.scanResults` only after `startScan` returns (the library replays its cached list to new listeners) and cannot run concurrently with the rower scan (`flutter_blue_plus` stops the previous one), so the Device tab disables one while the other scans. A Galaxy/Apple Watch needs a broadcaster app (e.g. *Heart for Bluetooth* on Wear OS) to expose `0x180D`; spec: [docs/superpowers/specs/2026-10-02-heart-rate-monitor-design.md](docs/superpowers/specs/2026-10-02-heart-rate-monitor-design.md).
- **[DatabaseService](lib/core/database/database_service.dart)**: SQLite wrapper. Schema has 4 tables with cascade deletes: `routines`, `interval_steps`, `workout_sessions`, `data_points`.

### Feature Layer (Provider + Screen pairs)

Each feature directory contains a `ChangeNotifier` provider and a screen widget:

- **device/**: BLE scan results and connection state for the rower (`DeviceProvider`) plus the heart rate sensor card (`HeartRateProvider`, [heart_rate_card.dart](lib/features/device/heart_rate_card.dart): search / connect / live bpm / disconnect / remembered-sensor states; hidden behind the full-screen "Bluetooth off / permission denied" view).
- **workout/**: Live workout tracking — phases (idle → active → paused → finished), routine step progression (time- or distance-based), 5-second telemetry sampling to `data_points`. Starting a workout pushes the fullscreen [ImmersiveWorkoutPage](lib/features/workout/immersive_workout_screen.dart) (outdoor scene + glass metric cards); the old `_FullscreenWorkoutPage` in `workout_screen.dart` is no longer navigated to.
  - **[scene/](lib/features/workout/scene/)**: 2.5D chase-camera scene engine used by the immersive page. `SceneCamera` projects world meters (x lateral, z forward, y up; camera 2.2 m high, rower at z = 9.5) to pixels; `SceneState` integrates real speed (`500 / split`), distance, stroke phase and oar puddles once per frame from a single `Ticker` in `SceneView`; `StrokeCycle` encodes the legs → back → arms sequence (drive 0–0.40, recovery 0.40–1.0); `TimeOfDay` (clashes with Material's — import material with `hide TimeOfDay`) gives the palette/light for the wall-clock hour; `Environment` (lake, river, coast, regatta) generates shore props deterministically per 50 m segment. Painters: `SkyPainter`, `WaterPainter` (GLSL `shaders/water.frag` via `WaterShader`, with a painted fallback when the program can't load), `ShorePainter`, `BoatPainter` (the rower faces the camera: rowers face the stern). Scenery is chosen in the idle view (`EnvironmentPicker` → `SceneSettings`, persisted in SharedPreferences `scene.environment`); the simulator panel can force the scene hour (`SceneSettings.hourOverride`). Spec: [docs/superpowers/specs/2026-10-02-immersive-scene-2-5d-design.md](docs/superpowers/specs/2026-10-02-immersive-scene-2-5d-design.md).
  - **[SeriesTracker](lib/features/workout/series_tracker.dart)**: pure class fed once per second from `WorkoutProvider._tick` (before `_checkStepCompletion`). Computes 500 m laps inside `work` steps (time interpolated between readings, pauses excluded) and per-repetition summaries for the current series (last 3: work split + total meters). It sanitizes monitor distance: deltas that are negative or > 10 m/s are ignored (FTMS packets without the distance flag parse as 0, monitors reset, rowing while paused). In-memory only, nothing is persisted. `WorkoutProvider.resume()` calls `series.rebase()`.
  - **[series_panels.dart](lib/features/workout/series_panels.dart)**: `WallClock` (HH:mm, shown in the top bars) and `SeriesPanels` (collapsible "500 m" and "Reps" panels under the SPM card, only for routines). Collapsed by default; expanded state persisted in `SharedPreferences` (`immersive.lapsExpanded`, `immersive.repsExpanded`). Styled like `_GlassMetricCard`.
- **routines/**: CRUD for `Routine` and `IntervalStep` records
- **history/**: Read-only list of completed `WorkoutSession` records

### Data Flow

BLE notification bytes → `FtmsParser.parse()` → `RowingData` → `BleService` stream → `WorkoutProvider` (via `StreamSubscription`) → `notifyListeners()` → UI rebuild.

Heart rate: `HeartRateService.bpmStream` → `WorkoutProvider` merges it into `_data` with `copyWith(heartRate:)` (the sensor overrides the FTMS heart-rate field; when the sensor is no longer connected the field goes back to 0 until the next FTMS packet). Everything downstream (`data_points`, TCX, charts, metric cards, `SessionStats.avgHeartRate/maxHeartRate`, shown as `avg/max` chips in history and session detail when `hasHeartRate`) just reads `RowingData.heartRate`.

Telemetry is buffered every 5 seconds during active workouts and batch-inserted to `data_points`. The session row is created on workout start (to get an ID) and updated with aggregated totals on finish.

### Key Models

- **RowingData**: Immutable real-time snapshot with `copyWith`.
- **Routine / IntervalStep**: Training plan; steps are typed (warmup/work/rest/cooldown) and can be duration- or distance-based with optional watt/SPM targets. Steps sharing a `groupId` form a series repeated `groupRepeatCount` times. `Routine.flattenedSteps` expands series (applying progressions); `Routine.flattenedStepPositions` is index-aligned with it and gives each step's `StepPosition` `(groupId, rep, repCount)`.
- **WorkoutSession / DataPoint**: Persisted session with nested telemetry samples.

### UI Conventions

- Bottom navigation with `IndexedStack` to preserve screen state.
- Material 3 dark theme, seed color `#0077B6`.
- Step-type color scheme: work = `#EF476F`, rest = `#06D6A0`, warmup = `#FFD166`, cooldown = `#118AB2`.
- Screen always-on during workouts via `wakelock_plus`.

### Dev Mode: Simulated Rower

Lets you develop and test the UI without hardware. Enabled at compile time with `--dart-define=SIMULATOR=true`; see the spec in [docs/superpowers/specs/2026-10-01-dev-simulator-design.md](docs/superpowers/specs/2026-10-01-dev-simulator-design.md).

- **Flag**: `kSimulator` in [dev_config.dart](lib/core/dev/dev_config.dart) is a `const bool.fromEnvironment('SIMULATOR')`. Without the define it is `false`, so every `if (kSimulator)` branch and the simulator classes are tree-shaken out of normal/release builds. No build script (`codemagic.yaml`, `.github/workflows`, gradle, xcconfig) passes the define — keep it that way.
- **[SimulatedBleService](lib/core/bluetooth/simulated_ble_service.dart)** `implements BleService` and is swapped in by `main.dart`; providers and screens are unaware of it. It auto-"connects" (emits `connected` / adapter `on`) in a microtask when the first listener subscribes, because `DeviceProvider` only listens to the streams and never reads the initial `status`. Emits one `RowingData` per second (with `heartRate: 0`); `startScan`/`connect` reconnect, `simulateDisconnect()` drops and reconnects after 3 s. `rawBytesStream`/`devicesStream` never emit (so the `DeviceProvider` watchdog never fires).
- **[SimulatedHeartRateService](lib/core/bluetooth/simulated_heart_rate_service.dart)** `implements HeartRateService`; shares the `RowingSimulator` (`main.dart` passes `(ble as SimulatedBleService).simulator`). The simulated rower sends `heartRate: 0` over FTMS so the pulse only arrives through the simulated sensor. `startScan()` lists one synthetic "Pulsómetro simulado"; `autoConnect()` does nothing (nothing is persisted); `simulateDisconnect()` drops and reconnects after 3 s (panel button "Simular caída del pulsómetro"), exposing the name as remembered meanwhile so the card shows "reconectando...".
- **[RowingSimulator](lib/core/dev/rowing_simulator.dart)**: pure physics (`tick()` = 1 s). Concept2 formulas: pace = `500·(2.80/W)^(1/3)`, kcal/s = `(W·4·0.8604 + 300)/3600`. Controls: `targetWatts` (30–500), `targetSpm` (14–40), `rowing`; `noise: false` for deterministic tests.
- **[SimulatorOverlay](lib/core/dev/simulator_overlay.dart)**: "SIMULADOR" banner + 🛠 control panel (presets Suave/Medio/Fuerte, ± watts/SPM, "Remando" switch, "Simular desconexión"). Mounted via `MaterialApp.builder`, i.e. **above the Navigator, where there is no `Overlay`**: do not use `Tooltip`/`tooltip:` params, `Slider`, bottom sheets, dropdowns or popup menus in it. It reads the service with `context.read<BleService>() as SimulatedBleService` on every use (hot reload creates a new service in `RowerApp.build`, but `Provider` keeps the original).
- **Separate database**: `DatabaseService` opens `rower_app_dev.db` instead of `rower_app.db`.
- **Nothing is uploaded to Strava**: `StravaApiService.uploadActivity` returns `null` before any request (all upload paths go through it), and the workout UIs (`_triggerStravaUpload` + routine-completed dialogs in both `workout_screen.dart` and `immersive_workout_screen.dart`) skip upload prompts. **Any new Strava write or upload prompt must also be guarded with `kSimulator`.** Strava login/import still work.

### Platform Notes

- **Android**: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (API 31+), legacy Bluetooth + location for older APIs, `WAKE_LOCK`. `minSdkVersion` 21.
- **iOS**: `NSBluetoothAlwaysUsageDescription` in Info.plist; `bluetooth-central` background mode enabled. Deployment target 15.0.
- **Windows**: needs Visual Studio with the "Desktop development with C++" workload and Windows Developer Mode (Flutter plugins use symlinks). SQLite runs through `sqflite_common_ffi`, initialized in `main()` for Windows/Linux. BLE uses `flutter_blue_plus` 2.x, whose federated Windows implementation is `flutter_blue_plus_winrt`.
- **flutter_blue_plus license**: 2.x requires a `license:` argument on `connect()`; [BleService](lib/core/bluetooth/ble_service.dart) uses `License.nonprofit` (`_fbpLicense`). Commercial use by a for-profit organization requires a paid license (`License.commercial`).
