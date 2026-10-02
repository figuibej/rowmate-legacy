import 'package:flutter/material.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/database_service.dart';
import '../../core/models/workout_session.dart';
import '../../core/strava/strava_config.dart';
import '../../shared/theme.dart';
import 'history_provider.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<HistoryProvider>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: p.loading
          ? const Center(child: CircularProgressIndicator())
          : p.sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history, size: 56, color: Colors.white12),
                      const SizedBox(height: 12),
                      Text(l10n.historyEmpty,
                          style: const TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: p.sessions.length,
                  itemBuilder: (context, i) {
                    final session = p.sessions[i];
                    final stats = p.statsFor(session.id);
                    return _SessionCard(
                      session,
                      stats: stats,
                      onTap: () async {
                        final db = context.read<DatabaseService>();
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => SessionDetailScreen(
                            session: session,
                            db: db,
                          ),
                        ));
                        // Recargar las sesiones cuando vuelves (por si se subió a Strava)
                        if (context.mounted) {
                          context.read<HistoryProvider>().load();
                        }
                      },
                    );
                  },
                ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final WorkoutSession s;
  final SessionStats stats;
  final VoidCallback? onTap;
  const _SessionCard(this.s, {required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat('dd/MM/yyyy  HH:mm').format(s.startedAt);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rowing, size: 18, color: Color(0xFF00B4D8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.routineName ?? l10n.historyFree,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  if (StravaConfig.isConfigured && s.stravaActivityId != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.cloud_done, size: 14, color: Color(0xFFFC4C02)),
                    ),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: l10n.historyStatTime, value: stats.durationFormatted),
                  _Stat(label: l10n.historyStatDistance, value: '${stats.totalDistance}m', color: MetricColors.distance),
                  _Stat(label: 'Watts', value: '${stats.p99Watts}', color: MetricColors.watts),
                  _Stat(label: 'SPM', value: stats.p99Spm.toStringAsFixed(1), color: MetricColors.spm),
                  _Stat(label: 'Split', value: stats.splitFormatted, color: MetricColors.split),
                  if (stats.hasHeartRate)
                    _Stat(
                      label: l10n.historyStatHeartRate,
                      value: '${stats.avgHeartRate}/${stats.maxHeartRate}',
                      color: MetricColors.heartRate,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

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
