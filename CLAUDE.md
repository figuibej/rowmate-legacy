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
├── core/           # Platform services: BLE, database, domain models
├── features/       # One folder per screen (device, workout, routines, history)
├── shared/         # Theme and reusable widgets
└── main.dart       # App entry point, Provider tree setup
```

### Core Layer

- **[BleService](lib/core/bluetooth/ble_service.dart)**: Singleton managing device scan/connect lifecycle. Emits `Stream<BleStatus>`, `Stream<RowingData>`, and `Stream<List<ScanResult>>`. Discovers the FTMS service (UUID `0x1826`) and subscribes to the Rower Data characteristic (UUID `0x2AD2`).
- **[FtmsParser](lib/core/bluetooth/ftms_parser.dart)**: Parses raw BLE notification bytes per the FTMS protocol. Uses flag bits to determine which optional fields are present (little-endian variable-length encoding).
- **[DatabaseService](lib/core/database/database_service.dart)**: SQLite wrapper. Schema has 4 tables with cascade deletes: `routines`, `interval_steps`, `workout_sessions`, `data_points`.

### Feature Layer (Provider + Screen pairs)

Each feature directory contains a `ChangeNotifier` provider and a screen widget:

- **device/**: BLE scan results and connection state
- **workout/**: Live workout tracking — phases (idle → active → paused → finished), routine step progression (time- or distance-based), 5-second telemetry sampling to `data_points`
- **routines/**: CRUD for `Routine` and `IntervalStep` records
- **history/**: Read-only list of completed `WorkoutSession` records

### Data Flow

BLE notification bytes → `FtmsParser.parse()` → `RowingData` → `BleService` stream → `WorkoutProvider` (via `StreamSubscription`) → `notifyListeners()` → UI rebuild.

Telemetry is buffered every 5 seconds during active workouts and batch-inserted to `data_points`. The session row is created on workout start (to get an ID) and updated with aggregated totals on finish.

### Key Models

- **RowingData**: Immutable real-time snapshot with `copyWith`.
- **Routine / IntervalStep**: Training plan; steps are typed (warmup/work/rest/cooldown) and can be duration- or distance-based with optional watt/SPM targets.
- **WorkoutSession / DataPoint**: Persisted session with nested telemetry samples.

### UI Conventions

- Bottom navigation with `IndexedStack` to preserve screen state.
- Material 3 dark theme, seed color `#0077B6`.
- Step-type color scheme: work = `#EF476F`, rest = `#06D6A0`, warmup = `#FFD166`, cooldown = `#118AB2`.
- Screen always-on during workouts via `wakelock_plus`.

### Platform Permissions

- **Android**: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (API 31+), legacy Bluetooth + location for older APIs, `WAKE_LOCK`. `minSdkVersion` 21.
- **iOS**: `NSBluetoothAlwaysUsageDescription` in Info.plist; `bluetooth-central` background mode enabled.
