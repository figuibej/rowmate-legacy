# Pulsómetro BLE genérico (Heart Rate Profile)

## Objetivo

Conectar cualquier sensor de frecuencia cardíaca que exponga el servicio BLE estándar
Heart Rate (`0x180D`): bandas pectorales (Polar, Garmin, Wahoo…) y relojes que lo
transmitan. Funciona en Android e iOS con `flutter_blue_plus`, que ya está en el proyecto.

El pulso se muestra en vivo, se guarda en cada `data_point`, viaja a Strava en el TCX
y aparece como promedio y máximo en el historial.

## Contexto: Galaxy Watch y otros smartwatches

Un Galaxy Watch (el de prueba es un Watch 7, Wear OS 5) **no transmite el pulso por
BLE de fábrica**: Samsung Health no expone el servicio `0x180D`. Hace falta una app en
el reloj que haga de "broadcaster" (por ejemplo *Heart for Bluetooth* en Wear OS). Con
esa app corriendo, el reloj se comporta como una banda estándar y la app no necesita
nada específico de Samsung. Con Apple Watch pasa lo mismo (HeartCast, ECHO HR…).

La tarjeta de la app lo explica en el estado "sin sensor".

## Definiciones

- **Pulsómetro / sensor:** periférico BLE con el servicio `0x180D` y el characteristic
  Heart Rate Measurement `0x2A37` (notify).
- **bpm:** latidos por minuto. `0` significa "sin lectura válida".
- **Sensor recordado:** el último sensor conectado con éxito, guardado en
  `SharedPreferences` (`hrm.deviceId`, `hrm.deviceName`).
- **Estado del sensor (`HrmStatus`):** `scanning`, `connecting`, `connected`,
  `disconnected`.

## Arquitectura

El remo no cambia de responsabilidad. El teléfono mantiene dos conexiones GATT a la
vez: `BleService` (remo, FTMS) y `HeartRateService` (pulsómetro). `WorkoutProvider`
fusiona los dos streams en un único `RowingData`, así todo lo que ya consume
`RowingData.heartRate` sigue funcionando sin tocarlo.

```
0x2A37 bytes → HeartRateParser → HeartRateService.bpmStream ─┐
                                                              ├→ WorkoutProvider._data (copyWith heartRate)
0x2AD2 bytes → FtmsParser → BleService.dataStream ────────────┘
                                   HeartRateService.statusStream/bpmStream → HeartRateProvider → _HeartRateCard
```

Archivos nuevos:

| Archivo | Contenido |
|---|---|
| `lib/core/bluetooth/heart_rate_parser.dart` | `HeartRateParser`, `HeartRateReading` |
| `lib/core/bluetooth/heart_rate_service.dart` | `HrmStatus`, `HeartRateService` |
| `lib/core/bluetooth/simulated_heart_rate_service.dart` | `SimulatedHeartRateService` |
| `lib/features/device/heart_rate_provider.dart` | `HeartRateProvider` |

Archivos modificados: `main.dart`, `workout_provider.dart`, `device_screen.dart`,
`ble_service.dart` (arreglo del escaneo), `simulated_ble_service.dart`,
`rowing_simulator.dart`, `simulator_overlay.dart`, `workout_session.dart`
(`SessionStats`), `database_service.dart` (`getStatsForSessions`),
`history_screen.dart`, `session_detail_screen.dart`, `app_es.arb`, `app_en.arb`.

Sin migración de base de datos: `data_points.heart_rate` ya existe.

## `HeartRateParser` (lib/core/bluetooth/heart_rate_parser.dart)

Clase pura. `static HeartRateReading? parse(List<int> bytes)`.

Formato del Heart Rate Measurement (Bluetooth SIG):

- Byte 0: flags.
  - Bit 0: `0` → bpm en uint8 (byte 1); `1` → bpm en uint16 little-endian (bytes 1-2).
  - Bits 1-2: estado de contacto. `0b00`/`0b01` → no soportado; `0b10` → soportado,
    sin contacto; `0b11` → soportado, con contacto.
  - Bit 3: Energy Expended presente (uint16). Se salta.
  - Bit 4: intervalos RR presentes (uint16 cada uno). Se ignoran.
- `HeartRateReading({required int bpm, required bool? sensorContact})`:
  `sensorContact` es `null` si el sensor no lo informa.

Devuelve `null` si `bytes` está vacío o es más corto de lo que exigen los flags.

## `HeartRateService` (lib/core/bluetooth/heart_rate_service.dart)

