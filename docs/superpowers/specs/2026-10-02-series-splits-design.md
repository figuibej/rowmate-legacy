# Parciales de 500 m y comparación de series en la pantalla inmersiva

## Objetivo

Durante una rutina con series, el remero tiene que poder ver sin frenar:
1. si mantiene el ritmo dentro de cada paso de trabajo, a partir de vueltas de 500 m;
2. cuántos metros lleva en la repetición actual de la serie;
3. cómo le fue en las repeticiones anteriores de la misma serie hoy (las últimas 3);
4. la hora actual.

Los puntos 1 a 3 se pueden colapsar. Con los paneles colapsados, la pantalla se ve igual que hoy, más la hora.

## Definiciones

- **Serie:** un grupo de pasos (`groupId`) repetido `groupRepeatCount` veces.
- **Repetición:** una pasada completa por los pasos del grupo.
- **Paso suelto:** un paso sin `groupId`. No pertenece a ninguna serie.
- **Vuelta (lap):** cada 500 m completos dentro de un paso de **trabajo** (`StepType.work`), contados desde el inicio de ese paso.
  - Un paso de menos de 500 m no genera vueltas.
  - Los pasos de enfriamiento, descanso o calentamiento no generan vueltas.
  - El tiempo de cada vuelta se interpola linealmente entre las dos lecturas en las que se cruza la marca, para tener precisión por debajo del segundo.
- **Tiempo:** se usan los segundos activos del entrenamiento (`WorkoutProvider.totalElapsedSeconds`). El tiempo en pausa no cuenta.
- **Metros de la repetición:** la distancia recorrida en todos los pasos de la repetición actual (trabajo, enfriamiento y los demás).
- **Split de una repetición anterior:** el tiempo de trabajo dividido por los metros de trabajo de esa repetición, por 500. Si no hubo metros de trabajo, se muestra "—".
- **Comparación:** las últimas 3 repeticiones **completas** de la serie en curso, en esta sesión, de la más reciente a la más antigua. Al empezar otra serie, o un paso suelto, la lista se vacía.

## Arquitectura

### `Routine.flattenedStepPositions` (lib/core/models/routine.dart)

Devuelve una lista alineada índice por índice con `flattenedSteps`. Cada elemento es un `StepPosition = ({String? groupId, int rep, int repCount})`:
- `rep` empieza en 1;
- un paso suelto da `(null, 1, 1)`.

`flattenedSteps` no se modifica.

### `SeriesTracker` (lib/features/workout/series_tracker.dart)

Es una clase pura, sin timers ni Flutter.

| Miembro | Descripción |
|---|---|
| `begin(int distanceMeters)` | Reinicia todo, tomando como base la distancia del monitor al iniciar |
| `update({stepIndex, step, position, distanceMeters, elapsedSeconds})` | Registra una lectura del paso actual |
| `laps` | Vueltas completas del paso actual (`Lap(number, seconds)`) |
| `isWorkStep` | Si el paso actual es de trabajo |
| `currentLapMeters`, `currentLapSeconds` | La vuelta en curso |
| `inSeries`, `rep`, `repCount`, `repMeters` | La repetición actual |
| `previousReps` | Hasta 3 `RepSummary(rep, totalMeters, workMeters, workSeconds)`, con `workSplitSeconds` calculado |

Un cambio de `stepIndex` cierra el paso anterior. Si además cambia la repetición dentro del mismo grupo, la repetición que termina se agrega como `RepSummary`.

### `WorkoutProvider`

- `startWithRoutine` guarda `routine.flattenedStepPositions` y llama a `series.begin(distancia actual)`.
- `_tick`, antes de `_checkStepCompletion()`, llama a `series.update(...)` con el paso actual. Si el paso termina en ese tick, el siguiente `update` ya corresponde al paso nuevo.
- `reset()` vuelve a llamar a `series.begin(0)`.
- Expone `SeriesTracker get series`.
- Nada de esto se guarda en la base.

### UI (lib/features/workout/series_panels.dart)

- `WallClock`: un chip con la hora `HH:mm`. Tiene su propio `Timer` de 1 s, así que sigue andando también en pausa.
- `SeriesPanels({required SeriesTracker tracker})`: dos paneles colapsables.
  - **Parciales:**
    - colapsado, es un chip con icono de cronómetro y el texto "500 m";
    - expandido, muestra las últimas 4 vueltas (`#n m:ss.d`), la vuelta en curso (`▸ 340 m · 1:15.0`) y, si hay serie, `Rep 3/6 · 1.245 m`;
    - en un paso que no es de trabajo muestra "Sin parciales en este paso".
  - **Series anteriores:**
    - solo aparece si `inSeries`;
    - colapsado, es un chip con icono de historial y el texto "Reps";
    - expandido, muestra filas `Rep 4 · 1:54 · 741 m`, o "Sin repeticiones completas" si todavía no hay ninguna.
  - El estado expandido o colapsado de cada panel se guarda en `SharedPreferences` (`immersive.lapsExpanded`, `immersive.repsExpanded`). Por defecto los dos están colapsados.
- Integración en `ImmersiveWorkoutPage`:
  - `WallClock` va centrado arriba, a la altura de las tarjetas de SPM y split (`padding.top + 90`).
  - `_ImmersiveHUD` recibe un widget opcional `belowSpm`, que se dibuja debajo de la tarjeta de SPM en la misma columna izquierda. Se le pasa `SeriesPanels` solo cuando hay rutina.

## Fuera de alcance

- Guardar las vueltas o las repeticiones en la base o mostrarlas en el historial.
- Comparar contra sesiones anteriores de la misma rutina.
- Cambios en la pantalla vieja `_FullscreenWorkoutPage`.

## Tests

- `test/routine_positions_test.dart`: posiciones alineadas con `flattenedSteps` para pasos sueltos y grupos repetidos.
- `test/series_tracker_test.dart`:
  - vuelta interpolada (3 m/s da 166,67 s);
  - dos vueltas en un mismo paso;
  - un paso de trabajo de menos de 500 m no genera vueltas;
  - un paso de enfriamiento no genera vueltas pero suma a `repMeters`;
  - el cambio de repetición crea un `RepSummary` con el split de trabajo;
  - el tope de 3 repeticiones, con la más reciente primero;
  - un grupo nuevo vacía `previousReps`;
  - la vuelta en curso.
- `test/series_panels_test.dart`:
  - los paneles arrancan colapsados;
  - tocar el chip los expande y guarda la preferencia;
  - el panel de repeticiones no aparece si no hay serie.
- Manual, con el simulador: una rutina 4 × (1000 m trabajo + 1 min enfriamiento).
