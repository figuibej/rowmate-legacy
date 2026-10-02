import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flutter/scheduler.dart';
import '../../../core/models/rowing_data.dart';
import 'environment.dart';
import 'painters/boat_painter.dart';
import 'painters/shore_painter.dart';
import 'painters/sky_painter.dart';
import 'painters/water_painter.dart';
import 'scene_camera.dart';
import 'scene_state.dart';
import 'time_of_day.dart';
import 'water_shader.dart';

/// Escena 2.5D completa (cielo, agua, orilla, bote) animada con un solo Ticker.
class SceneView extends StatefulWidget {
  const SceneView({
    super.key,
    required this.environment,
    required this.data,
    required this.isActive,
    this.hourOverride,
  });

  final Environment environment;
  final RowingData data;

  /// true solo con el entrenamiento en marcha (ni en pausa ni terminado).
  final bool isActive;

  /// Hora de la escena en lugar de la real (modo simulador).
  final double? hourOverride;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final SceneState _state = SceneState();
  Duration _last = Duration.zero;

  // El FragmentShader es de este State: se crea cuando llega el programa y se
  // libera en dispose (un shader por escena montada, no uno global).
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    final program = WaterShader.program;
    if (program != null) {
      _shader = program.fragmentShader();
    } else {
      WaterShader.load().then((p) {
        if (mounted && p != null) setState(() => _shader = p.fragmentShader());
      });
    }
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    // dt acotado: tras una pausa del sistema no saltar la escena
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _state.update(
      dt: dt,
      pace500m: widget.data.pace500mSeconds.toDouble(),
      spm: widget.data.strokeRate,
      isActive: widget.isActive,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  double get _hour {
    final o = widget.hourOverride;
    if (o != null) return o;
    final n = DateTime.now();
    return n.hour + n.minute / 60;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final cam = SceneCamera(size);
      final hour = _hour;
      final palette = TimeOfDay.paletteFor(hour);
      final light = TimeOfDay.lightFor(hour, cam);
      final env = widget.environment;
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: SkyPainter(
              camera: cam, palette: palette, light: light, hour: hour,
              environment: env, distance: _state.distance, time: _state.time,
            ),
          ),
          CustomPaint(
            painter: WaterPainter(
              shader: _shader, camera: cam, state: _state,
              palette: palette, light: light, environment: env,
            ),
          ),
          CustomPaint(
            painter: ShorePainter(
              camera: cam, props: env.visibleProps(_state.distance),
              distance: _state.distance, palette: palette, time: _state.time,
            ),
          ),
          CustomPaint(
            painter: BoatPainter(camera: cam, state: _state, palette: palette, light: light),
          ),
        ],
      );
    });
  }
}