Misma forma que `BleService`, acotada a un sensor.

### API

```dart
enum HrmStatus { scanning, connecting, connected, disconnected }

class HeartRateService {
  Stream<HrmStatus> get statusStream;
  Stream<int> get bpmStream;                 // 0 = sin lectura válida
  Stream<List<ScanResult>> get devicesStream;
  HrmStatus get status;
  int get bpm;                               // último valor emitido, 0 si no hay
  String? get connectedDeviceName;
  String? get rememberedDeviceName;          // null si no hay sensor recordado
  bool get isRetrying;                       // true mientras corre una cadencia de reintentos

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)});
  Future<void> stopScan();
  Future<void> connect(BluetoothDevice device);
  Future<void> autoConnect();                // al arrancar la app
  Future<void> disconnect();                 // manual: desconecta y olvida
  Future<void> forget();                     // olvida un sensor recordado sin conexión
  void dispose();
}
```

### Escaneo

- `FlutterBluePlus.startScan(withServices: [Guid('180D')], timeout: timeout)`. El
  filtro por servicio lo aplica el sistema operativo.
- Se suscribe a `FlutterBluePlus.scanResults` **después** de que `startScan` devuelva
  (ahí la librería ya vació la lista cacheada, que se reemite a cada listener nuevo; si
  se suscribiera antes recibiría los resultados del escaneo anterior) y **cancela la
  suscripción** al terminar el escaneo. No se filtra por `advertisementData.serviceUuids`
  en el cliente: en iOS un servicio puede venir en los "overflow UUIDs" y no aparecer en
  esa lista aunque el sistema lo haya aceptado.
- `flutter_blue_plus` corta cualquier escaneo en curso al llamar a `startScan`. La
  pantalla no permite escanear pulsómetro mientras el remo está en `scanning` o
  `connecting`, ni escanear remo mientras el pulsómetro está en `scanning`.
- Al terminar, si sigue en `scanning`, vuelve a `disconnected`.

### Conexión

1. `status = connecting`; `device.connect(license: License.nonprofit, autoConnect: false, timeout: 15 s)`.
2. `discoverServices()`; buscar `0x180D` → `0x2A37`. Si falta alguno: desconectar,
   `status = disconnected`, error "no es un pulsómetro compatible". No se recuerda el
   sensor.
3. `setNotifyValue(true)` y escuchar `lastValueStream`.
4. Guardar `remoteId.str` y `platformName` en `SharedPreferences` (`hrm.deviceId`,
   `hrm.deviceName`).
5. Registrar el listener de `connectionState` **después** de conectar (como el remo).
   Si llega `disconnected` sin ser manual: `status = disconnected`, limpiar y programar
   reconexión.
6. `status = connected`.

Las excepciones de `discoverServices` / `setNotifyValue` se capturan, se registran con
`debugPrint('[HRM] …')` y disparan una desconexión interna sin olvidar el sensor.

### Lecturas

- Cada notificación pasa por `HeartRateParser`. Si `sensorContact == false` se emite `0`;
  si no, el bpm leído.
- Watchdog interno: si pasan 10 s sin notificaciones estando `connected`, se emite `0`.
  No corta la conexión. Vuelve a emitir el valor real con la siguiente notificación.
- `bpmStream` emite en cada notificación (típicamente 1 Hz).

### Reconexión y memoria

- **Al arrancar** (`autoConnect()`, llamado desde `main.dart`): si hay sensor recordado,
  `BluetoothDevice.fromId(id).connect(...)` directo, sin escanear. En Android se conecta
  por dirección; en iOS por el identificador que el sistema ya conoce del periférico. Si
  falla, reintenta cada 10 s durante 1 minuto (6 intentos) y después queda en
  `disconnected` con `isRetrying == false`.
- **Caída estando conectado:** reintenta cada 3 s, indefinidamente, hasta reconectar o
  hasta `disconnect()`/`forget()`.
- **`disconnect()`** (manual): cancela reintentos, desconecta y borra el sensor recordado.
  Si no se borrara, la reconexión lo volvería a enganchar.
- **`forget()`**: cancela reintentos y borra el sensor recordado sin tocar la conexión
  (se usa cuando está recordado pero no conectado).
- **`connect(device)`** manual sobre el sensor recordado reinicia la cadencia de arranque.

### Adaptador apagado o sin permiso

No se duplica lógica: la vista de escaneo de la pestaña Dispositivo ya ocupa toda la
pantalla con "Bluetooth apagado", y la tarjeta queda detrás. Los reintentos fallan solos
y siguen su cadencia.

