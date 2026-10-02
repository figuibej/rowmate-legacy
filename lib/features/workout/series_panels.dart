import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/theme.dart';
import 'series_tracker.dart';

/// m:ss.d — tiempo de una vuelta.
String formatLapTime(double seconds) {
  final tenths = (seconds * 10).round();
  final m = tenths ~/ 600;
  final s = (tenths % 600) / 10;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

/// m:ss — split redondeado al segundo.
String formatSplit(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// "1.245 m"
String formatMeters(int meters) =>
    '${NumberFormat('#,##0', 'es').format(meters)} m';

// Mismo lenguaje visual que _GlassMetricCard (SPM / Split / Watts):
// fondo negro 55 %, radio 14, etiqueta de color con tracking, valores w800.
BoxDecoration _glass() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    );

TextStyle _labelStyle(Color color) => TextStyle(
      color: color.withValues(alpha: 0.8),
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );

TextStyle _valueStyle(Color color, double size) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle _unitStyle(Color color) => TextStyle(
      color: color.withValues(alpha: 0.55),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

const _mutedStyle = TextStyle(color: Colors.white54, fontSize: 15);

/// Hora actual (HH:mm). Tiene su propio timer: sigue andando en pausa.
/// [framed] = false para usarla dentro de una barra que ya tiene fondo.
class WallClock extends StatefulWidget {
  const WallClock({super.key, this.framed = true});

  final bool framed;

  @override
  State<WallClock> createState() => _WallClockState();
}

class _WallClockState extends State<WallClock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      // Solo redibujar cuando cambia el minuto mostrado
      if (now.minute != _now.minute || now.hour != _now.hour) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule, size: 16, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          DateFormat('HH:mm').format(_now),
          // Mismo tamaño que la cuenta regresiva de la barra de etapas
          style: _valueStyle(Colors.white, 18),
        ),
      ],
    );
    if (!widget.framed) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: _glass(),
      child: content,
    );
  }
}

/// Paneles colapsables de parciales de 500 m y repeticiones anteriores.
/// Colapsados por defecto; el estado se recuerda entre sesiones.
class SeriesPanels extends StatefulWidget {
  const SeriesPanels({super.key, required this.tracker});

  final SeriesTracker tracker;

  static const lapsKey = 'immersive.lapsExpanded';
  static const repsKey = 'immersive.repsExpanded';

  @override
  State<SeriesPanels> createState() => _SeriesPanelsState();
}

class _SeriesPanelsState extends State<SeriesPanels> {
  bool _lapsExpanded = false;
  bool _repsExpanded = false;
  // Si el usuario tocó antes de que termine _load, su elección gana
  bool _lapsTouched = false;
  bool _repsTouched = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      if (!_lapsTouched) {
        _lapsExpanded = prefs.getBool(SeriesPanels.lapsKey) ?? false;
      }
      if (!_repsTouched) {
        _repsExpanded = prefs.getBool(SeriesPanels.repsKey) ?? false;
      }
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tracker;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsiblePanel(
          icon: Icons.timer_outlined,
          color: MetricColors.split,
          collapsedLabel: '500 m',
          title: 'Parciales 500 m',
          expanded: _lapsExpanded,
          onToggle: () {
            _lapsTouched = true;
            setState(() => _lapsExpanded = !_lapsExpanded);
            _save(SeriesPanels.lapsKey, _lapsExpanded);
          },
          child: _LapsContent(tracker: t),
        ),
        if (t.inSeries) ...[
          const SizedBox(height: 8),
          _CollapsiblePanel(
            icon: Icons.history,
            color: MetricColors.distance,
            collapsedLabel: 'Reps',
            title: 'Series anteriores',
            expanded: _repsExpanded,
            onToggle: () {
              _repsTouched = true;
              setState(() => _repsExpanded = !_repsExpanded);
              _save(SeriesPanels.repsKey, _repsExpanded);
            },
            child: _RepsContent(tracker: t),
          ),
        ],
      ],
    );
  }
}

class _CollapsiblePanel extends StatelessWidget {
  const _CollapsiblePanel({
    required this.icon,
    required this.color,
    required this.collapsedLabel,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String collapsedLabel;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Mismo ancho mínimo que la tarjeta grande de SPM que está encima
        constraints: const BoxConstraints(minWidth: 130),
        // 200: no invade la columna Split/Watts en teléfonos de 360 dp
        width: expanded ? 200 : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: _glass(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colapsado vive en una columna sin ancho acotado: sin Flexible ahí
            if (expanded)
              Row(
                children: [
                  Icon(icon, size: 14, color: color.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(color)),
                  ),
                  const Icon(Icons.expand_less, size: 18, color: Colors.white54),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  Text(collapsedLabel, style: _labelStyle(color)),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, size: 18, color: Colors.white54),
                ],
              ),
            if (expanded) ...[
              const SizedBox(height: 6),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _LapsContent extends StatelessWidget {
  const _LapsContent({required this.tracker});

  final SeriesTracker tracker;

  @override
  Widget build(BuildContext context) {
    final t = tracker;
    final laps = t.laps;
    // Las más recientes primero, para leerlas de un vistazo
    final shown =
        (laps.length > 4 ? laps.sublist(laps.length - 4) : laps).reversed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!t.isWorkStep)
          const Text('Sin parciales en este paso', style: _mutedStyle)
        else ...[
          // Vuelta en curso: valor grande, como las tarjetas de métricas
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(formatLapTime(t.currentLapSeconds),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _valueStyle(MetricColors.split, 30)),
              ),
              const SizedBox(width: 6),
              Text('${t.currentLapMeters} m',
                  style: _unitStyle(MetricColors.split)),
            ],
          ),
          const SizedBox(height: 4),
          for (final lap in shown)
            _MetricRow(
              label: '#${lap.number}',
              value: formatLapTime(lap.seconds),
              valueColor: MetricColors.split,
            ),
        ],
        if (t.inSeries) ...[
          const SizedBox(height: 6),
          Text('Rep ${t.rep}/${t.repCount} · ${formatMeters(t.repMeters)}',
              style: _valueStyle(MetricColors.distance, 16)),
        ],
      ],
    );
  }
}

class _RepsContent extends StatelessWidget {
  const _RepsContent({required this.tracker});

  final SeriesTracker tracker;

  @override
  Widget build(BuildContext context) {
    final reps = tracker.previousReps;
    if (reps.isEmpty) {
      return const Text('Sin repeticiones completas', style: _mutedStyle);
    }
    return Column(
      children: [
        for (final r in reps)
          _MetricRow(
            label: 'Rep ${r.rep}',
            value: r.workSplitSeconds == null
                ? '—'
                : formatSplit(r.workSplitSeconds!),
            valueColor: MetricColors.split,
            trailing: formatMeters(r.totalMeters),
          ),
      ],
    );
  }
}

/// Fila "etiqueta · valor grande · (dato secundario)" con el estilo de las tarjetas.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 52,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _valueStyle(valueColor, 22)),
          ),
          if (trailing != null)
            Text(trailing!, style: _valueStyle(MetricColors.distance, 16)),
        ],
      ),
    );
  }
}
