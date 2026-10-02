// lib/core/bluetooth/reconnect_loop.dart
import 'dart:async';

/// Reintenta [attempt] hasta que devuelva true, se agoten [maxAttempts]
/// (null = sin límite) o se llame a [cancel]. El primer intento es inmediato
/// al llamar a [start]; los siguientes esperan [interval] tras cada fallo.
/// Una excepción en [attempt] cuenta como fallo.
class ReconnectLoop {
  ReconnectLoop({
    required this.interval,
    required this.attempt,
    this.maxAttempts,
    this.onGiveUp,
  });

  final Duration interval;
  final Future<bool> Function() attempt;
  final int? maxAttempts;
  final void Function()? onGiveUp;

  Timer? _timer;
  int _attempts = 0;
  bool _running = false;

  /// Generación de la corrida actual. Un intento en vuelo de una corrida
  /// anterior (cancelada o reiniciada con [start]) descarta su resultado.
  int _generation = 0;

  bool get isRunning => _running;
  int get attempts => _attempts;

  /// Arranca (o reinicia desde cero) la cadencia. El primer intento es inmediato.
  void start() {
    cancel();
    _running = true;
    _attempts = 0;
    _tryOnce(_generation);
  }

  /// Frena los reintentos. Un intento en vuelo no se aborta, pero su
  /// resultado se descarta.
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _tryOnce(int generation) async {
    if (!_running || generation != _generation) return;
    _attempts++;
    var ok = false;
    try {
      ok = await attempt();
    } catch (_) {
      ok = false;
    }
    if (generation != _generation || !_running) return; // corrida vieja o cancelada
    if (ok) {
      _running = false;
      return;
    }
    final max = maxAttempts;
    if (max != null && _attempts >= max) {
      _running = false;
      onGiveUp?.call();
      return;
    }
    _timer = Timer(interval, () => _tryOnce(generation));
  }
}

/// Llama a [onStale] si pasan [timeout] sin un [touch]. Cada [touch] rearma
/// el plazo; [stop] lo desactiva.
class StaleWatchdog {
  StaleWatchdog({required this.timeout, required this.onStale});

  final Duration timeout;
  final void Function() onStale;
  Timer? _timer;

  void touch() {
    _timer?.cancel();
    _timer = Timer(timeout, onStale);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
