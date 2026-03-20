import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import '../../core/models/interval_step.dart';
import '../../core/models/rowing_data.dart';
import '../../core/strava/strava_config.dart';
import '../../shared/theme.dart';
import '../device/device_provider.dart';
import '../profile/profile_provider.dart';
import 'workout_provider.dart';

// ─── Entry point ──────────────────────────────────────────────────────────

class ImmersiveWorkoutPage extends StatefulWidget {
  const ImmersiveWorkoutPage({super.key});

  @override
  State<ImmersiveWorkoutPage> createState() => _ImmersiveWorkoutPageState();
}

class _ImmersiveWorkoutPageState extends State<ImmersiveWorkoutPage>
    with TickerProviderStateMixin {
  bool _hasShownCompletionDialog = false;

  // Rowing stroke animation
  late AnimationController _strokeController;
  // Cloud parallax
  late AnimationController _cloudController;
  // Water ripple / wake
  late AnimationController _wakeController;

  double _lastSpm = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _strokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _cloudController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _wakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _strokeController.dispose();
    _cloudController.dispose();
    _wakeController.dispose();
    super.dispose();
  }

  void _updateAvatarAnimationFromSpm(double spm, bool isActive) {
    if (!isActive || spm < 1) {
      _strokeController.stop();
      _wakeController.stop();
      return;
    }

    // One full stroke cycle per... (60/spm) seconds
    final cycleDuration =
        Duration(milliseconds: ((60 / spm) * 1000).round().clamp(400, 3000));

    if ((spm - _lastSpm).abs() > 0.5 || !_strokeController.isAnimating) {
      _strokeController.duration = cycleDuration;
      _strokeController.repeat();
      _wakeController.duration = cycleDuration;
      _wakeController.repeat();
      _lastSpm = spm;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkoutProvider>();
    final sp = w.stepProgress;

    _updateAvatarAnimationFromSpm(
      w.data.strokeRate,
      w.phase == WorkoutPhase.active,
    );

    // Completion dialog — fire once
    if (w.phase == WorkoutPhase.finished && !_hasShownCompletionDialog) {
      _hasShownCompletionDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCompletionDialog(context, w);
      });
    }

    // Return to idle
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
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Outdoor background ──────────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([_cloudController, _wakeController]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _OutdoorScenePainter(
                    cloudOffset: _cloudController.value,
                    wakePhase: _wakeController.value,
                    isRowing: w.phase == WorkoutPhase.active &&
                        w.data.strokeRate > 0,
                  ),
                );
              },
            ),

            // ── 2. Rowing avatar ───────────────────────────────────
            AnimatedBuilder(
              animation: _strokeController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _RowingAvatarPainter(
                    strokePhase: _strokeController.value,
                    isRowing: w.phase == WorkoutPhase.active &&
                        w.data.strokeRate > 0,
                    isPaused: w.phase == WorkoutPhase.paused,
                  ),
                );
              },
            ),

            // ── 3. Stage timeline (top) ────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: sp != null
                  ? _StageTimelineBar(sp: sp, w: w)
                  : _FreeWorkoutTopBar(w: w),
            ),

            // ── 4. HUD overlay ─────────────────────────────────────
            _ImmersiveHUD(data: w.data, elapsedSeconds: w.totalElapsedSeconds,
                currentStep: sp?.step),

            // ── 5. Controls ────────────────────────────────────────
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: _ImmersiveControls(w: w, onFinish: () => _confirmFinish(context, w)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Finish confirmation ───────────────────────────────────────────────────

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

  void _triggerStravaUpload(BuildContext context, WorkoutProvider w) {
    final profile = context.read<ProfileProvider>();
    final sessionId = w.lastFinishedSessionId;
    if (!profile.isConnected || sessionId == null) return;
    final l10n = AppLocalizations.of(context)!;

    switch (profile.uploadPreference) {
      case UploadPreference.auto:
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.profileUploadingToStrava)));
        profile.uploadSession(sessionId).then((ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(ok ? l10n.profileUploaded : l10n.profileUploadFailed)),
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

  // ── Completion dialog ─────────────────────────────────────────────────────

  void _showCompletionDialog(BuildContext context, WorkoutProvider w) async {
    final l10n = AppLocalizations.of(context)!;
    final profile =
        StravaConfig.isConfigured ? context.read<ProfileProvider>() : null;
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
              Text(l10n.workoutCompletedMessage ??
                  'Has completado tu rutina exitosamente.'),
              const SizedBox(height: 16),
              _CompletionStats(w: w),
            ],
          ),
          actions: [
            if (shouldAskStrava) ...[
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
                          SnackBar(
                              content: Text(ok
                                  ? l10n.profileUploaded
                                  : l10n.profileUploadFailed)),
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
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (StravaConfig.isConfigured &&
                      profile != null &&
                      profile.isConnected &&
                      profile.uploadPreference == UploadPreference.auto) {
                    final sessionId = w.lastFinishedSessionId;
                    if (sessionId != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text(l10n.profileUploadingToStrava)),
                      );
                      profile.uploadSession(sessionId).then((ok) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(ok
                                    ? l10n.profileUploaded
                                    : l10n.profileUploadFailed)),
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
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTDOOR SCENE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _OutdoorScenePainter extends CustomPainter {
  final double cloudOffset; // 0..1 looping
  final double wakePhase;   // 0..1 looping
  final bool isRowing;

  const _OutdoorScenePainter({
    required this.cloudOffset,
    required this.wakePhase,
    required this.isRowing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Sky gradient ──────────────────────────────────────────────────────
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.center,
      colors: const [
        Color(0xFF0A2040), // deep dawn blue
        Color(0xFF1565C0), // mid sky
        Color(0xFF42A5F5), // horizon glow
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.60),
      Paint()..shader = skyGradient.createShader(Rect.fromLTWH(0, 0, w, h * 0.60)),
    );

    // ── Sun / glow near horizon ───────────────────────────────────────────
    final sunY = h * 0.42;
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD082).withOpacity(0.7),
          const Color(0xFFFF8C42).withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(w * 0.5, sunY), radius: 80));
    canvas.drawCircle(Offset(w * 0.5, sunY), 80, sunPaint);
    canvas.drawCircle(
      Offset(w * 0.5, sunY),
      18,
      Paint()..color = const Color(0xFFFFE57F),
    );

    // ── Clouds ────────────────────────────────────────────────────────────
    final cloudPaint = Paint()..color = Colors.white.withOpacity(0.55);
    final clouds = [
      (x: 0.08, y: 0.12, r: 28.0),
      (x: 0.22, y: 0.08, r: 18.0),
      (x: 0.55, y: 0.10, r: 32.0),
      (x: 0.70, y: 0.15, r: 22.0),
      (x: 0.88, y: 0.09, r: 24.0),
    ];
    for (final c in clouds) {
      final dx = ((c.x + cloudOffset * 0.25) % 1.0) * w;
      _drawCloud(canvas, Offset(dx, h * c.y), c.r, cloudPaint);
    }

    // ── Treeline / shore at horizon ───────────────────────────────────────
    final horizonY = h * 0.52;
    _drawTreeline(canvas, size, horizonY);

    // ── Water gradient ────────────────────────────────────────────────────
    final waterGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFF1565C0),
        Color(0xFF0D3B6E),
        Color(0xFF071E3D),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, w, h - horizonY),
      Paint()
        ..shader = waterGradient
            .createShader(Rect.fromLTWH(0, horizonY, w, h - horizonY)),
    );

    // ── Water shimmer lines ───────────────────────────────────────────────
    final shimmerPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1.5;
    for (int i = 0; i < 8; i++) {
      final lineY = horizonY + (h - horizonY) * (i + 1) / 9;
      final lineW = w * (0.3 + 0.4 * i / 8);
      canvas.drawLine(
        Offset((w - lineW) / 2, lineY),
        Offset((w + lineW) / 2, lineY),
        shimmerPaint,
      );
    }

    // ── Wake / water ripples behind boat ─────────────────────────────────
    if (isRowing) {
      _drawWake(canvas, size, horizonY, wakePhase);
    }
  }

  void _drawCloud(Canvas canvas, Offset center, double r, Paint p) {
    canvas.drawCircle(center, r, p);
    canvas.drawCircle(center.translate(-r * 0.7, r * 0.3), r * 0.65, p);
    canvas.drawCircle(center.translate(r * 0.7, r * 0.3), r * 0.65, p);
    canvas.drawCircle(center.translate(r * 1.2, 0), r * 0.5, p);
    canvas.drawCircle(center.translate(-r * 1.2, 0), r * 0.5, p);
  }

  void _drawTreeline(Canvas canvas, Size size, double horizonY) {
    final w = size.width;
    final treePaint = Paint()..color = const Color(0xFF1B5E20);
    final treeDarkPaint = Paint()..color = const Color(0xFF0A3D10);

    // Simple tree silhouettes as triangles
    final treeData = [
      (x: 0.02, h: 0.07), (x: 0.06, h: 0.09), (x: 0.10, h: 0.06),
      (x: 0.14, h: 0.08), (x: 0.18, h: 0.05), (x: 0.22, h: 0.07),
      (x: 0.65, h: 0.06), (x: 0.69, h: 0.08), (x: 0.73, h: 0.05),
      (x: 0.77, h: 0.09), (x: 0.81, h: 0.07), (x: 0.85, h: 0.05),
      (x: 0.89, h: 0.08), (x: 0.93, h: 0.06), (x: 0.97, h: 0.07),
    ];

    for (final t in treeData) {
      final tx = t.x * w;
      final th = t.h * size.height;
      final treeW = th * 0.55;
      final path = Path()
        ..moveTo(tx, horizonY - th)
        ..lineTo(tx - treeW / 2, horizonY)
        ..lineTo(tx + treeW / 2, horizonY)
        ..close();
      canvas.drawPath(path, treePaint);
      // Shadow side
      final shadowPath = Path()
        ..moveTo(tx, horizonY - th)
        ..lineTo(tx, horizonY)
        ..lineTo(tx + treeW / 2, horizonY)
        ..close();
      canvas.drawPath(shadowPath, treeDarkPaint);
    }
  }

  void _drawWake(Canvas canvas, Size size, double horizonY, double phase) {
    final centerX = size.width / 2;
    final startY = horizonY + size.height * 0.08; // just below boat
    final maxY = size.height * 0.92;

    for (int i = 0; i < 4; i++) {
      final t = ((phase + i * 0.25) % 1.0);
      final wakeY = startY + (maxY - startY) * t;
      final halfW = 12 + 50 * t;
      final opacity = (1.0 - t) * 0.35;
      final wakePaint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(centerX - halfW, wakeY)
        ..quadraticBezierTo(centerX, wakeY - 6, centerX + halfW, wakeY);
      canvas.drawPath(path, wakePaint);
    }
  }

  @override
  bool shouldRepaint(_OutdoorScenePainter old) =>
      cloudOffset != old.cloudOffset ||
      wakePhase != old.wakePhase ||
      isRowing != old.isRowing;
}

