import 'dart:ui';
import 'package:flutter/foundation.dart';

/// Carga y cachea el programa del shader de agua. Si falla (GPU sin soporte,
/// asset ausente), devuelve null y la escena usa el fallback pintado.
class WaterShader {
  WaterShader._();

  static Future<FragmentProgram?>? _loading;
  static FragmentProgram? program;

  static Future<FragmentProgram?> load() {
    return _loading ??= () async {
      try {
        program = await FragmentProgram.fromAsset('shaders/water.frag');
        return program;
      } catch (e) {
        debugPrint('[Scene] Shader de agua no disponible, usando fallback: $e');
        return null;
      }
    }();
  }
}
