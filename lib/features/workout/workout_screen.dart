import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../core/models/interval_step.dart';
import '../../core/models/routine.dart';
import '../../core/models/rowing_data.dart';
import '../../core/strava/strava_config.dart';
import '../../shared/theme.dart';
import '../device/device_provider.dart';
import '../profile/profile_provider.dart';
import '../routines/routines_provider.dart';
import 'workout_provider.dart';
import 'immersive_workout_screen.dart';

class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkoutProvider>(
      builder: (context, w, _) {
        // Solo mostrar IdleView si está realmente idle, no si está finished
        // (finished se maneja en la pantalla fullscreen)
        if (w.isIdle) {
          return _IdleView();
        }
        return _ActiveView();
      },
    );
  }
}

// ─── Vista en reposo: elegir rutina o libre ───────────────────────────────

class _IdleView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceProvider>();
    final routines = context.watch<RoutinesProvider>().routines;
    final workout = context.read<WorkoutProvider>();
    final l10n = AppLocalizations.of(context)!;
    final connected = device.isConnected;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workoutTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!connected)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.workoutRowerNotConnected,
                          style: const TextStyle(color: Colors.orange, fontSize: 13)),
                    ),
                  ],
                ),
              ),

            FilledButton.icon(
              onPressed: connected
                  ? () {
                      workout.startFree();
                      _openFullscreen(context);
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.workoutFree),
            ),

            const SizedBox(height: 24),

            if (routines.isNotEmpty) ...[
              Text(l10n.workoutOrPickRoutine,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: routines.length,
                  itemBuilder: (context, i) {
                    final r = routines[i];
                    return Opacity(
                      opacity: connected ? 1.0 : 0.5,
                      child: Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.fitness_center,
                              color: Color(0xFF00B4D8)),
                          title: Text(r.name),
                          subtitle: Text(r.summary,
                              style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: connected
                              ? () => _confirmStart(context, r, workout)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            if (routines.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    l10n.workoutNoRoutines,
                    style: const TextStyle(color: Colors.white38),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmStart(
      BuildContext context, Routine r, WorkoutProvider workout) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r.name),
        content: Text(l10n.workoutStartContent(r.summary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.workoutStart)),
        ],
      ),
    );
    if (ok == true) {
      workout.startWithRoutine(r);
      if (context.mounted) _openFullscreen(context);
    }
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ImmersiveWorkoutPage(),
      ),
    );
  }
}

// ─── Vista activa (fallback si vuelve sin fullscreen) ─────────────────────

class _ActiveView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // La pantalla fullscreen ya está abierta por encima (pushed desde _IdleView).
    // Este widget queda debajo en el IndexedStack y no debe hacer nada.
    return const Scaffold(
      body: Center(
        child: _WorkoutInProgressPlaceholder(),
      ),
    );
  }
}

class _WorkoutInProgressPlaceholder extends StatelessWidget {
  const _WorkoutInProgressPlaceholder();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.workoutInProgress,
        style: const TextStyle(color: Colors.white38));
  }
}

// ─── Pantalla fullscreen de entrenamiento ──────────────────────────────────

class _FullscreenWorkoutPage extends StatefulWidget {
  const _FullscreenWorkoutPage();

  @override
  State<_FullscreenWorkoutPage> createState() => _FullscreenWorkoutPageState();
}

class _FullscreenWorkoutPageState extends State<_FullscreenWorkoutPage> {
  bool _hasShownCompletionDialog = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkoutProvider>();
    final sp = w.stepProgress;
    final currentStep = sp?.step;

