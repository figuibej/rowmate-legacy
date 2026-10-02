# Escena inmersiva 2.5D: cámara de persecución, agua en GPU y 4 escenarios

## Objetivo

Reemplazar la escena plana de la pantalla inmersiva (`_OutdoorScenePainter` + `_RowingAvatarPainter`) por una escena en perspectiva al estilo "cámara de persecución" de EXR: el paisaje viene hacia el remero a la velocidad real del monitor, el agua refleja el cielo y brilla con el sol, el bote se ve desde atrás con un remero articulado que hace la secuencia real de la palada, y hay cuatro escenarios a elegir. Todo en Flutter puro (CustomPainter + un fragment shader GLSL), sin dependencias nuevas, en Android, iOS, macOS y Windows.

El HUD (tarjetas de métricas, barra de etapas, paneles de series, controles) no cambia, salvo la banda de tiempo + distancia, que pasa del centro inferior a la esquina inferior izquierda para no tapar el bote.

## Decisiones

- **Técnica:** 2.5D (proyección en perspectiva dibujada) y no 3D real. `flutter_scene` es experimental y no corre en Windows; Unity embebido no corre en escritorio y duplica el proyecto.
- **Cámara:** una sola, fija, detrás y arriba del bote mirando hacia el punto de fuga.
- **Luz:** sigue la hora real del reloj (amanecer, día, atardecer, noche con luna y estrellas).
- **Escenarios:** lago alpino, río urbano, costa, canal de regata. Se elige antes de remar y se recuerda.
- **Velocidad:** la del monitor, `500 / split` m/s. Sin remar, el bote desacelera hasta detenerse.

## Estructura de archivos

```
lib/features/workout/scene/
├── scene_camera.dart        # Proyección mundo → pantalla
├── scene_state.dart         # Velocidad, distancia, fase de palada, cabeceo, hora
├── stroke_cycle.dart        # Secuencia piernas/espalda/brazos y ángulo del remo
├── time_of_day.dart         # Paleta y posición del sol/luna según la hora
├── environment.dart         # Environment, EnvironmentId, ShoreProp, generador
├── environments/
│   ├── lake_environment.dart
│   ├── river_environment.dart
│   ├── coast_environment.dart
│   └── regatta_environment.dart
├── painters/
│   ├── sky_painter.dart     # Cielo, sol/luna, estrellas, nubes, silueta lejana
│   ├── water_painter.dart   # Usa el shader; fallback con degradé
│   ├── shore_painter.dart   # Objetos de orilla proyectados
│   ├── boat_painter.dart    # Bote + remero + remos + salpicaduras
│   └── thumbnail_painter.dart # Miniatura estática para el selector
├── water_shader.dart        # Carga y cachea el FragmentProgram
├── scene_settings.dart      # ChangeNotifier: escenario elegido (+ hora forzada en dev)
├── environment_picker.dart  # Fila de tarjetas para elegir escenario
└── scene_view.dart          # Widget que compone las capas con un Ticker
shaders/water.frag           # Shader GLSL del agua (declarado en pubspec `shaders:`)
```

`immersive_workout_screen.dart` pasa a usar `SceneView` como capas 1 y 2 del `Stack` y elimina los tres `AnimationController` de escena. `_StageTimelineBar`, `_FreeWorkoutTopBar`, `_ImmersiveHUD` y el resto no cambian.

## Cámara (`SceneCamera`)

Sistema de mundo en metros: `x` lateral (0 = eje del bote, positivo a la derecha), `z` distancia hacia adelante desde la cámara, `y` altura sobre el agua.

- Constantes: altura de cámara `camHeight = 2.2`, el remero está en `boatZ = 9.5` (con 8.0 la popa quedaba pegada al borde inferior en horizontal), el horizonte en `horizonY = 0.40 * h` (vertical) o `0.42 * h` (horizontal), `focal = size.shortestSide * 1.0`.
- Proyección de un punto `(x, y, z)` con `z > 0.5`:
  - `screenX = w / 2 + focal * x / z`
  - `screenY = horizonY + focal * (camHeight - y) / z`
  - `scale = focal / z` (píxeles por metro a esa distancia)
