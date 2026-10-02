// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navDevice => 'Device';

  @override
  String get navWorkout => 'Workout';

  @override
  String get navRoutines => 'Routines';

  @override
  String get navHistory => 'History';

  @override
  String get navProfile => 'Profile';

  @override
  String get deviceTitle => 'Device';

  @override
  String get deviceDisconnect => 'Disconnect';

  @override
  String get deviceConnected => 'Connected';

  @override
  String get deviceSearching => 'Searching...';

  @override
  String get deviceSearch => 'Search devices';

  @override
  String get deviceSearchHint =>
      'Searching for FTMS devices with service 0x1826...';

  @override
  String get deviceNoResults => 'No devices found';

  @override
  String get deviceNoResultsHint =>
      'Make sure the rower is on\nand Bluetooth is enabled';

  @override
  String get deviceBtOff => 'Bluetooth is off';

  @override
  String get deviceBtOffHint =>
      'Turn on Bluetooth from Control Center\nor Settings to search for the rower';

  @override
  String get deviceBtDenied => 'Bluetooth permission denied';

  @override
  String get deviceBtDeniedHint =>
      'Enable Bluetooth permission in\nSettings > Privacy > Bluetooth';

  @override
  String get deviceBtEnable => 'Enable Bluetooth';

  @override
  String get hrmTitle => 'Heart rate sensor';

  @override
  String get hrmNoSensor => 'No sensor';

  @override
  String get hrmWatchHint =>
      'A smartwatch needs an app that broadcasts heart rate over Bluetooth (e.g. Heart for Bluetooth on Wear OS).';

  @override
  String get hrmSearch => 'Search';

  @override
  String get hrmSearchOther => 'Search another';

  @override
  String get hrmSearching => 'Searching sensors…';

  @override
  String hrmConnectingTo(String name) {
    return 'Connecting to $name…';
  }

  @override
  String get hrmConnect => 'Connect';

  @override
  String get hrmDisconnect => 'Disconnect';

  @override
  String get hrmForget => 'Forget';

  @override
  String get hrmReconnecting => 'reconnecting…';

  @override
  String get hrmNotFound => 'not found';

  @override
  String get hrmUnknownSensor => 'Unknown sensor';

  @override
  String get hrmIncompatible =>
      'Not a compatible heart rate sensor (no Heart Rate service)';

  @override
  String hrmConnectError(String error) {
    return 'Connection error: $error';
  }

  @override
  String get hrmBpm => 'bpm';

  @override
  String get workoutTitle => 'Workout';

  @override
  String get workoutFree => 'Free workout';

  @override
  String get workoutRowerNotConnected => 'Connect the rower to start a workout';

  @override
  String get workoutOrPickRoutine => '  Or pick a routine:';

  @override
  String get workoutNoRoutines => 'Create a routine in the \"Routines\" tab';

  @override
  String get workoutInProgress => 'Workout in progress...';

  @override
  String get workoutScene => 'Scenery';

  @override
  String get sceneLake => 'Alpine lake';

  @override
  String get sceneRiver => 'City river';

  @override
  String get sceneCoast => 'Coast';

  @override
  String get sceneRegatta => 'Regatta course';

  @override
  String get workoutFinish => 'Finish';

  @override
  String get workoutFinishTitle => 'Finish workout';

  @override
  String get workoutFinishContent => 'The session will be saved. Continue?';

  @override
  String get workoutPause => 'Pause';

  @override
  String get workoutResume => 'Resume';

  @override
  String get workoutStartTitle => 'Start workout?';

  @override
  String workoutStartContent(String summary) {
    return '$summary\n\nStart the workout?';
  }

  @override
  String get workoutStart => 'Start';

  @override
  String get workoutCompleted => 'Workout Completed!';

  @override
  String get workoutCompletedMessage =>
      'You have successfully completed your routine.';

  @override
  String get metricTime => 'TIME';

  @override
  String get metricSplit => 'SPLIT 500m';

  @override
  String get metricDistance => 'DISTANCE';

  @override
  String get metricWatts => 'WATTS';

  @override
  String get metricSpm => 'SPM';

  @override
  String get metricCalories => 'CALORIES';

  @override
  String get metricHeartRate => 'HR';

  @override
  String get metricFreeLabel => 'Free workout';

  @override
  String get routinesTitle => 'Routines';

  @override
  String get routinesEmpty => 'No routines yet';

  @override
  String get routinesEmptyHint => 'Press + to create one';

  @override
  String get routineEdit => 'Edit';

  @override
  String get routineDelete => 'Delete';

  @override
  String get routineDeleteTitle => 'Delete routine';

  @override
  String routineDeleteContent(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty => 'No saved sessions';

  @override
  String get historyFree => 'Free';

  @override
  String get historyStatTime => 'Time';

  @override
  String get historyStatDistance => 'Distance';

  @override
  String get historyStatWatts => 'Watts';

  @override
  String get historyStatCalories => 'kcal';

  @override
  String get historyStatHeartRate => 'HR';

  @override
  String get sessionNoTelemetry => 'No telemetry data';

  @override
  String get sessionSummary => 'Summary';

  @override
  String get sessionStepBreakdown => 'Step Performance';

  @override
  String get sessionChartWatts => 'Watts';

  @override
  String get sessionChartSpm => 'SPM';

  @override
  String get sessionChartSplit => 'Split 500m';

  @override
  String get sessionChartDistance => 'Distance';

  @override
  String get sessionChartHr => 'HR';

  @override
  String get stepTypeWarmup => 'Warmup';

  @override
  String get stepTypeWork => 'Work';

  @override
  String get stepTypeRest => 'Rest';

  @override
  String get stepTypeCooldown => 'Cooldown';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get ok => 'OK';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get editorNewRoutine => 'New routine';

  @override
  String get editorEditRoutine => 'Edit routine';

  @override
  String get editorRoutineName => 'Routine name';

  @override
  String get editorDescription => 'Description (optional)';

  @override
  String editorStepsCount(int count) {
    return 'Steps ($count)';
  }

  @override
  String get editorStep => 'Step';

  @override
  String get editorSeries => 'Series';

  @override
  String get editorEmptySteps => 'No steps yet.\nPress \"Step\" or \"Series\".';

  @override
  String get editorDeleteSeries => 'Delete series';

  @override
  String get editorAddStepToSeries => 'Add step to series';

  @override
  String get editorRepetitions => 'Repetitions';

  @override
  String get editorAmount => 'Amount';

  @override
  String get editorNameEmpty => 'Name cannot be empty';

  @override
  String get editorNoSteps => 'Add at least one step';

  @override
  String get editorNewStep => 'New step';

  @override
  String get editorEditStep => 'Edit step';

  @override
  String get editorStepType => 'Type';

  @override
  String get editorByTime => 'By time';

  @override
  String get editorByDistance => 'By distance';

  @override
  String get editorMinutes => 'Min';

  @override
  String get editorSeconds => 'Sec';

  @override
  String get editorMeters => 'Meters';

  @override
  String get editorOptionalTargets => 'Optional targets';

  @override
  String get editorWattsMin => 'W min';

  @override
  String get editorWattsMax => 'W max';

  @override
  String get editorTargetSpm => 'Target SPM';

  @override
  String get editorSplitMin => 'Split min';

  @override
  String get editorSplitSec => 'Split sec';

  @override
  String get editorProgressions => 'Progressions (only applies to series)';

  @override
  String get editorProgressionSpm => 'SPM increment (+/rep)';

  @override
  String get editorProgressionSpmHint => 'e.g: 2';

  @override
  String get editorProgressionWatts => 'Watts increment (+/rep)';

  @override
  String get editorProgressionWattsHint => 'e.g: 5';

  @override
  String get editorProgressionSplit => 'Split change in seconds (+/-/rep)';

  @override
  String get editorProgressionSplitHint => 'e.g: -2 (faster)';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileConnectStrava => 'Connect with Strava';

  @override
  String get profileConnected => 'Connected';

  @override
  String get profileConnectedToStrava => 'Connected to Strava';

  @override
  String get profileDisconnect => 'Disconnect';

  @override
  String get profileDisconnectTitle => 'Disconnect Strava';

  @override
  String get profileDisconnectContent =>
      'Your sessions won\'t be uploaded automatically. Continue?';

  @override
  String get profileUploadSettings => 'Upload Settings';

  @override
  String get profileAutoUpload => 'Auto-upload';

  @override
  String get profileAutoUploadDesc =>
      'Upload sessions to Strava automatically after finishing';

  @override
  String get profileAskUpload => 'Ask me each time';

  @override
  String get profileAskUploadDesc => 'Show a dialog after each workout';

  @override
  String get profileManualUpload => 'Manual only';

  @override
  String get profileManualUploadDesc => 'Upload sessions manually from History';

  @override
  String get profileSync => 'Sync';

  @override
  String get profileSyncDesc => 'Download your rowing activities from Strava';

  @override
  String get profileSyncFromStrava => 'Sync from Strava';

  @override
  String get profileSyncToStrava => 'Sync to Strava';

  @override
  String get profileSyncing => 'Syncing...';

  @override
  String get profileUploading => 'Uploading...';

  @override
  String profileSyncResult(int count) {
    return '$count sessions synced';
  }

  @override
  String profileUploadResult(int count) {
    return '$count sessions uploaded';
  }

  @override
  String get profileSyncToDesc =>
      'Upload all unsynced local sessions to Strava';

  @override
  String get profilePendingUploads => 'Pending Uploads';

  @override
  String get profileUploadToStrava => 'Upload to Strava';

  @override
  String get profileUploadingToStrava => 'Uploading to Strava...';

  @override
  String get profileUploaded => 'Uploaded to Strava';

  @override
  String get profileUploadFailed => 'Upload failed';

  @override
  String get profileAskUploadDialog => 'Upload this session to Strava?';
}
