/// Modo desarrollo con remo simulado:
///   flutter run -d windows --dart-define=SIMULATOR=true
/// Constante de compilación: sin el flag, el código del simulador
/// queda fuera del build por tree-shaking.
const bool kSimulator = bool.fromEnvironment('SIMULATOR');
