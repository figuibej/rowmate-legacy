import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'environment.dart';
import 'painters/thumbnail_painter.dart';
import 'scene_settings.dart';

String environmentName(EnvironmentId id, AppLocalizations l10n) => switch (id) {
      EnvironmentId.lake => l10n.sceneLake,
      EnvironmentId.river => l10n.sceneRiver,
      EnvironmentId.coast => l10n.sceneCoast,
      EnvironmentId.regatta => l10n.sceneRegatta,
    };

/// Fila horizontal de tarjetas con miniatura para elegir el escenario.
class EnvironmentPicker extends StatelessWidget {
  const EnvironmentPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SceneSettings>();
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EnvironmentId.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final id = EnvironmentId.values[i];
          final selected = id == settings.environmentId;
          return GestureDetector(
            onTap: () => settings.setEnvironment(id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 80,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? const Color(0xFF00B4D8) : Colors.white12,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: CustomPaint(painter: ThumbnailPainter(Environment.of(id))),
                ),
                const SizedBox(height: 6),
                Text(
                  environmentName(id, l10n),
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