## `HeartRateProvider` (lib/features/device/heart_rate_provider.dart)

`ChangeNotifier` que escucha `statusStream`, `bpmStream` y `devicesStream`. Expone:
`status`, `isConnected`, `isScanning`, `bpm`, `scanResults`, `connectedDeviceName`,
`rememberedDeviceName`, `isRetrying`, `error`, y los métodos `startScan`, `connect`,
`disconnect`, `forget`, `retry` (= `HeartRateService.autoConnect()`, que reinicia la
cadencia de arranque sobre el sensor recordado). Los errores de `connect`/`startScan` se
capturan y quedan en `error` hasta la próxima acción.

## Fusión en `WorkoutProvider`

Constructor: `WorkoutProvider(BleService ble, HeartRateService hrm, DatabaseService db)`.

- `int? _hrmBpm`: `null` si el pulsómetro no está `connected`; si no, el último bpm
  (incluido `0`).
- Paquete del remo: `_data = d.copyWith(heartRate: _hrmBpm ?? d.heartRate)`. El
  pulsómetro manda sobre el FTMS; sin pulsómetro se respeta el monitor, como hoy.
- bpm del pulsómetro: `_hrmBpm = bpm; _data = _data.copyWith(heartRate: bpm);
  notifyListeners()`. El pulso se actualiza aunque el remo esté quieto o desconectado.
- Pulsómetro pasa a `disconnected`: `_hrmBpm = null; _data = _data.copyWith(heartRate: 0)`.
  El siguiente paquete FTMS repone su propio valor si lo tuviera.

Nada aguas abajo cambia: muestreo cada 5 s a `data_points`, último punto en `finish()`,
TCX de Strava, tarjetas de pulso de `device_screen`, `workout_screen` e
`immersive_workout_screen`, y el gráfico del detalle ya leen `heartRate`.

`DeviceProvider` no cambia: la grilla del remo sigue mostrando pulso solo si viene por
FTMS. El bpm del pulsómetro se ve en su tarjeta.

## Estadísticas de sesión

- `SessionStats` suma `avgHeartRate` (media redondeada de los puntos con
  `heartRate > 0`) y `maxHeartRate`. Ambos `0` si no hubo pulso.
- `DatabaseService.getStatsForSessions` agrega `heart_rate` a las columnas que consulta
  (hoy no la carga, por eso el `DataPoint` que construye queda con `heartRate = 0`).
- `history_screen` (`_SessionCard`) y `session_detail_screen` (resumen) muestran un chip
  "Pulso" con `avg · max` en `MetricColors.heartRate`, solo cuando `maxHeartRate > 0`.

## Tarjeta "Pulsómetro" (device_screen.dart)

`_HeartRateCard`, mismo estilo que `_MetricCard` (fondo `#1A2E45`, radio 16, borde
superior de 3 px en `MetricColors.heartRate`). Se coloca al final de `_ScanView` (debajo
de la lista del remo) y de `_ConnectedView` (debajo de la grilla, antes del debug).
Lee `HeartRateProvider` y `DeviceProvider` (para deshabilitar el escaneo cruzado).

| Estado | Contenido | Acciones |
|---|---|---|
| Sin sensor (`disconnected`, nada recordado) | Corazón apagado, "Pulsómetro · Sin sensor". Pista en gris: "Un smartwatch necesita una app que transmita el pulso por Bluetooth (p. ej. Heart for Bluetooth en Wear OS)." | **Buscar** (deshabilitado si el remo está `scanning` o `connecting`) |
| Buscando (`scanning`) | Spinner + lista de sensores (nombre o "Sensor desconocido", id) | Tocar uno → `connect` |
| Conectando (`connecting`) | "Conectando a {nombre}…" + spinner | — |
| Conectado (`connected`) | Corazón en color, nombre, bpm en fuente 52. Si bpm es 0: "--" | **Desconectar** |
| Recordado, sin conexión | "{nombre} · reconectando…" mientras `isRetrying`; luego "{nombre} · no encontrado" | **Conectar** (`retry`), **Olvidar** (`forget`), **Buscar otro** |
| Error | Texto rojo bajo el contenido del estado actual | — |

**Buscar otro** escanea sin olvidar el sensor recordado; al conectar con éxito otro
sensor, ese pasa a ser el recordado.

El botón **Buscar** del remo (`_ScanView`) se deshabilita mientras el pulsómetro está en
`scanning`.

