// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get navDevice => 'Dispositivo';

  @override
  String get navWorkout => 'Workout';

  @override
  String get navRoutines => 'Rutinas';

  @override
  String get navHistory => 'Historial';

  @override
  String get navProfile => 'Perfil';

  @override
  String get deviceTitle => 'Dispositivo';

  @override
  String get deviceDisconnect => 'Desconectar';

  @override
  String get deviceConnected => 'Conectado';

  @override
  String get deviceSearching => 'Buscando...';

  @override
  String get deviceSearch => 'Buscar dispositivos';

  @override
  String get deviceSearchHint =>
      'Buscando dispositivos FTMS con servicio 0x1826...';

  @override
  String get deviceNoResults => 'No se encontraron dispositivos';

  @override
  String get deviceNoResultsHint =>
      'Asegurate que el rower esté encendido\ny el Bluetooth activado';

  @override
  String get deviceBtOff => 'Bluetooth apagado';

  @override
  String get deviceBtOffHint =>
      'Activá el Bluetooth desde el Centro de Control\no Ajustes para buscar el rower';

  @override
  String get deviceBtDenied => 'Permiso de Bluetooth denegado';

  @override
  String get deviceBtDeniedHint =>
      'Habilitá el permiso de Bluetooth en\nAjustes > Privacidad > Bluetooth';

  @override
  String get deviceBtEnable => 'Activar Bluetooth';

  @override
  String get hrmTitle => 'Pulsómetro';

  @override
  String get hrmNoSensor => 'Sin sensor';

  @override
  String get hrmWatchHint =>
      'Un smartwatch necesita una app que transmita el pulso por Bluetooth (p. ej. Heart for Bluetooth en Wear OS).';

  @override
  String get hrmSearch => 'Buscar';

  @override
  String get hrmSearchOther => 'Buscar otro';

  @override
  String get hrmSearching => 'Buscando sensores…';

  @override
  String hrmConnectingTo(String name) {
    return 'Conectando a $name…';
  }

  @override
  String get hrmConnect => 'Conectar';

  @override
  String get hrmDisconnect => 'Desconectar';

  @override
  String get hrmForget => 'Olvidar';

  @override
  String get hrmReconnecting => 'reconectando…';

  @override
  String get hrmNotFound => 'no encontrado';

  @override
  String get hrmUnknownSensor => 'Sensor desconocido';

  @override
  String get hrmIncompatible =>
      'No es un pulsómetro compatible (sin servicio Heart Rate)';

  @override
  String hrmConnectError(String error) {
    return 'Error al conectar: $error';
  }

  @override
  String get hrmBpm => 'bpm';

  @override
  String get workoutTitle => 'Entrenamiento';

  @override
  String get workoutFree => 'Entrenamiento libre';

  @override
  String get workoutRowerNotConnected =>
      'Conectá el rower para iniciar un entrenamiento';

  @override
  String get workoutOrPickRoutine => '  O elegí una rutina:';

  @override
  String get workoutNoRoutines => 'Creá una rutina en la pestaña \"Rutinas\"';

  @override
  String get workoutInProgress => 'Entrenamiento en curso...';

  @override
  String get workoutScene => 'Escenario';

  @override
  String get sceneLake => 'Lago alpino';

  @override
  String get sceneRiver => 'Río urbano';

  @override
  String get sceneCoast => 'Costa';

  @override
  String get sceneRegatta => 'Canal de regata';

  @override
  String get workoutFinish => 'Terminar';

  @override
  String get workoutFinishTitle => 'Terminar entrenamiento';

  @override
  String get workoutFinishContent => 'Se guardará la sesión. ¿Continuar?';

  @override
  String get workoutPause => 'Pausa';

  @override
  String get workoutResume => 'Reanudar';

  @override
  String get workoutStartTitle => 'Iniciar entrenamiento?';

  @override
  String workoutStartContent(String summary) {
    return '$summary\n\nIniciar el entrenamiento?';
  }

  @override
  String get workoutStart => 'Iniciar';

  @override
  String get workoutCompleted => '¡Entrenamiento completado!';

  @override
  String get workoutCompletedMessage =>
      'Has completado tu rutina exitosamente.';

  @override
  String get metricTime => 'TIEMPO';

  @override
  String get metricSplit => 'SPLIT 500m';

  @override
  String get metricDistance => 'DISTANCIA';

  @override
  String get metricWatts => 'VATIOS';

  @override
  String get metricSpm => 'SPM';

  @override
  String get metricCalories => 'CALORÍAS';

  @override
  String get metricHeartRate => 'PULSO';

  @override
  String get metricFreeLabel => 'Entrenamiento libre';

  @override
  String get routinesTitle => 'Rutinas';

  @override
  String get routinesEmpty => 'No hay rutinas todavía';

  @override
  String get routinesEmptyHint => 'Presioná + para crear una';

  @override
  String get routineEdit => 'Editar';

  @override
  String get routineDelete => 'Eliminar';

  @override
  String get routineDeleteTitle => 'Eliminar rutina';

  @override
  String routineDeleteContent(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get historyTitle => 'Historial';

  @override
  String get historyEmpty => 'No hay sesiones guardadas';

  @override
  String get historyFree => 'Libre';

  @override
  String get historyStatTime => 'Tiempo';

  @override
  String get historyStatDistance => 'Distancia';

  @override
  String get historyStatWatts => 'Vatios';

  @override
  String get historyStatCalories => 'kcal';

  @override
  String get historyStatHeartRate => 'Pulso';

  @override
  String get sessionNoTelemetry => 'No hay datos de telemetría';

  @override
  String get sessionSummary => 'Resumen';

  @override
  String get sessionStepBreakdown => 'Rendimiento por paso';

  @override
  String get sessionChartWatts => 'Vatios';

  @override
  String get sessionChartSpm => 'SPM';

  @override
  String get sessionChartSplit => 'Split 500m';

  @override
  String get sessionChartDistance => 'Distancia';

  @override
  String get sessionChartHr => 'Pulso';

  @override
  String get stepTypeWarmup => 'Calentamiento';

  @override
  String get stepTypeWork => 'Trabajo';

  @override
  String get stepTypeRest => 'Descanso';

  @override
  String get stepTypeCooldown => 'Enfriamiento';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirmar';

  @override
  String get save => 'Guardar';

  @override
  String get editorNewRoutine => 'Nueva rutina';

  @override
  String get editorEditRoutine => 'Editar rutina';

  @override
  String get editorRoutineName => 'Nombre de la rutina';

  @override
  String get editorDescription => 'Descripción (opcional)';

  @override
  String editorStepsCount(int count) {
    return 'Pasos ($count)';
  }

  @override
  String get editorStep => 'Paso';

  @override
  String get editorSeries => 'Serie';

  @override
  String get editorEmptySteps =>
      'Todavía no hay pasos.\nPresioná \"Paso\" o \"Serie\".';

  @override
  String get editorDeleteSeries => 'Eliminar serie';

  @override
  String get editorAddStepToSeries => 'Agregar paso a serie';

  @override
  String get editorRepetitions => 'Repeticiones';

  @override
  String get editorAmount => 'Cantidad';

  @override
  String get editorNameEmpty => 'El nombre no puede estar vacío';

  @override
  String get editorNoSteps => 'Agregá al menos un paso';

  @override
  String get editorNewStep => 'Nuevo paso';

  @override
  String get editorEditStep => 'Editar paso';

  @override
  String get editorStepType => 'Tipo';

  @override
  String get editorByTime => 'Por tiempo';

  @override
  String get editorByDistance => 'Por distancia';

  @override
  String get editorMinutes => 'Min';

  @override
  String get editorSeconds => 'Seg';

  @override
  String get editorMeters => 'Metros';

  @override
  String get editorOptionalTargets => 'Objetivos opcionales';

  @override
  String get editorWattsMin => 'W mín';

  @override
  String get editorWattsMax => 'W máx';

  @override
  String get editorTargetSpm => 'SPM objetivo';

  @override
  String get editorSplitMin => 'Split min';

  @override
  String get editorSplitSec => 'Split seg';

  @override
  String get editorProgressions => 'Progresiones (solo aplica en series)';

  @override
  String get editorProgressionSpm => 'Incremento SPM (+/rep)';

  @override
  String get editorProgressionSpmHint => 'Ej: 2';

  @override
  String get editorProgressionWatts => 'Incremento Watts (+/rep)';

  @override
  String get editorProgressionWattsHint => 'Ej: 5';

  @override
  String get editorProgressionSplit => 'Cambio Split segundos (+/-/rep)';

  @override
  String get editorProgressionSplitHint => 'Ej: -2 (más rápido)';

  @override
  String get profileTitle => 'Perfil';

  @override
  String get profileConnectStrava => 'Conectar con Strava';

  @override
  String get profileConnected => 'Conectado';

  @override
  String get profileConnectedToStrava => 'Conectado a Strava';

  @override
  String get profileDisconnect => 'Desconectar';

  @override
  String get profileDisconnectTitle => 'Desconectar Strava';

  @override
  String get profileDisconnectContent =>
      'Tus sesiones no se subirán automáticamente. ¿Continuar?';

  @override
  String get profileUploadSettings => 'Configuración de subida';

  @override
  String get profileAutoUpload => 'Subida automática';

  @override
  String get profileAutoUploadDesc =>
      'Subir sesiones a Strava automáticamente al terminar';

  @override
  String get profileAskUpload => 'Preguntar cada vez';

  @override
  String get profileAskUploadDesc =>
      'Mostrar un diálogo después de cada entrenamiento';

  @override
  String get profileManualUpload => 'Solo manual';

  @override
  String get profileManualUploadDesc =>
      'Subir sesiones manualmente desde el Historial';

  @override
  String get profileSync => 'Sincronización';

  @override
  String get profileSyncDesc =>
      'Descargar tus actividades de remo desde Strava';

  @override
  String get profileSyncFromStrava => 'Sincronizar desde Strava';

  @override
  String get profileSyncToStrava => 'Sincronizar a Strava';

  @override
  String get profileSyncing => 'Sincronizando...';

  @override
  String get profileUploading => 'Subiendo...';

  @override
  String profileSyncResult(int count) {
    return '$count sesiones sincronizadas';
  }

  @override
  String profileUploadResult(int count) {
    return '$count sesiones subidas';
  }

  @override
  String get profileSyncToDesc =>
      'Subir todas las sesiones locales sin sincronizar a Strava';

  @override
  String get profilePendingUploads => 'Subidas pendientes';

  @override
  String get profileUploadToStrava => 'Subir a Strava';

  @override
  String get profileUploadingToStrava => 'Subiendo a Strava...';

  @override
  String get profileUploaded => 'Subido a Strava';

  @override
  String get profileUploadFailed => 'Error al subir';

  @override
  String get profileAskUploadDialog => '¿Subir esta sesión a Strava?';
}
