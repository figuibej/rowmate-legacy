import 'dart:ui';

/// Cámara de persecución: proyecta coordenadas de mundo (metros) a pantalla.
/// Mundo: x lateral (0 = eje del bote, + derecha), z hacia adelante desde la
/// cámara, y altura sobre el agua.
class SceneCamera {
  SceneCamera(this.size)
      : horizonY = size.height * (size.width > size.height ? 0.42 : 0.40),
        focal = size.shortestSide;

  /// Altura de la cámara sobre el agua (m).
  static const double camHeight = 2.2;

  /// Distancia de la cámara al remero (m). Con 9.5 la popa (4.2 m más cerca)
  /// queda visible por encima del borde inferior en horizontal.
  static const double boatZ = 9.5;

  /// Nada más cerca que esto se dibuja.
  static const double minZ = 0.5;

  final Size size;
  final double horizonY;
  final double focal;

  double get centerX => size.width / 2;

  /// Punto de mundo → pantalla. null si queda detrás de la cámara.
  Offset? project(double x, double y, double z) {
    if (z <= minZ) return null;
    return Offset(
      centerX + focal * x / z,
      horizonY + focal * (camHeight - y) / z,
    );
  }

  /// Píxeles por metro a la distancia z.
  double scaleAt(double z) => focal / z;

  /// Inversa para puntos sobre el agua (y = 0); screen.dy debe ser > horizonY.
  /// Devuelve Offset(x, z) en metros.
  Offset unprojectWater(Offset screen) {
    final z = focal * camHeight / (screen.dy - horizonY);
    final x = (screen.dx - centerX) * z / focal;
    return Offset(x, z);
  }
}