- Inversa para el agua (dada una fila de pantalla `sy > horizonY`): `z = focal * camHeight / (sy - horizonY)`, `x = (sx - w/2) * z / focal`.
- Cualquier `z <= 0.5` no se dibuja.

## Estado de la escena (`SceneState`)

Se actualiza una vez por frame desde el `Ticker` con `dt` en segundos y los datos del `WorkoutProvider`:

- `targetSpeed = pace500m > 0 && isActive ? 500 / pace500m : 0` (m/s).
- `speed` tiende a `targetSpeed` con una constante de tiempo de 1,5 s (`speed += (target - speed) * min(1, dt / 1.5)`). Así el bote desacelera al dejar de remar y en pausa.
- `distance += speed * dt` (metros de mundo recorridos; mueve la orilla y las ondas).
- `strokePhase` avanza a `spm / 60` ciclos por segundo mientras `spm > 0`; si `spm == 0` queda en 0 (catch).
- `pitch` (cabeceo del bote, radianes): `0.02 * sin(strokePhase * 2π)` más un balanceo lento `0.006 * sin(t * 0.8)`.
- `hour` (0–24, decimal): hora real del reloj, salvo `SceneSettings.hourOverride` en modo simulador.
- `puddles`: lista de charcos activos `(x, z, age)` que se crean al soltar la pala y envejecen 4 s mientras se alejan con `distance`.

## Palada (`StrokeCycle`)

Fase `p` en [0, 1). Drive más rápido que recuperación (ratio 1:2).

| Tramo | p | Qué pasa |
|---|---|---|
| Catch | 0.00 | Rodillas arriba, cuerpo adelante, brazos estirados, pala entra |
| Drive piernas | 0.00–0.18 | Piernas se extienden, carro va hacia atrás |
| Drive espalda | 0.10–0.30 | Tronco pasa de +25° (adelante) a −20° (atrás) |
| Drive brazos | 0.22–0.36 | Brazos se flexionan hasta el pecho |
| Finish | 0.36–0.40 | Pala sale del agua, se genera el charco |
| Recuperación brazos | 0.40–0.60 | Brazos se estiran |
| Recuperación tronco | 0.50–0.75 | Tronco vuelve a +25° |
| Recuperación piernas | 0.60–1.00 | Rodillas suben, carro vuelve adelante |

Exposición: `legs(p)`, `back(p)`, `arms(p)` en [0, 1] con suavizado `smoothstep` en cada tramo, `bladeInWater(p)` (true en 0.00–0.38), `oarSweep(p)`: ángulo del remo respecto de la perpendicular al bote, de −55° (catch, hacia la proa) a +35° (finish, hacia la popa) durante el drive, y vuelta durante la recuperación. `bladeFeathered(p)` = !bladeInWater.

## Hora del día (`TimeOfDay`)

A partir de `hour` devuelve una `ScenePalette`:
- `sunElevation = sin((hour - 6) / 12 * π)` (positivo entre 6 y 18). Si es ≤ −0.1 es de noche: se dibuja luna (posición simétrica) y estrellas.
- Posición en pantalla del sol/luna: `x = w * (0.25 + 0.5 * (hour - 6) / 12)` acotado a [0.15, 0.85] del ancho; `y = horizonY - sunElevation * horizonY * 0.9`.
- Paleta por keyframes (interpolación lineal entre horas): 5 (amanecer: cielo violeta-naranja, agua oscura), 7 (mañana), 12 (día: azul, agua azul-turquesa), 18 (atardecer: naranja-rosa), 20 (anochecer: azul profundo), 22 (noche: casi negro, agua azul marino) y de vuelta a 5. Campos: `skyTop`, `skyHorizon`, `waterNear`, `waterFar`, `sunColor`, `sunGlow`, `fog`, `ambient` (multiplicador para teñir orilla y bote; de noche baja a 0.35).

## Escenarios (`Environment`)

