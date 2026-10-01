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

El simulador también se registra con su tipo concreto (`Provider<SimulatedBleService>`) para que el panel de control pueda acceder a sus controles.

## SimulatedBleService

Archivo: `lib/core/bluetooth/simulated_ble_service.dart`.

**Estado inicial:** `status = connected`, `connectedDeviceName = 'Remo simulado'`, adaptador en `on`.

**Escaneo:** `startScan` y `stopScan` no hacen nada y `devicesStream` emite una lista vacía. `connect(device)` no se usa.

**Datos:** un `Timer` de 1 s emite un `RowingData` en `dataStream` a partir de los parámetros actuales:

| Campo | Cálculo |
|---|---|
| `powerWatts` | Watts objetivo ± 5 % de ruido |
| `strokeRate` | SPM objetivo ± 1 de ruido |
| `pace500mSeconds` | Fórmula de Concept2: `500 * (2.80 / watts)^(1/3)` |
| `distanceMeters` | Se acumula `500 / pace` metros por segundo |
| `strokeCount` | Se acumula `spm / 60` remadas por segundo, redondeado |
| `totalCalories` | Se acumula `watts * 4 / 4184 + 0.35` kcal por segundo (aproximación de Concept2) |
| `heartRate` | Converge suavemente hacia `90 + watts * 0.35`, con tope de 190 |
| `elapsedSeconds` | Segundos desde el inicio mientras se rema |

**Controles públicos:**
- `targetWatts`: 30–500, por defecto 150.
- `targetSpm`: 14–40, por defecto 24.
- `rowing`: con `false` se emiten SPM, watts y pace en 0; distancia, remadas y tiempo quedan congelados y el pulso baja.
- `simulateDisconnect()`: emite `disconnected` y, a los 3 s, `connected` otra vez, igual que la auto-reconexión real.
- Presets: Suave (100 W / 20 spm), Medio (180 W / 24 spm), Fuerte (280 W / 30 spm).

**Streams de solo depuración:** `rawBytesStream` no emite nada.

## Panel de control

Archivo: `lib/core/dev/simulator_panel.dart`. Se monta en `MainShell` solo si `kSimulator` es `true`.

- Un `FloatingActionButton` pequeño (icono `build`) abre un `ModalBottomSheet` con:
  - presets de intensidad;
  - sliders de watts y SPM;
  - un switch "Remando";
  - un botón "Simular desconexión".
- Una cinta "SIMULADOR" en la esquina superior indica que no hay un remo real.

## Datos

- `DatabaseService` usa `rower_app_dev.db` cuando `kSimulator` es `true` y `rower_app.db` en caso contrario.
- **En modo simulador no se sube nada a Strava.**
  - Bloqueo central: `StravaApiService.uploadActivity` retorna `null` sin hacer ningún request cuando `kSimulator` es `true` (y lo registra con `debugPrint`). Todos los caminos de subida pasan por ahí: la subida de una sesión, la sincronización en lote y la subida manual desde el historial o el perfil. Esos caminos ya tratan `null` como un fallo.
  - UI: los dos `_triggerStravaUpload` de `lib/features/workout/workout_screen.dart` retornan de inmediato cuando `kSimulator` es `true`. Así, al terminar una sesión simulada no aparece ni el snackbar ni el diálogo de subida.
  - La lectura desde Strava (login y descarga de actividades) no se toca.

## Fuera de alcance

- Acelerar el tiempo para probar rutinas largas. Requeriría tocar el reloj de `WorkoutProvider`.
- Generar bytes FTMS crudos o probar `FtmsParser`.
- Simular el flujo de escaneo y conexión.

## Tests

`test/simulated_ble_service_test.dart`, usando `fake_async`:
- Con más watts, el pace es menor (más rápido).
- La distancia y las remadas crecen con el tiempo mientras se rema.
- Con `rowing = false`, SPM y watts valen 0 y la distancia no cambia.
- `simulateDisconnect()` emite `disconnected` y después `connected`.