Textos nuevos en `app_es.arb` / `app_en.arb`: título de la tarjeta, "sin sensor", pista
del smartwatch, buscar, buscar otro, conectando a, desconectar, conectar, olvidar,
reconectando, no encontrado, sensor desconocido, sensor incompatible, error al conectar.

## Arreglo colateral en `BleService.startScan`

Hoy registra un listener de `FlutterBluePlus.scanResults` en cada llamada, antes de
`startScan`, y nunca lo cancela. Como `scanResults` es global y reemite la última lista,
un escaneo de pulsómetro metería el reloj en la lista del remo. Cambios:

- suscribirse **después** de que `FlutterBluePlus.startScan` devuelva (la lista ya está
  vacía);
- guardar la suscripción y cancelarla al terminar el escaneo (y en `stopScan` /
  `dispose`).

No se filtra por UUID anunciado en el cliente, por el mismo motivo que en
`HeartRateService` (overflow UUIDs en iOS).

## Simulador (`SIMULATOR=true`)

- `SimulatedHeartRateService(RowingSimulator simulator)` `implements HeartRateService`.
  Comparte el simulador del `SimulatedBleService` (`main.dart` se lo pasa).
  - `startScan()`: `status = scanning`, emite una lista con un `ScanResult` sintético
    (`BluetoothDevice.fromId('SIM:HRM')`, `advName` "Pulsómetro simulado",
    `serviceUuids: [Guid('180D')]`), y vuelve a `disconnected` tras el timeout si no se
    conectó.
  - `connect()` / `autoConnect()`: `status = connected` y emite `simulator.heartRate`
    cada segundo. `autoConnect()` **no** conecta solo: en modo simulador no hay sensor
    recordado (no se escribe en `SharedPreferences`), así la tarjeta arranca en "sin
    sensor" y se puede probar el flujo completo.
  - `disconnect()` / `forget()`: cortan y vuelven a `disconnected`.
  - `simulateDisconnect({reconnectAfter = 3 s})`: cae y reconecta, para probar la
    reconexión en `WorkoutProvider` y en la tarjeta.
- `RowingSimulator` no cambia su `tick()` (sigue devolviendo `heartRate`, y
  `rowing_simulator_test` sigue igual); además expone el último valor con
  `int get heartRate`. `SimulatedBleService` emite `tick().copyWith(heartRate: 0)`, como
  el monitor real, para que el pulso llegue solo por el pulsómetro simulado.
- El panel 🛠 de `SimulatorOverlay` suma el botón "Simular desconexión del pulsómetro"
  (sin `Tooltip`, como el resto del panel).

## Manejo de errores

- Fallo de conexión o sensor incompatible → `HeartRateProvider.error` visible en la
  tarjeta; el servicio queda `disconnected`. Si el sensor estaba recordado y fue
  `autoConnect`, siguen los reintentos de arranque.
- Excepciones al suscribirse → desconexión interna sin olvidar el sensor → reintentos de
  caída.
- Escaneo sin resultados → vuelve a "sin sensor" con la pista del smartwatch.

## Fuera de alcance

- Zonas de frecuencia cardíaca (requiere FC máxima en el perfil).
- Nivel de batería del sensor (`0x180F`).
- Más de un sensor a la vez.
- Mostrar el bpm del pulsómetro en la grilla del remo de la pestaña Dispositivo.

## Tests (`test/`)

- `heart_rate_parser_test`: bpm uint8 y uint16; contacto no soportado / sin contacto /
  con contacto; paquete con Energy Expended y RR; bytes vacíos o truncados → `null`.
- `heart_rate_service_test`: solo la lógica aislable de `HeartRateService` (staleness y
  cadencia de reintentos), extraída a helpers puros si hace falta. Lo que depende de
  `FlutterBluePlus` estático no se testea, igual que `BleService`.
- `simulated_heart_rate_service_test`: escaneo emite el sensor sintético; conectar emite
  bpm cada segundo; `simulateDisconnect` cae y reconecta (`fake_async`).
- `workout_provider_hr_test`: con `BleService` y `HeartRateService` falsos
  (`implements`), prioridad pulsómetro > FTMS, bpm sin paquetes del remo, vuelta a `0`
  al desconectar y FTMS repone su valor.
- `session_stats_test`: `avgHeartRate` / `maxHeartRate` ignoran ceros y quedan en `0`
  sin pulso.
- `heart_rate_card_test`: widget test de los estados de la tarjeta usando
  `SimulatedHeartRateService`, incluido el botón Buscar deshabilitado mientras el remo
  escanea.