```dart
enum EnvironmentId { lake, river, coast, regatta }

abstract class Environment {
  EnvironmentId get id;
  double get waveAmplitude;          // 0.0–1.0, lo usa el shader
  double get waveScale;              // metros entre crestas
  Color tintWater(Color base);       // ajuste de color del agua por escenario
  void paintHorizon(Canvas c, Size s, SceneCamera cam, ScenePalette p); // silueta lejana
  List<ShoreProp> propsForSegment(int segmentIndex); // determinista
}

class ShoreProp {
  final double x;      // metros, negativo = orilla izquierda
  final double z;      // metros absolutos de mundo (0 = inicio)
  final PropKind kind; // pine, mountainCabin, pier, building, boathouse, bridge,
                       // laneBuoy, lamp, cliff, lighthouse, gull, beachUmbrella,
                       // grandstand, finishTower, flag, distanceMarker
  final double scale;  // 0.7–1.3
  final int seed;      // variación de forma/color
}
```

- El mundo se divide en segmentos de 50 m. `propsForSegment(k)` usa `Random(hash(id, k))`, así el paisaje es el mismo cada vez a la misma distancia y no depende del orden de dibujo.
- Las orillas están en `|x| ≥ 9` (el río tiene 18 m de ancho; en costa la orilla derecha no existe y la izquierda está en `x = −14`).
- Un `bridge` ocupa `x` de −12 a 12 a `y = 6`: se dibuja como arco sobre el agua y pasa por encima de la cámara.
- Visibles los objetos con `z` entre `distance + 1` y `distance + 400`. Se ordenan de lejos a cerca antes de pintar. Máximo 40 por frame (los más lejanos se descartan primero).

Contenido por escenario:

| | Silueta lejana | Orilla | Agua |
|---|---|---|---|
| **Lago** | Montañas con nieve, dos planos con parallax | Pinos densos (cada 6–12 m, ambas orillas), muelle cada ~400 m, cabaña cada ~600 m | Calma: `waveAmplitude 0.25`, `waveScale 2.5` |
| **Río urbano** | Skyline de edificios con ventanas iluminadas de noche | Boathouses y edificios de 3–6 pisos cada 15–30 m, faroles cada 25 m, puente de piedra cada ~800 m, boyas de carril cada 50 m | `0.35`, `2.0` |
| **Costa** | Horizonte abierto, acantilado lejano a la izquierda | Acantilados a la izquierda con faro cada ~1000 m, playa con sombrillas, gaviotas (se dibujan en el cielo y se mueven solas) | Movida: `0.8`, `4.0` |
| **Canal de regata** | Tribunas y torre de llegada lejanas, banderas | Boyas de colores cada 10 m en 3 carriles visibles, marcas de distancia cada 250 m con número, tribuna cada ~1000 m | `0.3`, `1.5` |

## Agua (`shaders/water.frag`)

Un fragment shader que pinta toda el área bajo el horizonte. Uniforms (en este orden): `uSize (vec2)`, `uHorizonY`, `uFocal`, `uCamHeight`, `uDistance`, `uTime`, `uWaveAmp`, `uWaveScale`, `uSunX`, `uSunY`, `uSunElevation`, `uWaterNear (vec3)`, `uWaterFar (vec3)`, `uSkyHorizon (vec3)`, `uSunColor (vec3)`, `uFog (vec3)`, `uWakeStrength`, `uBoatZ`.

Por píxel:
1. Si `y < uHorizonY`: transparente.
2. Inversa de cámara: `z = uFocal * uCamHeight / (y - uHorizonY)`, `x = (px - w/2) * z / uFocal`. `zw = z + uDistance` (coordenada de mundo).
3. Ondas: `h = sin(zw / uWaveScale + uTime * 0.6) * 0.6 + sin((zw * 0.7 + x * 1.3) / uWaveScale + uTime * 0.9) * 0.4`, más un ruido de valor con hash de `floor(x, zw)` para romper la regularidad. Normal aproximada con las derivadas de `h`.
4. Color base: `mix(uWaterNear, uWaterFar, smoothstep(2, 120, z))`, oscurecido/aclarado por `h * uWaveAmp`.
5. Reflejo del cielo (Fresnel): `fres = pow(1 - clamp(uCamHeight / length(vec2(z, uCamHeight)), 0, 1), 3)`; `color = mix(color, uSkyHorizon, fres * 0.6)`.
6. Brillo del sol: columna gaussiana en `|px - uSunX|` con ancho creciente con `z`, modulada por `max(0, normal.y)` elevado a 24 y por `uSunElevation` (de noche usa el color de la luna). Suma `uSunColor * glitter`.
7. Estela: para `z < uBoatZ` (entre la popa y la cámara), ancho de la V `wv = 0.3 + (uBoatZ - z) * 0.35`; `foam = smoothstep(wv, wv - 0.4, abs(x)) * (1 - smoothstep(0, uBoatZ, uBoatZ - z)) * uWakeStrength`, con ruido; `color = mix(color, vec3(1), foam * 0.5)`.
8. Niebla: `color = mix(color, uFog, smoothstep(80, 400, z))`.
9. Salida con alpha 1.

