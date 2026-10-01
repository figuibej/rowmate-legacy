import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

BoxDecoration _glass() => BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    );

const _textStyle = TextStyle(
  color: Colors.white,
  fontSize: 13,
  fontFeatures: [FontFeature.tabularFigures()],
);
const _mutedStyle = TextStyle(color: Colors.white54, fontSize: 12);

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
        const Icon(Icons.schedule, size: 14, color: Colors.white70),
        const SizedBox(width: 5),
        Text(
          DateFormat('HH:mm').format(_now),
          style: _textStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
    if (!widget.framed) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    required this.collapsedLabel,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
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
        width: expanded ? 180 : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: _glass(),
        child: expanded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(title,
                            style: _textStyle.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      const Icon(Icons.expand_less, size: 16, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text(collapsedLabel, style: _textStyle),
                ],
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.left, this.right, {this.dim = false});

  final String left;
  final String right;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final style = dim ? _textStyle.copyWith(color: Colors.white60) : _textStyle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
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
    final shown = laps.length > 4 ? laps.sublist(laps.length - 4) : laps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!t.isWorkStep)
          const Text('Sin parciales en este paso', style: _mutedStyle)
        else ...[
          for (final lap in shown)
            _Row('#${lap.number}', formatLapTime(lap.seconds)),
          _Row('▸ ${t.currentLapMeters} m', formatLapTime(t.currentLapSeconds),
              dim: true),
        ],
        if (t.inSeries) ...[
          const SizedBox(height: 4),
          Text('Rep ${t.rep}/${t.repCount} · ${formatMeters(t.repMeters)}',
              style: _mutedStyle),
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
          _Row(
            'Rep ${r.rep}',
            '${r.workSplitSeconds == null ? '—' : formatSplit(r.workSplitSeconds!)}'
                ' · ${formatMeters(r.totalMeters)}',
          ),
      ],
    );
  }
}