    // Si el workout terminó, mostrar diálogo de completado (solo una vez)
    if (w.phase == WorkoutPhase.finished && !_hasShownCompletionDialog) {
      _hasShownCompletionDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showWorkoutCompletedDialog(context, w);
        }
      });
    }

    // Si está idle (después de reset), volver atrás y resetear flag
    if (w.isIdle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          _hasShownCompletionDialog = false;
          Navigator.of(context).pop();
        }
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFinish(context, w);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: SafeArea(
          child: OrientationBuilder(
            builder: (context, orientation) {
              return Column(
                children: [
                  // Top bar: título + terminar
                  _CompactTopBar(w: w),
                  // Banner del paso actual
                  if (sp != null) _CompactStepBanner(sp: sp),
                  // Métricas ocupando todo el espacio
                  Expanded(
                    child: _FullscreenMetrics(
                      data: w.data,
                      elapsedSeconds: w.totalElapsedSeconds,
                      currentStep: currentStep,
                      orientation: orientation,
                    ),
                  ),
                  // Controles
                  _CompactControls(w: w),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmFinish(BuildContext context, WorkoutProvider w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Terminar entrenamiento'),
        content: const Text('Se guardará la sesión. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Terminar')),
        ],
      ),
    );
    if (ok == true) {
      await w.finish();
      if (context.mounted && StravaConfig.isConfigured) {
        _triggerStravaUpload(context, w);
      }
      w.reset();
    }
  }

  void _showWorkoutCompletedDialog(BuildContext context, WorkoutProvider w) async {
    final l10n = AppLocalizations.of(context)!;
    final profile = StravaConfig.isConfigured ? context.read<ProfileProvider>() : null;
    final shouldAskStrava = StravaConfig.isConfigured &&
                           profile != null &&
                           profile.isConnected &&
                           profile.uploadPreference == UploadPreference.ask;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF06D6A0), size: 28),
              const SizedBox(width: 12),
              Text(l10n.workoutCompleted ?? '¡Entrenamiento completado!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.workoutCompletedMessage ?? 'Has completado tu rutina exitosamente.'),
              const SizedBox(height: 16),
              _buildCompletionStats(w),
            ],
          ),
          actions: [
            if (shouldAskStrava) ...[
              // Modo "ask": dos botones (con y sin Strava)
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  w.reset();
                },
                child: Text(l10n.workoutFinish ?? 'Finalizar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final sessionId = w.lastFinishedSessionId;
                  if (sessionId != null) {
                    profile!.uploadSession(sessionId).then((ok) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ok ? l10n.profileUploaded : l10n.profileUploadFailed)),
                        );
                      }
                    });
                  }
                  w.reset();
                },
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: Text(l10n.profileUploadToStrava),
              ),
            ] else ...[
              // Modo "auto" o "manual": un solo botón
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Subir automáticamente si está configurado y es modo auto
                  if (StravaConfig.isConfigured &&
                      profile != null &&
                      profile.isConnected &&
                      profile.uploadPreference == UploadPreference.auto) {
                    final sessionId = w.lastFinishedSessionId;
                    if (sessionId != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.profileUploadingToStrava)),
                      );
                      profile.uploadSession(sessionId).then((ok) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? l10n.profileUploaded : l10n.profileUploadFailed)),
                          );
                        }
                      });
                    }
                  }
                  w.reset();
                },
                child: Text(l10n.workoutFinish ?? 'Finalizar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionStats(WorkoutProvider w) {
    final duration = w.totalElapsedSeconds;
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    final timeStr = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _CompletionStat(
            icon: Icons.timer,
            label: 'Tiempo',
            value: timeStr,
          ),
          const SizedBox(height: 8),
          _CompletionStat(
            icon: Icons.straighten,
            label: 'Distancia',
            value: '${w.data.distanceMeters} m',
          ),
          const SizedBox(height: 8),
          _CompletionStat(
            icon: Icons.local_fire_department,
            label: 'Calorías',
            value: '${w.data.totalCalories}',
          ),
        ],
      ),
    );
  }

  void _triggerStravaUpload(BuildContext context, WorkoutProvider w) {
    final profile = context.read<ProfileProvider>();
    final sessionId = w.lastFinishedSessionId;
    if (!profile.isConnected || sessionId == null) return;

    final l10n = AppLocalizations.of(context)!;

    switch (profile.uploadPreference) {
      case UploadPreference.auto:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileUploadingToStrava)),
        );
        profile.uploadSession(sessionId).then((ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? l10n.profileUploaded : l10n.profileUploadFailed)),
            );
          }
        });
      case UploadPreference.ask:
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.profileUploadToStrava),
            content: Text(l10n.profileAskUploadDialog),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel)),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    profile.uploadSession(sessionId);
                  },
                  child: Text(l10n.profileUploadToStrava)),
            ],
          ),
        );
      case UploadPreference.manual:
        break;
    }
  }
}

// ─── Top bar compacta ─────────────────────────────────────────────────────