`uWakeStrength` = `clamp(speed / 4, 0, 1)`. `uBoatZ` es la `z` de la **popa** (`boatZ − 4.2`), que es donde nace la estela.

`WaterShader.load()` devuelve `Future<FragmentProgram?>`: usa `FragmentProgram.fromAsset('shaders/water.frag')`, cachea el resultado, y ante cualquier error devuelve `null` y lo registra con `debugPrint`. `WaterPainter` con programa `null` pinta el fallback: degradé `waterFar → waterNear` y 10 líneas de brillo horizontales con opacidad por `h`, sin estela. La app es usable siempre.

## Bote, remero y remos (`BoatPainter`)

Todo en coordenadas de mundo proyectadas con la cámara; el bote está centrado en `x = 0`, `z` de `boatZ − 4.2` (popa) a `boatZ + 4.0` (proa), `y = 0.08` sobre el agua, rotado por `pitch`.

- **Casco**: polígono proyectado de la popa (cerca, más ancha en pantalla) a la proa (converge al punto de fuga), con degradé claro arriba / oscuro abajo y línea de flotación. Riggers a ambos lados en `z = boatZ ± 0.3`, `x = ±0.8`. Sombra elíptica sobre el agua, desplazada según la posición del sol.
- **Remero** (de cara a la cámara: los remeros miran hacia la popa): los pies van en `z = boatZ − 1.15` (hacia la popa) y el carro en `z = boatZ − 0.6 * (1 − legs(p))`, así en el catch está cerca de los pies y en el finish hacia la proa. Muslos y pantorrillas como cápsulas que se pliegan (`legs`), tronco con inclinación `torsoLean(p)` (+ hacia la popa, es decir hacia la cámara, en el catch), hombros, brazos hasta las manos que siguen el mango del remo, cabeza con pelo. Colores: traje `#1565C0`, piel `#FFCC80`, teñidos por `ambient`. Tamaño real: tronco 0.55 m, cabeza 0.24 m.
- **Remos** (cada lado): pivote en el rigger, largo 2.9 m, ángulo `oarSweep(p)` en el plano del agua. Pala: en el agua (`bladeInWater`) se dibuja vertical, color `#00B4D8`, con un chorro de salpicadura en el catch (6 gotas blancas que caen 0.3 s). Fuera del agua, plana (`bladeFeathered`), horizontal.
- **Charcos**: `SceneState.puddles` dibujados como anillos blancos translúcidos que se agrandan (0.3 → 1.2 m) y se desvanecen en 4 s, alejándose con `distance`.

## Cielo (`SkyPainter`)

- Degradé `skyTop → skyHorizon` hasta `horizonY`.
- Sol: disco + halo radial; luna: disco con sombra; estrellas: 80 puntos con posición determinista y parpadeo suave cuando es de noche.
- Nubes: 6–8 nubes de formas redondeadas (varias elipses superpuestas con sombra inferior), con parallax `distance * 0.002` más deriva propia.
- `environment.paintHorizon(...)`: silueta lejana entre `horizonY − 0.12h` y `horizonY`, en dos planos con parallax `distance * 0.004` y `0.008`, teñida por `fog`.

## Selección de escenario

