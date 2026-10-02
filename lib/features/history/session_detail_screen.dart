import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import '../../core/database/database_service.dart';
import '../../core/models/interval_step.dart';
import '../../core/models/workout_session.dart';
import '../../core/strava/strava_config.dart';
import '../../shared/theme.dart';
import '../profile/profile_provider.dart';

class SessionDetailScreen extends StatefulWidget {
  final WorkoutSession session;
  final DatabaseService db;
  const SessionDetailScreen({super.key, required this.session, required this.db});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<DataPoint> _points = [];
  List<IntervalStep> _flatSteps = [];
  bool _loading = true;
  int _chartMetric = 0; // 0=watts, 1=spm, 2=split, 3=distance, 4=hr
  late WorkoutSession _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _load();
  }

  Future<void> _load() async {
    // Recargar session desde DB para tener el estado más actual
    final freshSession = await widget.db.getSessionById(widget.session.id!);
    final sessionToUse = freshSession ?? widget.session;

    final pts = await widget.db.getDataPointsForSession(sessionToUse.id!);
    List<IntervalStep> flatSteps = [];
    if (sessionToUse.routineId != null) {
      final routine = await widget.db.getRoutineById(sessionToUse.routineId!);
      if (routine != null) {
        flatSteps = routine.flattenedSteps;
      }
    }
    setState(() {
      _session = sessionToUse;
      _points = pts;
      _flatSteps = flatSteps;
      _loading = false;
    });
  }

  Future<void> _refreshSession() async {
    final updated = await widget.db.getSessionById(widget.session.id!);
    if (updated != null && mounted) {
      setState(() => _session = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final l10n = AppLocalizations.of(context)!;
    final metricLabels = [
      l10n.sessionChartWatts,
      l10n.sessionChartSpm,
      l10n.sessionChartSplit,
      l10n.sessionChartDistance,
      l10n.sessionChartHr,
    ];
    final stravaConfigured = StravaConfig.isConfigured;
    final ProfileProvider? profile = stravaConfigured
        ? context.watch<ProfileProvider>()
        : null;
    // Mostrar botón si Strava está configurado, conectado y la sesión no fue subida
    final showUploadButton = stravaConfigured &&
        profile != null &&
        profile.isConnected &&
        (s.stravaActivityId == null || s.stravaActivityId!.isEmpty) &&
        s.finishedAt != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.routineName ?? l10n.workoutFree),
        actions: [
          if (stravaConfigured && s.stravaActivityId != null)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.cloud_done, color: Color(0xFFFC4C02), size: 20),
            ),
          if (showUploadButton)
            IconButton(
              icon: profile.isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              tooltip: l10n.profileUploadToStrava,
              onPressed: profile.isUploading
                  ? null
                  : () async {
                      final ok = await profile.uploadSession(s.id!);
                      if (context.mounted) {
                        if (ok) _refreshSession();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? l10n.profileUploaded
                                : l10n.profileUploadFailed),
                          ),
                        );
                      }
                    },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _points.isEmpty
              ? Center(
                  child: Text(l10n.sessionNoTelemetry,
                      style: const TextStyle(color: Colors.white38)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummary(s, l10n),
                    const SizedBox(height: 20),
                    if (_hasStepData) ...[
                      _buildStepBreakdown(l10n),
                      const SizedBox(height: 20),
                    ],
                    _buildChartSelector(metricLabels),
                    const SizedBox(height: 8),
                    _buildChart(),
                  ],
                ),
    );
  }

  bool get _hasStepData => _points.any((p) => p.stepIndex != null);

  // ─── Resumen general ───────────────────────────────────────────────────

  Widget _buildSummary(WorkoutSession s, AppLocalizations l10n) {
    final stats = SessionStats.compute(_points);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sessionSummary,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatChip(label: l10n.historyStatTime, value: stats.durationFormatted),
                _StatChip(label: l10n.historyStatDistance, value: '${stats.totalDistance}m', color: MetricColors.distance),
                _StatChip(label: 'Watts', value: '${stats.p99Watts}', color: MetricColors.watts),
                _StatChip(label: 'SPM', value: stats.p99Spm.toStringAsFixed(1), color: MetricColors.spm),
                _StatChip(label: 'Split', value: stats.splitFormatted, color: MetricColors.split),
                if (stats.hasHeartRate)
                  _StatChip(
                    label: l10n.historyStatHeartRate,
                    value: '${stats.avgHeartRate}/${stats.maxHeartRate}',
                    color: MetricColors.heartRate,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Desglose por paso ────────────────────────────────────────────────

  Widget _buildStepBreakdown(AppLocalizations l10n) {
    final Map<int, List<DataPoint>> grouped = {};
    for (final p in _points) {
      if (p.stepIndex != null) {
        grouped.putIfAbsent(p.stepIndex!, () => []).add(p);
      }
    }

    if (grouped.isEmpty) return const SizedBox.shrink();

    final sortedKeys = grouped.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sessionStepBreakdown,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            ...sortedKeys.map((idx) {
              final pts = grouped[idx]!;
              return _buildStepRow(idx, pts);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(int stepIdx, List<DataPoint> pts) {
    final avgWatts = pts.map((p) => p.powerWatts).reduce((a, b) => a + b) / pts.length;
    final avgSpm = pts.map((p) => p.strokeRate).reduce((a, b) => a + b) / pts.length;
    final avgSplit = pts.map((p) => p.pace500mSeconds).reduce((a, b) => a + b) / pts.length;
    final duration = pts.length * 5; // cada punto = 5 segundos
    final dist = pts.last.distanceMeters - pts.first.distanceMeters;

    final durStr = '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}';
    final splitMin = avgSplit.round() ~/ 60;
    final splitSec = avgSplit.round() % 60;
    final splitStr = '$splitMin:${splitSec.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF00B4D8).withAlpha(40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${stepIdx + 1}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00B4D8),
                    fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$durStr  ·  ${dist}m',
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MiniStat('${avgWatts.round()}W'),
                    _MiniStat('${avgSpm.toStringAsFixed(1)} spm'),
                    _MiniStat('$splitStr/500m'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Selector de métrica para gráfico ─────────────────────────────────

  Widget _buildChartSelector(List<String> metricLabels) {
    return SegmentedButton<int>(
      segments: List.generate(
        metricLabels.length,
        (i) => ButtonSegment(value: i, label: Text(metricLabels[i], style: const TextStyle(fontSize: 11))),
      ),
      selected: {_chartMetric},
      onSelectionChanged: (v) => setState(() => _chartMetric = v.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: const Color(0xFF0077B6),
        selectedForegroundColor: Colors.white,
      ),
    );
  }

  // ─── Gráfico ──────────────────────────────────────────────────────────

  Widget _buildChart() {
    if (_points.isEmpty) return const SizedBox.shrink();

    // Para Split/Pace, necesitamos calcular el máximo para la transformación
    final maxPaceForTransform = _chartMetric == 2
        ? _points.map((p) => p.pace500mSeconds.toDouble()).reduce((a, b) => a > b ? a : b)
        : 0.0;

    final spots = _points.map((p) {
      final x = p.elapsedSeconds.toDouble();
      final y = switch (_chartMetric) {
        0 => p.powerWatts.toDouble(),
        1 => p.strokeRate,
        // Para Split: transformar para que valores bajos (pace rápido) aparezcan arriba
        2 => maxPaceForTransform - p.pace500mSeconds.toDouble(),
        3 => p.distanceMeters.toDouble(),
        4 => p.heartRate.toDouble(),
        _ => 0.0,
      };
      return FlSpot(x, y);
    }).toList();

    // Computar regiones de pasos con tipo e índice
    final stepRegions = <({double start, double end, String type, int stepIndex})>[];
    if (_hasStepData) {
      int? prevStep;
      String? prevType;
      double startX = 0;
      for (final p in _points) {
        if (p.stepIndex != null && p.stepIndex != prevStep) {
          if (prevStep != null && prevType != null) {
            stepRegions.add((start: startX, end: p.elapsedSeconds.toDouble(), type: prevType!, stepIndex: prevStep!));
          }
          startX = p.elapsedSeconds.toDouble();
          prevStep = p.stepIndex;
          prevType = p.stepType ?? 'work';
        }
      }
      if (prevStep != null && prevType != null) {
        stepRegions.add((start: startX, end: _points.last.elapsedSeconds.toDouble(), type: prevType!, stepIndex: prevStep!));
      }
    }

    final lineColor = switch (_chartMetric) {
      0 => MetricColors.watts,
      1 => MetricColors.spm,
      2 => MetricColors.split,
      3 => MetricColors.distance,
      4 => MetricColors.heartRate,
      _ => Colors.white,
    };

    final unitLabel = switch (_chartMetric) {
      0 => 'W',
      1 => 'spm',
      2 => 's',
      3 => 'm',
      4 => 'bpm',
      _ => '',
    };

    // Líneas horizontales de target por step
    final targetLines = <LineChartBarData>[];
    if (_flatSteps.isNotEmpty) {
      for (final region in stepRegions) {
        if (region.stepIndex >= _flatSteps.length) continue;
        final step = _flatSteps[region.stepIndex];

        final targetValues = <double>[];
        switch (_chartMetric) {
          case 0:
            if (step.targetWattsMin != null) targetValues.add(step.targetWattsMin!.toDouble());
            if (step.targetWattsMax != null) targetValues.add(step.targetWattsMax!.toDouble());
          case 1:
            if (step.targetSpm != null) targetValues.add(step.targetSpm!.toDouble());
          case 2:
            if (step.targetSplitSeconds != null) targetValues.add(step.targetSplitSeconds!.toDouble());
        }

        for (final targetY in targetValues) {
          final regionColor = stepColor(region.type);
          targetLines.add(LineChartBarData(
            spots: [FlSpot(region.start, targetY), FlSpot(region.end, targetY)],
            isCurved: false,
            color: Colors.white.withAlpha(200),
            barWidth: 2,
            dashArray: [8, 5],
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: regionColor.withAlpha(18),
              cutOffY: 0,
              applyCutOffY: true,
            ),
          ));
        }
      }
    }

    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    for (final tl in targetLines) {
      for (final s in tl.spots) {
        if (s.y > maxY) maxY = s.y;
        if (s.y < minY) minY = s.y;
      }
    }

    // Para todas las métricas: eje Y normal (0 abajo, max arriba)
    // Para Split, los datos ya están transformados para que pace rápido = valor alto (arriba)
    final chartMinY = 0.0;
    final chartMaxY = maxY * 1.1 > 0 ? maxY * 1.1 : 100.0;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          maxY: chartMaxY,
          minY: chartMinY,
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: stepRegions
                .map((r) => VerticalRangeAnnotation(
                      x1: r.start,
                      x2: r.end,
                      color: stepColor(r.type).withAlpha(25),
                    ))
                .toList(),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white10,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: _xInterval,
                getTitlesWidget: (value, meta) {
                  final m = value ~/ 60;
                  final s = (value % 60).toInt();
                  return Text('$m:${s.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 9, color: Colors.white38));
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  // Para Split (métrica 2): transformar de vuelta y formatear como MM:SS
                  if (_chartMetric == 2) {
                    // Valor transformado → Pace real
                    final realPace = (maxPaceForTransform - value).toInt();
                    final mins = realPace ~/ 60;
                    final secs = realPace % 60;
                    return Text(
                      '$mins:${secs.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 9, color: Colors.white38),
                    );
                  }
                  // Para otras métricas: número entero
                  return Text(
                    '${value.toInt()}',
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withAlpha(30),
              ),
            ),
            ...targetLines,
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: stepRegions
                .skip(1) // no mostrar línea al inicio
                .map((r) => VerticalLine(
                      x: r.start,
                      color: Colors.white24,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ))
                .toList(),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) {
                    String yValue;
                    // Para Split (métrica 2): transformar de vuelta y formatear como MM:SS
                    if (_chartMetric == 2) {
                      final realPace = (maxPaceForTransform - s.y).toInt();
                      final mins = realPace ~/ 60;
                      final secs = realPace % 60;
                      yValue = '$mins:${secs.toString().padLeft(2, '0')}';
                    } else {
                      yValue = s.y.toStringAsFixed(1);
                    }
                    return LineTooltipItem(
                      '$yValue $unitLabel',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    );
                  })
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  double get _xInterval {
    if (_points.isEmpty) return 60;
    final total = _points.last.elapsedSeconds;
    if (total < 300) return 30;
    if (total < 600) return 60;
    if (total < 1800) return 120;
    return 300;
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          // Seis columnas en 360 dp: "137/150" o "12345m" no entran a 14 px.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color ?? Colors.white)),
          ),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String text;
  const _MiniStat(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white)),
    );
  }
}