class _CompactTopBar extends StatelessWidget {
  final WorkoutProvider w;
  const _CompactTopBar({required this.w});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.rowing, color: Color(0xFF00B4D8), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              w.routine?.name ?? l10n.metricFreeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _confirmFinish(context, w),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: Text(l10n.workoutFinish, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _confirmFinish(BuildContext context, WorkoutProvider w) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.workoutFinishTitle),
        content: Text(l10n.workoutFinishContent),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.workoutFinish)),
        ],
      ),
    );
    if (ok == true) {
      await w.finish();
      if (context.mounted && StravaConfig.isConfigured) {
        _triggerStravaUpload(context, w, l10n);
      }
      w.reset();
    }
  }

  void _triggerStravaUpload(BuildContext context, WorkoutProvider w, AppLocalizations l10n) {
    final profile = context.read<ProfileProvider>();
    final sessionId = w.lastFinishedSessionId;
    if (!profile.isConnected || sessionId == null) return;

    switch (profile.uploadPreference) {
      case UploadPreference.auto:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileUploadingToStrava)),
        );
        profile.uploadSession(sessionId).then((ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? l10n.profileUploaded : l10n.profileUploadFailed)),
            );
          }
        });
      case UploadPreference.ask:
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.profileUploadToStrava),
            content: Text(l10n.profileAskUploadDialog),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel)),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    profile.uploadSession(sessionId);
                  },
                  child: Text(l10n.profileUploadToStrava)),
            ],
          ),
        );
      case UploadPreference.manual:
        break;
    }
  }
}

// ─── Banner del paso actual (compacto) ────────────────────────────────────

class _CompactStepBanner extends StatefulWidget {
  final StepProgress sp;
  const _CompactStepBanner({required this.sp});

  @override
  State<_CompactStepBanner> createState() => _CompactStepBannerState();
}