// ═══════════════════════════════════════════════════════════════════════════
// ROWING AVATAR PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _RowingAvatarPainter extends CustomPainter {
  final double strokePhase; // 0..1
  final bool isRowing;
  final bool isPaused;

  const _RowingAvatarPainter({
    required this.strokePhase,
    required this.isRowing,
    required this.isPaused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Boat sits just below the horizon (~55% height)
    final boatCenterY = h * 0.60;
    final boatCenterX = w * 0.5;

    // Stroke animation: 0→0.4 = drive (lean back, arms pull), 0.4→0.7 = finish,
    // 0.7→1.0 = recovery (lean forward, arms extend)
    final phase = isRowing ? strokePhase : 0.35; // rest at mid-drive if idle

    // Body lean angle: from +20° (forward/catch) to -20° (back/finish)
    final leanAngle = _lerp(-0.35, 0.35, _smoothPhase(phase));

    // Arm extension: 0 = fully extended (catch), 1 = fully bent (finish)
    final armBend = phase < 0.5
        ? _lerp(0.0, 1.0, phase / 0.5)
        : _lerp(1.0, 0.0, (phase - 0.5) / 0.5);

    // ── Draw boat ─────────────────────────────────────────────────────────
    _drawBoat(canvas, boatCenterX, boatCenterY, w);

    // ── Draw oar blades ───────────────────────────────────────────────────
    _drawOars(canvas, boatCenterX, boatCenterY, armBend, w);

    // ── Draw rower figure ─────────────────────────────────────────────────
    _drawRower(canvas, boatCenterX, boatCenterY - 4, leanAngle, armBend);
  }

  double _smoothPhase(double t) {
    // Ease in-out
    return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0, 1);

  void _drawBoat(Canvas canvas, double cx, double cy, double screenW) {
    final boatW = screenW * 0.45;
    final boatH = 14.0;

    // Hull
    final hullPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFF5F5F5), const Color(0xFFBDBDBD)],
      ).createShader(Rect.fromLTWH(cx - boatW / 2, cy, boatW, boatH));

    final hull = Path()
      ..moveTo(cx - boatW / 2, cy + boatH * 0.4)
      ..quadraticBezierTo(cx - boatW * 0.3, cy, cx, cy)
      ..quadraticBezierTo(cx + boatW * 0.3, cy, cx + boatW / 2, cy + boatH * 0.4)
      ..lineTo(cx + boatW * 0.38, cy + boatH)
      ..quadraticBezierTo(cx, cy + boatH * 1.3, cx - boatW * 0.38, cy + boatH)
      ..close();

    canvas.drawPath(hull, hullPaint);

    // Hull accent line
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF00B4D8).withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Water line reflection
    canvas.drawLine(
      Offset(cx - boatW * 0.4, cy + boatH * 1.1),
      Offset(cx + boatW * 0.4, cy + boatH * 1.1),
      Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..strokeWidth = 1,
    );
  }

  void _drawOars(
      Canvas canvas, double cx, double boatY, double armBend, double screenW) {
    final oarPaint = Paint()
      ..color = const Color(0xFFBCAAA4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final bladeColor = Paint()..color = const Color(0xFF00B4D8);

    // Oar angle swings with arm bend
    // armBend 0 = catch (oar behind), 1 = finish (oar forward)
    final oarAngle = _lerp(-0.5, 0.5, armBend); // radians sweep

    for (final side in [-1.0, 1.0]) {
      final pivotX = cx + side * screenW * 0.08;
      final pivotY = boatY + 6;
      final oarLen = screenW * 0.28;

      final angle = oarAngle * side + math.pi / 2;
      final endX = pivotX + oarLen * math.cos(angle) * side;
      final endY = pivotY + oarLen * math.sin(angle) * 0.35;

      // Shaft
      canvas.drawLine(Offset(pivotX, pivotY), Offset(endX, endY), oarPaint);

      // Blade (small rectangle at tip)
      canvas.save();
      canvas.translate(endX, endY);
      canvas.rotate(angle - math.pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-6, -2, 12, 18),
          const Radius.circular(3),
        ),
        bladeColor,
      );
      canvas.restore();
    }
  }

  void _drawRower(
      Canvas canvas, double cx, double cy, double leanAngle, double armBend) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(leanAngle);

    final skinPaint = Paint()..color = const Color(0xFFFFCC80);
    final suitPaint = Paint()..color = const Color(0xFF1565C0);
    final darkSuit = Paint()..color = const Color(0xFF0D3B6E);

    // Torso
    final torsoPath = Path()
      ..moveTo(-9, -30)
      ..lineTo(-10, 0)
      ..lineTo(10, 0)
      ..lineTo(9, -30)
      ..close();
    canvas.drawPath(torsoPath, suitPaint);

    // Legs (seat)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-10, -4, 20, 10), const Radius.circular(3)),
      darkSuit,
    );

    // Arms
    final armExtend = _lerp(18.0, 8.0, armBend); // arm reach
    const armY = -18.0;
    // Left arm
    canvas.drawLine(
      const Offset(-9, armY),
      Offset(-armExtend, armY + 4),
      Paint()
        ..color = const Color(0xFF1565C0)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    // Right arm
    canvas.drawLine(
      const Offset(9, armY),
      Offset(armExtend, armY + 4),
      Paint()
        ..color = const Color(0xFF1565C0)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // Hands
    canvas.drawCircle(Offset(-armExtend, armY + 4), 4, skinPaint);
    canvas.drawCircle(Offset(armExtend, armY + 4), 4, skinPaint);

    // Head
    canvas.drawCircle(const Offset(0, -36), 10, skinPaint);

    // Helmet / cap
    canvas.drawArc(
      const Rect.fromLTWH(-10, -48, 20, 20),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFF1565C0),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RowingAvatarPainter old) =>
      strokePhase != old.strokePhase ||
      isRowing != old.isRowing ||
      isPaused != old.isPaused;
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TIMELINE BAR (for routines)
// ═══════════════════════════════════════════════════════════════════════════

class _StageTimelineBar extends StatefulWidget {
  final StepProgress sp;
  final WorkoutProvider w;
  const _StageTimelineBar({required this.sp, required this.w});

  @override
  State<_StageTimelineBar> createState() => _StageTimelineBarState();
}

class _StageTimelineBarState extends State<_StageTimelineBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.sp;
    final w = widget.w;
    final routine = w.routine;
    if (routine == null) return const SizedBox.shrink();

    final steps = routine.steps;
    final remaining = sp.remainingInStep;
    final isEndingSoon = sp.isEndingSoon;

    // Next step preview (show when ≤ 15s remaining)
    final showUpNext =
        remaining >= 0 && remaining <= 15 && sp.stepIndex + 1 < sp.totalSteps;
    final nextStep =
        showUpNext ? steps[sp.stepIndex + 1] : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Steps pill row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  _StepPill(
                    step: steps[i],
                    isActive: i == sp.stepIndex,
                    isCompleted: i < sp.stepIndex,
                    progress: i == sp.stepIndex ? sp.progress : 0,
                    pulseAnim: isEndingSoon && i == sp.stepIndex ? _pulseCtrl : null,
                  ),
                ]
              ],
            ),
          ),

          // ── Active step info ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                // Step type label
                Text(
                  stepTypeLocalized(sp.step.type, AppLocalizations.of(context)!),
                  style: TextStyle(
                    color: stepColor(sp.step.type.name),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                if (sp.step.targetLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: stepColor(sp.step.type.name).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sp.step.targetLabel,
                      style: TextStyle(
                          color: stepColor(sp.step.type.name),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(),
                // Up next chip
                if (showUpNext && nextStep != null)
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Opacity(
                      opacity: 0.6 + _pulseCtrl.value * 0.4,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: stepColor(nextStep.type.name).withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: stepColor(nextStep.type.name).withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Up next: ',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 10)),
                            Text(
                              stepTypeLocalized(nextStep.type, AppLocalizations.of(context)!),
                              style: TextStyle(
                                color: stepColor(nextStep.type.name),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Countdown
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final remainStr = remaining >= 0
                        ? '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
                        : '${sp.step.distanceMeters}m';
                    return Text(
                      remainStr,
                      style: TextStyle(
                        color: isEndingSoon
                            ? Color.lerp(Colors.white,
                                stepColor(sp.step.type.name), _pulseCtrl.value)!
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: isEndingSoon ? 20 : 18,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final IntervalStep step;
  final bool isActive;
  final bool isCompleted;
  final double progress;
  final AnimationController? pulseAnim;

  const _StepPill({
    required this.step,
    required this.isActive,
    required this.isCompleted,
    required this.progress,
    this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final color = stepColor(step.type.name);
    final baseOpacity = isCompleted ? 0.35 : (isActive ? 1.0 : 0.45);

    Widget pill = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            // Background
            Container(color: color.withOpacity(baseOpacity * 0.4)),
            // Fill for active step progress
            if (isActive && progress > 0)
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(color: color),
              )
            else if (isCompleted)
              Container(color: color.withOpacity(0.45)),
          ],
        ),
      ),
    );

    if (pulseAnim != null) {
      pill = AnimatedBuilder(
        animation: pulseAnim!,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3 + pulseAnim!.value * 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              )
            ],
          ),
          child: child,
        ),
        child: pill,
      );
    }

    return Expanded(child: pill);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FREE WORKOUT TOP BAR (no routine)
// ═══════════════════════════════════════════════════════════════════════════

class _FreeWorkoutTopBar extends StatelessWidget {
  final WorkoutProvider w;
  const _FreeWorkoutTopBar({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.rowing, color: Color(0xFF00B4D8), size: 20),
          const SizedBox(width: 8),
          const Text(
            'Entrenamiento Libre',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _PhaseChip(phase: w.phase),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final WorkoutPhase phase;
  const _PhaseChip({required this.phase});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      WorkoutPhase.active => ('EN MARCHA', const Color(0xFF06D6A0)),
      WorkoutPhase.paused => ('PAUSADO', const Color(0xFFFFD166)),
      WorkoutPhase.finished => ('FINALIZADO', const Color(0xFFEF476F)),
      _ => ('—', Colors.white38),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// IMMERSIVE HUD — floating metrics overlay
// ═══════════════════════════════════════════════════════════════════════════

class _ImmersiveHUD extends StatelessWidget {
  final RowingData data;
  final int elapsedSeconds;
  final IntervalStep? currentStep;

  const _ImmersiveHUD({
    required this.data,
    required this.elapsedSeconds,
    required this.currentStep,
  });

  String get _timeFormatted {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _targetColor(double? val, double? target, {bool invert = false}) {
    if (val == null || target == null) return Colors.white;
    if (invert) return val > target ? const Color(0xFFFF4444) : Colors.white;
    return val < target ? const Color(0xFFFF4444) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final hasSpmTarget = currentStep?.targetSpm != null;
    final hasWattsTarget = currentStep?.targetWattsMin != null;
    final hasSplitTarget = currentStep?.targetSplitSeconds != null;

    final spmColor = hasSpmTarget
        ? _targetColor(data.strokeRate, currentStep?.targetSpm?.toDouble())
        : MetricColors.spm;
    final wattsColor = hasWattsTarget
        ? _targetColor(
            data.powerWatts.toDouble(), currentStep?.targetWattsMin?.toDouble())
        : MetricColors.watts;
    final splitColor = hasSplitTarget
        ? _targetColor(data.pace500mSeconds.toDouble(),
            currentStep?.targetSplitSeconds?.toDouble(),
            invert: true)
        : MetricColors.split;

    return Stack(
      children: [
        // ── Top-left: SPM (biggest metric) ─────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 90,
          left: 14,
          child: _GlassMetricCard(
            label: 'SPM',
            value: data.strokeRate.toStringAsFixed(1),
            color: spmColor,
            size: _MetricSize.large,
            hasTarget: hasSpmTarget,
          ),
        ),

        // ── Top-right: Split + Watts stacked ───────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 90,
          right: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GlassMetricCard(
                label: 'Split /500m',
                value: data.pace500mFormatted,
                color: splitColor,
                size: _MetricSize.medium,
                hasTarget: hasSplitTarget,
              ),
              const SizedBox(height: 8),
              _GlassMetricCard(
                label: 'Watts',
                value: '${data.powerWatts}',
                unit: 'W',
                color: wattsColor,
                size: _MetricSize.medium,
                hasTarget: hasWattsTarget,
              ),
            ],
          ),
        ),

        // ── Center band: Distance + Time ───────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 140,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.50),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CenterMetric(
                    icon: Icons.timer_outlined,
                    value: _timeFormatted,
                    color: MetricColors.time,
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.white12,
                  ),
                  _CenterMetric(
                    icon: Icons.straighten,
                    value: '${data.distanceMeters}',
                    unit: 'm',
                    color: MetricColors.distance,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Bottom-right: Calories + Heart Rate ────────────────────────
        Positioned(
          bottom: 140,
          right: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GlassMetricCard(
                label: 'kcal',
                value: '${data.totalCalories}',
                color: MetricColors.calories,
                size: _MetricSize.small,
              ),
              if (data.heartRate > 0) ...[
                const SizedBox(height: 8),
                _GlassMetricCard(
                  label: 'BPM',
                  value: '${data.heartRate}',
                  color: MetricColors.heartRate,
                  size: _MetricSize.small,
                  icon: Icons.favorite,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum _MetricSize { large, medium, small }

class _GlassMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color color;
  final _MetricSize size;
  final bool hasTarget;
  final IconData? icon;

  const _GlassMetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.size,
    this.unit,
    this.hasTarget = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final (valueFontSize, labelFontSize, minW) = switch (size) {
      _MetricSize.large => (52.0, 13.0, 130.0),
      _MetricSize.medium => (36.0, 12.0, 110.0),
      _MetricSize.small => (28.0, 11.0, 90.0),
    };

    return Container(
      constraints: BoxConstraints(minWidth: minW),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasTarget
              ? color.withOpacity(0.7)
              : Colors.white.withOpacity(0.10),
          width: hasTarget ? 1.5 : 1.0,
        ),
        boxShadow: hasTarget
            ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: labelFontSize, color: color.withOpacity(0.8)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit!,
                  style: TextStyle(
                      color: color.withOpacity(0.55),
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CenterMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? unit;
  final Color color;

  const _CenterMetric({
    required this.icon,
    required this.value,
    required this.color,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color.withOpacity(0.7), size: 16),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                    color: color.withOpacity(0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// IMMERSIVE CONTROLS
// ═══════════════════════════════════════════════════════════════════════════

class _ImmersiveControls extends StatelessWidget {
  final WorkoutProvider w;
  final VoidCallback onFinish;

  const _ImmersiveControls({required this.w, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Finish button (ghost, left)
          OutlinedButton(
            onPressed: onFinish,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 1.2),
              minimumSize: const Size(120, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              backgroundColor: Colors.black.withOpacity(0.45),
            ),
            child: const Text('Terminar', style: TextStyle(fontSize: 15)),
          ),

          const SizedBox(width: 16),

          // Pause / Resume
          if (w.isPaused)
            FilledButton.icon(
              onPressed: w.resume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reanudar', style: TextStyle(fontSize: 15)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF06D6A0),
                foregroundColor: Colors.black,
                minimumSize: const Size(140, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: w.pause,
              icon: const Icon(Icons.pause),
              label: const Text('Pausa', style: TextStyle(fontSize: 15)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.black.withOpacity(0.45),
                side: const BorderSide(color: Colors.white24, width: 1.2),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPLETION STATS (dialog)
// ═══════════════════════════════════════════════════════════════════════════

class _CompletionStats extends StatelessWidget {
  final WorkoutProvider w;
  const _CompletionStats({required this.w});

  @override
  Widget build(BuildContext context) {
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
          _StatRow(icon: Icons.timer, label: 'Tiempo', value: timeStr),
          const SizedBox(height: 8),
          _StatRow(
              icon: Icons.straighten,
              label: 'Distancia',
              value: '${w.data.distanceMeters} m'),
          const SizedBox(height: 8),
          _StatRow(
              icon: Icons.local_fire_department,
              label: 'Calorías',
              value: '${w.data.totalCalories}'),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF00B4D8)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70))),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