- `SceneSettings extends ChangeNotifier`: `environmentId` (persistido en `SharedPreferences` bajo `scene.environment`, por defecto `lake`), `hourOverride` (solo lectura/escritura desde el panel del simulador; no se persiste). Registrado en `main.dart` con `ChangeNotifierProvider`.
- `EnvironmentPicker`: fila horizontal de 4 tarjetas (120×80) con `ThumbnailPainter` (la escena estática a las 12:00, sin remero, con 3 objetos de orilla) y el nombre debajo; borde resaltado en la elegida. Va en `_IdleView` arriba del botón "Entrenamiento libre", con el título `l10n.workoutScene`.
- Textos nuevos en `app_en.arb` / `app_es.arb`: `workoutScene` ("Scenery" / "Escenario"), `sceneLake` ("Alpine lake" / "Lago alpino"), `sceneRiver` ("City river" / "Río urbano"), `sceneCoast` ("Coast" / "Costa"), `sceneRegatta` ("Regatta course" / "Canal de regata").
- Panel del simulador (`simulator_overlay.dart`): fila "Hora escena" con − / + de a 1 h que escribe `SceneSettings.hourOverride` (vacío = hora real). Solo existe en modo simulador.

## `SceneView`

```dart
class SceneView extends StatefulWidget {
  const SceneView({required this.environment, required this.hour, required this.data,
                   required this.isActive, required this.isPaused});
}
```
- Un `Ticker`; en cada tick actualiza `SceneState` y llama `setState` (los painters leen el estado).
- `Stack` de `CustomPaint`: `SkyPainter`, `WaterPainter`, `ShorePainter`, `BoatPainter`. Cada uno implementa `shouldRepaint` comparando sus entradas.
- En `initState` dispara `WaterShader.load()`; hasta que termina usa el fallback.
- Pausa: el ticker sigue (el agua ondula) pero `targetSpeed = 0` y la palada se congela.

## Rendimiento

- Objetivo 60 fps en teléfono de gama media. El shader es una pasada por píxel con ~30 operaciones; sin texturas.
- `ShorePainter` reutiliza `Path`s por tipo de objeto y los escala con `canvas.scale`, sin crear objetos por frame.
- Nada de `withOpacity` (deprecado): `withValues(alpha:)`.
- Sin `OrientationBuilder`: la cámara se adapta a `size` (vertical en teléfono, horizontal en escritorio/tablet).

## Fuera de alcance

- 3D real, modelos glTF, Unity.
- Modos de cámara (POV, cinemático).
- Cambiar de escenario durante el entrenamiento.
- Sonido, landmarks reales, otros remeros/fantasmas, clima.
- Tocar el HUD, los paneles de series o la pantalla vieja `_FullscreenWorkoutPage`.

## Tests

- `test/scene/scene_camera_test.dart`: un punto más lejano queda más cerca del horizonte y más chico; `z → ∞` converge a `(w/2, horizonY)`; inversa ∘ proyección es identidad.
- `test/scene/scene_state_test.dart`: `speed` desde el split (1:47 → 4,67 m/s); al pasar a `pace 0` baja a < 0,1 en 6 s; `distance` crece; `strokePhase` a 24 spm da 0,4 ciclos/s; en pausa no avanza la palada.
- `test/scene/stroke_cycle_test.dart`: en `p=0` piernas plegadas, brazos estirados, pala en el agua; en `p=0.36` piernas extendidas, brazos flexionados; `legs` empieza antes que `back` y `back` antes que `arms`; `oarSweep(0) < 0 < oarSweep(0.36)`.
- `test/scene/time_of_day_test.dart`: 12:00 es día con sol arriba; 23:00 es noche con luna y estrellas; 18:30 interpola entre atardecer y anochecer.
- `test/scene/environment_test.dart`: `propsForSegment(k)` es determinista; los objetos quedan en `|x| ≥ 9` (salvo puentes y boyas); el canal de regata tiene boyas cada 10 m; cada escenario produce al menos un objeto por segmento.
- `test/scene/scene_view_test.dart`: pinta sin excepciones en 390×844 y 844×390, con programa de shader `null` (fallback) y en los 4 escenarios.
- `test/scene/environment_picker_test.dart`: tocar una tarjeta cambia `SceneSettings` y persiste en `SharedPreferences`.
- Manual con el simulador en Windows: capturas con el preset "Fuerte" (el paisaje pasa más rápido), en los 4 escenarios y a las 6, 12, 18 y 22 h con "Hora escena".