class _CompactStepBannerState extends State<_CompactStepBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.sp;
    final color = stepColor(sp.step.type.name);
    final remaining = sp.remainingInStep;
    final remainStr = remaining >= 0
        ? '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
        : '${sp.step.distanceMeters}m';
    final isEndingSoon = sp.isEndingSoon;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseOpacity = isEndingSoon
            ? 0.15 + (_pulseController.value * 0.25)
            : 0.15;

        return Container(
          color: color.withOpacity(pulseOpacity),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: isEndingSoon
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${stepTypeLocalized(sp.step.type, AppLocalizations.of(context)!)}${sp.step.targetLabel.isNotEmpty ? ' · ${sp.step.targetLabel}' : ''}',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(remainStr,
                  style: TextStyle(
                      color: isEndingSoon ? Colors.white : color,
                      fontWeight: FontWeight.bold,
                      fontSize: isEndingSoon ? 22 : 20)),
              const SizedBox(width: 8),
              Text('${sp.stepIndex + 1}/${sp.totalSteps}',
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
              // Barra de progreso mini
              if (sp.progress > 0) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 45,
                  child: LinearProgressIndicator(
                    value: sp.progress,
                    backgroundColor: Colors.white12,
                    color: color,
                    minHeight: 4,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Grid de métricas fullscreen ──────────────────────────────────────────

class _FullscreenMetrics extends StatelessWidget {
  final RowingData data;
  final int elapsedSeconds;
  final IntervalStep? currentStep;
  final Orientation orientation;

  const _FullscreenMetrics({
    required this.data,
    required this.elapsedSeconds,
    required this.currentStep,
    required this.orientation,
  });

  String get _elapsedFormatted {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Determina el color de una métrica según si cumple el objetivo
  Color _metricColor({
    required double? currentValue,
    required double? targetMin,
    bool invertComparison = false,
  }) {
    if (currentValue == null || targetMin == null) return Colors.white;
    // invertComparison = true para split (mayor = peor)
    if (invertComparison) {
      return currentValue > targetMin ? const Color(0xFFFF4444) : Colors.white;
    }
    return currentValue < targetMin ? const Color(0xFFFF4444) : Colors.white;
  }

  Color get _wattsColor => _metricColor(
        currentValue: data.powerWatts.toDouble(),
        targetMin: currentStep?.targetWattsMin?.toDouble(),
      );

  Color get _spmColor => _metricColor(
        currentValue: data.strokeRate,
        targetMin: currentStep?.targetSpm?.toDouble(),
      );

  Color get _splitColor => _metricColor(
        currentValue: data.pace500mSeconds.toDouble(),
        targetMin: currentStep?.targetSplitSeconds?.toDouble(),
        invertComparison: true,  // mayor = más lento = peor
      );

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = orientation == Orientation.landscape ? 4 : 2;
    final l10n = AppLocalizations.of(context)!;

    // Construimos la lista de métricas con flag de si tiene objetivo activo
    final hasWattsTarget = currentStep?.targetWattsMin != null;
    final hasSpmTarget = currentStep?.targetSpm != null;
    final hasSplitTarget = currentStep?.targetSplitSeconds != null;

    final all = <({Widget widget, bool hasTarget})>[
      (widget: _FullMetric(label: l10n.metricTime, value: _elapsedFormatted, color: MetricColors.time), hasTarget: false),
      (widget: _FullMetric(label: l10n.metricSplit, value: data.pace500mFormatted, color: hasSplitTarget ? _splitColor : MetricColors.split), hasTarget: hasSplitTarget),
      (widget: _FullMetric(label: l10n.metricDistance, value: '${data.distanceMeters}', unit: 'm', color: MetricColors.distance), hasTarget: false),
      (widget: _FullMetric(label: l10n.metricWatts, value: '${data.powerWatts}', unit: 'W', color: hasWattsTarget ? _wattsColor : MetricColors.watts), hasTarget: hasWattsTarget),
      (widget: _FullMetric(label: l10n.metricSpm, value: data.strokeRate.toStringAsFixed(1), color: hasSpmTarget ? _spmColor : MetricColors.spm), hasTarget: hasSpmTarget),
      (widget: _FullMetric(label: l10n.metricCalories, value: '${data.totalCalories}', unit: 'kcal', color: MetricColors.calories), hasTarget: false),
      if (data.heartRate > 0)
        (widget: _FullMetric(label: l10n.metricHeartRate, value: '${data.heartRate}', unit: 'bpm', color: MetricColors.heartRate), hasTarget: false),
    ];

    final targeted = all.where((m) => m.hasTarget).map((m) => m.widget).toList();
    final rest = all.where((m) => !m.hasTarget).map((m) => m.widget).toList();

    // Si no hay objetivos, mostrar todo en el grid normal
    if (targeted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: orientation == Orientation.landscape ? 1.8 : 1.3,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          children: all.map((m) => m.widget).toList(),
        ),
      );
    }

    // Con objetivos: fila de objetivos arriba + grid del resto abajo
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        children: [
          // Fila de indicadores con objetivo
          SizedBox(
            height: orientation == Orientation.landscape ? 70 : 80,
            child: Row(
              children: targeted
                  .map((w) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: w,
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Grid del resto
          Expanded(
            child: GridView.count(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: orientation == Orientation.landscape ? 1.8 : 1.3,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: rest,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Métrica individual fullscreen ────────────────────────────────────────

class _FullMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color color;

  const _FullMetric({
    required this.label,
    required this.value,
    this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final labelSize = (h * 0.12).clamp(10.0, 16.0);
        final valueSize = (h * 0.45).clamp(28.0, 72.0);
        final unitSize = (h * 0.16).clamp(12.0, 22.0);

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2E45),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              top: BorderSide(color: color.withOpacity(0.6), width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: labelSize,
                      color: color.withOpacity(0.7),
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value,
                          style: TextStyle(
                              fontSize: valueSize,
                              fontWeight: FontWeight.w800,
                              color: color,
                              height: 1)),
                      if (unit != null)
                        Text(' $unit',
                            style: TextStyle(
                                fontSize: unitSize, color: Colors.white38)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Controles compactos ──────────────────────────────────────────────────

class _CompactControls extends StatelessWidget {
  final WorkoutProvider w;
  const _CompactControls({required this.w});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (w.isPaused)
            FilledButton.icon(
              onPressed: w.resume,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.workoutResume),
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 44),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: w.pause,
              icon: const Icon(Icons.pause),
              label: Text(l10n.workoutPause),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 44),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Widget para estadísticas en diálogo de completado ────────────────────

class _CompletionStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CompletionStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF00B4D8)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
