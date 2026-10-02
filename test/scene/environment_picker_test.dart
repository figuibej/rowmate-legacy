import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/features/workout/scene/environment.dart';
import 'package:rowmate/features/workout/scene/environment_picker.dart';
import 'package:rowmate/features/workout/scene/scene_settings.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tocar una tarjeta cambia el escenario y lo persiste', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SceneSettings();
    await tester.pumpWidget(
      ChangeNotifierProvider<SceneSettings>.value(
        value: settings,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: EnvironmentPicker()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(settings.environmentId, EnvironmentId.lake);
    expect(find.text('Lago alpino'), findsOneWidget);

    await tester.tap(find.text('Río urbano'));
    await tester.pumpAndSettle();
    expect(settings.environmentId, EnvironmentId.river);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SceneSettings.prefKey), 'river');
  });

  testWidgets('arranca con el escenario guardado', (tester) async {
    SharedPreferences.setMockInitialValues({SceneSettings.prefKey: 'coast'});
    final settings = SceneSettings();
    await tester.pump(const Duration(milliseconds: 50));
    expect(settings.environmentId, EnvironmentId.coast);
  });
}
