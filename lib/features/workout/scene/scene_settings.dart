import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'environment.dart';

/// Escenario elegido (persistido) y hora forzada para el modo simulador.
class SceneSettings extends ChangeNotifier {
  SceneSettings() {
    _load();
  }

  static const prefKey = 'scene.environment';

  EnvironmentId _environmentId = EnvironmentId.lake;
  double? _hourOverride;
  bool _touched = false; // si el usuario eligió antes de que termine _load, gana él

  EnvironmentId get environmentId => _environmentId;

  /// Solo en modo simulador: hora de la escena en lugar de la real.
  double? get hourOverride => _hourOverride;
  set hourOverride(double? h) {
    _hourOverride = h;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = EnvironmentId.values.asNameMap()[prefs.getString(prefKey)];
    if (!_touched && id != null && id != _environmentId) {
      _environmentId = id;
      notifyListeners();
    }
  }

  Future<void> setEnvironment(EnvironmentId id) async {
    _touched = true;
    if (id == _environmentId) return;
    _environmentId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, id.name);
  }
}
