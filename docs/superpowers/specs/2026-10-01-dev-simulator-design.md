# Modo desarrollo: simulador de remo

## Objetivo

Poder levantar la app sin un remo conectado y simular una sesión realista, para iterar sobre la UI (pantalla de entrenamiento, rutinas, historial) desde cualquier plataforma, incluida Windows.

## Activación

- `lib/core/dev/dev_config.dart` define `const bool kSimulator = bool.fromEnvironment('SIMULATOR');`.
- Se lanza con `flutter run -d windows --dart-define=SIMULATOR=true`.
- Sin el flag, `kSimulator` es `false` en tiempo de compilación: el simulador y su panel quedan fuera del build por tree-shaking.
- `.vscode/launch.json` incluye la configuración "RowMate (simulador)" con ese `--dart-define`.

## Arquitectura

`SimulatedBleService implements BleService` (la interfaz implícita de la clase). En `main.dart`, cuando `kSimulator` es `true` se instancia el simulador en lugar de `BleService()`. Los providers (`DeviceProvider`, `WorkoutProvider`) y las pantallas no cambian, porque siguen recibiendo un `BleService`.

El panel accede a los controles con `context.read<BleService>() as SimulatedBleService`. No se registra un provider aparte, porque en un hot reload `RowerApp` crea una instancia nueva y el panel quedaría controlando una distinta de la que emite los datos.

La física del remo vive en una clase pura, `RowingSimulator` (`lib/core/dev/rowing_simulator.dart`), con un método `tick()` que avanza 1 s y devuelve un `RowingData`. Se puede testear sin timers. `SimulatedBleService` solo la ejecuta con un `Timer`.

## RowingSimulator

| Campo | Cálculo |
|---|---|
| `powerWatts` | Watts objetivo ± 5 % de ruido |
| `strokeRate` | SPM objetivo ± 1 de ruido |
| `pace500mSeconds` | Fórmula de Concept2: `500 * (2.80 / watts)^(1/3)` |
| `distanceMeters` | Se acumula `500 / pace` metros por segundo |
| `strokeCount` | Se acumula `spm / 60` remadas por segundo, redondeado hacia abajo |
| `totalCalories` | Se acumula `(watts * 4 * 0.8604 + 300) / 3600` kcal por segundo (fórmula de Concept2) |
| `heartRate` | Converge un 10 % por segundo hacia `90 + watts * 0.35` (tope 190) mientras se rema, y hacia 70 en reposo |
| `elapsedSeconds` | Segundos remados |

**Controles:**
- `targetWatts`: 30–500, por defecto 150.
- `targetSpm`: 14–40, por defecto 24.
- `rowing`: por defecto `true`. Con `false`, SPM, watts y pace valen 0; distancia, remadas, calorías y tiempo quedan congelados y el pulso baja.

El ruido se puede desactivar (`noise: false`) para los tests.

## SimulatedBleService

Archivo: `lib/core/bluetooth/simulated_ble_service.dart`.

**Estado inicial:** `DeviceProvider` no lee `status` al crearse, solo escucha `statusStream`. Por eso el simulador emite `connected` en un microtask cuando aparece el primer listener de `statusStream`, y `BluetoothAdapterState.on` cuando aparece el primero de `adapterStateStream`. Una vez conectado, `connectedDeviceName` es `'Remo simulado'`.

**Datos:** mientras está conectado, un `Timer` de 1 s emite `simulator.tick()` en `dataStream`.

**Escaneo y conexión:**
- `devicesStream` y `rawBytesStream` no emiten nada.
- `startScan` reconecta el remo simulado si está desconectado. Así el botón "Buscar" sirve para volver después de una desconexión manual.
- `stopScan` no hace nada. `connect(device)` también reconecta.
- `disconnect()` detiene los datos y emite `disconnected` sin reconectar.
- `simulateDisconnect()` emite `disconnected` y, a los 3 s, `connected` otra vez, igual que la auto-reconexión real.

## Panel de control

Archivo: `lib/core/dev/simulator_overlay.dart`. Se monta con `MaterialApp.builder` solo si `kSimulator` es `true`, para que quede por encima de todas las rutas, incluida la de entrenamiento en pantalla completa. Como ese lugar está fuera del `Navigator`, no hay `Overlay`: el panel no usa bottom sheets, tooltips ni sliders.

- Un `FloatingActionButton.small` (icono `build`) despliega una tarjeta inline con:
  - presets de intensidad (`ActionChip`): Suave (100 W / 20 spm), Medio (180 W / 24 spm), Fuerte (280 W / 30 spm);
  - botones − / + para watts (de a 10) y SPM (de a 1);
  - un switch "Remando";
  - un botón "Simular desconexión".
- Una cinta `Banner` con el texto "SIMULADOR" en la esquina superior izquierda indica que no hay un remo real.

## Datos

- `DatabaseService` usa `rower_app_dev.db` cuando `kSimulator` es `true` y `rower_app.db` en caso contrario.
- **En modo simulador no se sube nada a Strava.**
  - Bloqueo central: `StravaApiService.uploadActivity` retorna `null` sin hacer ningún request cuando `kSimulator` es `true` (y lo registra con `debugPrint`). Todos los caminos de subida pasan por ahí: la subida de una sesión, la sincronización en lote y la subida manual desde el historial o el perfil. Esos caminos ya tratan `null` como un fallo.
  - UI: los dos `_triggerStravaUpload` de `lib/features/workout/workout_screen.dart` retornan de inmediato cuando `kSimulator` es `true`. Así, al terminar una sesión simulada no aparece ni el snackbar ni el diálogo de subida.
  - La lectura desde Strava (login y descarga de actividades) no se toca.

## Fuera de alcance

- Acelerar el tiempo para probar rutinas largas. Requeriría tocar el reloj de `WorkoutProvider`.
- Generar bytes FTMS crudos o probar `FtmsParser`.
- Simular el flujo de escaneo con una lista de dispositivos.

## Tests

- `test/rowing_simulator_test.dart`:
  - con más watts, el pace es menor (más rápido);
  - 203 W equivalen a un pace de unos 2:00;
  - la distancia, las remadas y el tiempo crecen mientras se rema;
  - con `rowing = false`, SPM y watts valen 0 y la distancia no cambia.
- `test/simulated_ble_service_test.dart` (con `fake_async`):
  - emite `connected` al primer listener y datos cada segundo;
  - `simulateDisconnect()` emite `disconnected` y después `connected`;
  - `startScan()` reconecta después de un `disconnect()`.
- `test/simulator_overlay_test.dart`:
  - el panel se abre y el botón + de watts sube el objetivo, sin errores por falta de `Overlay`.
