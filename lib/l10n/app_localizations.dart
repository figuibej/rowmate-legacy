import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @navDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get navDevice;

  /// No description provided for @navWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get navWorkout;

  /// No description provided for @navRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get navRoutines;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @deviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get deviceTitle;

  /// No description provided for @deviceDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get deviceDisconnect;

  /// No description provided for @deviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get deviceConnected;

  /// No description provided for @deviceSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get deviceSearching;

  /// No description provided for @deviceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search devices'**
  String get deviceSearch;

  /// No description provided for @deviceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Searching for FTMS devices with service 0x1826...'**
  String get deviceSearchHint;

  /// No description provided for @deviceNoResults.
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get deviceNoResults;

  /// No description provided for @deviceNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Make sure the rower is on\nand Bluetooth is enabled'**
  String get deviceNoResultsHint;

  /// No description provided for @deviceBtOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off'**
  String get deviceBtOff;

  /// No description provided for @deviceBtOffHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on Bluetooth from Control Center\nor Settings to search for the rower'**
  String get deviceBtOffHint;

  /// No description provided for @deviceBtDenied.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission denied'**
  String get deviceBtDenied;

  /// No description provided for @deviceBtDeniedHint.
  ///
  /// In en, this message translates to:
  /// **'Enable Bluetooth permission in\nSettings > Privacy > Bluetooth'**
  String get deviceBtDeniedHint;

  /// No description provided for @deviceBtEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Bluetooth'**
  String get deviceBtEnable;

  /// No description provided for @hrmTitle.
  ///
  /// In en, this message translates to:
  /// **'Heart rate sensor'**
  String get hrmTitle;

  /// No description provided for @hrmNoSensor.
  ///
  /// In en, this message translates to:
  /// **'No sensor'**
  String get hrmNoSensor;

  /// No description provided for @hrmWatchHint.
  ///
  /// In en, this message translates to:
  /// **'A smartwatch (Wear OS, Apple Watch) needs an app that broadcasts heart rate over Bluetooth, e.g. Heart for Bluetooth on Wear OS.'**
  String get hrmWatchHint;

  /// No description provided for @hrmSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get hrmSearch;

  /// No description provided for @hrmSearchOther.
  ///
  /// In en, this message translates to:
  /// **'Search another'**
  String get hrmSearchOther;

  /// No description provided for @hrmSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching for sensors...'**
  String get hrmSearching;

  /// No description provided for @hrmConnectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}...'**
  String hrmConnectingTo(String name);

  /// No description provided for @hrmConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get hrmConnect;

  /// No description provided for @hrmDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get hrmDisconnect;

  /// No description provided for @hrmForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get hrmForget;

  /// No description provided for @hrmReconnecting.
  ///
  /// In en, this message translates to:
  /// **'reconnecting...'**
  String get hrmReconnecting;

  /// No description provided for @hrmNotFound.
  ///
  /// In en, this message translates to:
  /// **'not found'**
  String get hrmNotFound;

  /// No description provided for @hrmUnknownSensor.
  ///
  /// In en, this message translates to:
  /// **'Unknown sensor'**
  String get hrmUnknownSensor;

  /// No description provided for @hrmIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Not a compatible heart rate sensor (no Heart Rate service)'**
  String get hrmIncompatible;

  /// No description provided for @hrmConnectError.
  ///
  /// In en, this message translates to:
  /// **'Connection error: {error}'**
  String hrmConnectError(String error);

  /// No description provided for @hrmBpm.
  ///
  /// In en, this message translates to:
  /// **'bpm'**
  String get hrmBpm;

  /// No description provided for @workoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workoutTitle;

  /// No description provided for @workoutFree.
  ///
  /// In en, this message translates to:
  /// **'Free workout'**
  String get workoutFree;

  /// No description provided for @workoutRowerNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Connect the rower to start a workout'**
  String get workoutRowerNotConnected;

  /// No description provided for @workoutOrPickRoutine.
  ///
  /// In en, this message translates to:
  /// **'  Or pick a routine:'**
  String get workoutOrPickRoutine;

  /// No description provided for @workoutNoRoutines.
  ///
  /// In en, this message translates to:
  /// **'Create a routine in the \"Routines\" tab'**
  String get workoutNoRoutines;

  /// No description provided for @workoutInProgress.
  ///
  /// In en, this message translates to:
  /// **'Workout in progress...'**
  String get workoutInProgress;

  /// No description provided for @workoutScene.
  ///
  /// In en, this message translates to:
  /// **'Scenery'**
  String get workoutScene;

  /// No description provided for @sceneLake.
  ///
  /// In en, this message translates to:
  /// **'Alpine lake'**
  String get sceneLake;

  /// No description provided for @sceneRiver.
  ///
  /// In en, this message translates to:
  /// **'City river'**
  String get sceneRiver;

  /// No description provided for @sceneCoast.
  ///
  /// In en, this message translates to:
  /// **'Coast'**
  String get sceneCoast;

  /// No description provided for @sceneRegatta.
  ///
  /// In en, this message translates to:
  /// **'Regatta course'**
  String get sceneRegatta;

  /// No description provided for @workoutFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get workoutFinish;

  /// No description provided for @workoutFinishTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish workout'**
  String get workoutFinishTitle;

  /// No description provided for @workoutFinishContent.
  ///
  /// In en, this message translates to:
  /// **'The session will be saved. Continue?'**
  String get workoutFinishContent;

  /// No description provided for @workoutPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get workoutPause;

  /// No description provided for @workoutResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get workoutResume;

  /// No description provided for @workoutStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Start workout?'**
  String get workoutStartTitle;

  /// No description provided for @workoutStartContent.
  ///
  /// In en, this message translates to:
  /// **'{summary}\n\nStart the workout?'**
  String workoutStartContent(String summary);

  /// No description provided for @workoutStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get workoutStart;

  /// No description provided for @workoutCompleted.
  ///
  /// In en, this message translates to:
  /// **'Workout Completed!'**
  String get workoutCompleted;

  /// No description provided for @workoutCompletedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have successfully completed your routine.'**
  String get workoutCompletedMessage;

  /// No description provided for @metricTime.
  ///
  /// In en, this message translates to:
  /// **'TIME'**
  String get metricTime;

  /// No description provided for @metricSplit.
  ///
  /// In en, this message translates to:
  /// **'SPLIT 500m'**
  String get metricSplit;

  /// No description provided for @metricDistance.
  ///
  /// In en, this message translates to:
  /// **'DISTANCE'**
  String get metricDistance;

  /// No description provided for @metricWatts.
  ///
  /// In en, this message translates to:
  /// **'WATTS'**
  String get metricWatts;

  /// No description provided for @metricSpm.
  ///
  /// In en, this message translates to:
  /// **'SPM'**
  String get metricSpm;

  /// No description provided for @metricCalories.
  ///
  /// In en, this message translates to:
  /// **'CALORIES'**
  String get metricCalories;

  /// No description provided for @metricHeartRate.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get metricHeartRate;

  /// No description provided for @metricFreeLabel.
  ///
  /// In en, this message translates to:
  /// **'Free workout'**
  String get metricFreeLabel;

  /// No description provided for @routinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get routinesTitle;

  /// No description provided for @routinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No routines yet'**
  String get routinesEmpty;

  /// No description provided for @routinesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Press + to create one'**
  String get routinesEmptyHint;

  /// No description provided for @routineEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get routineEdit;

  /// No description provided for @routineDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get routineDelete;

  /// No description provided for @routineDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete routine'**
  String get routineDeleteTitle;

  /// No description provided for @routineDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String routineDeleteContent(String name);

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved sessions'**
  String get historyEmpty;

  /// No description provided for @historyFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get historyFree;

  /// No description provided for @historyStatTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get historyStatTime;

  /// No description provided for @historyStatDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get historyStatDistance;

  /// No description provided for @historyStatWatts.
  ///
  /// In en, this message translates to:
  /// **'Watts'**
  String get historyStatWatts;

  /// No description provided for @historyStatCalories.
  ///
  /// In en, this message translates to:
  /// **'kcal'**
  String get historyStatCalories;

  /// No description provided for @historyStatHeartRate.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get historyStatHeartRate;

  /// No description provided for @sessionNoTelemetry.
  ///
  /// In en, this message translates to:
  /// **'No telemetry data'**
  String get sessionNoTelemetry;

  /// No description provided for @sessionSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get sessionSummary;

  /// No description provided for @sessionStepBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Step Performance'**
  String get sessionStepBreakdown;

  /// No description provided for @sessionChartWatts.
  ///
  /// In en, this message translates to:
  /// **'Watts'**
  String get sessionChartWatts;

  /// No description provided for @sessionChartSpm.
  ///
  /// In en, this message translates to:
  /// **'SPM'**
  String get sessionChartSpm;

  /// No description provided for @sessionChartSplit.
  ///
  /// In en, this message translates to:
  /// **'Split 500m'**
  String get sessionChartSplit;

  /// No description provided for @sessionChartDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get sessionChartDistance;

  /// No description provided for @sessionChartHr.
  ///
  /// In en, this message translates to:
  /// **'HR'**
  String get sessionChartHr;

  /// No description provided for @stepTypeWarmup.
  ///
  /// In en, this message translates to:
  /// **'Warmup'**
  String get stepTypeWarmup;

  /// No description provided for @stepTypeWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get stepTypeWork;

  /// No description provided for @stepTypeRest.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get stepTypeRest;

  /// No description provided for @stepTypeCooldown.
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get stepTypeCooldown;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @editorNewRoutine.
  ///
  /// In en, this message translates to:
  /// **'New routine'**
  String get editorNewRoutine;

  /// No description provided for @editorEditRoutine.
  ///
  /// In en, this message translates to:
  /// **'Edit routine'**
  String get editorEditRoutine;

  /// No description provided for @editorRoutineName.
  ///
  /// In en, this message translates to:
  /// **'Routine name'**
  String get editorRoutineName;

  /// No description provided for @editorDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get editorDescription;

  /// No description provided for @editorStepsCount.
  ///
  /// In en, this message translates to:
  /// **'Steps ({count})'**
  String editorStepsCount(int count);

  /// No description provided for @editorStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get editorStep;

  /// No description provided for @editorSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get editorSeries;

  /// No description provided for @editorEmptySteps.
  ///
  /// In en, this message translates to:
  /// **'No steps yet.\nPress \"Step\" or \"Series\".'**
  String get editorEmptySteps;

  /// No description provided for @editorDeleteSeries.
  ///
  /// In en, this message translates to:
  /// **'Delete series'**
  String get editorDeleteSeries;

  /// No description provided for @editorAddStepToSeries.
  ///
  /// In en, this message translates to:
  /// **'Add step to series'**
  String get editorAddStepToSeries;

  /// No description provided for @editorRepetitions.
  ///
  /// In en, this message translates to:
  /// **'Repetitions'**
  String get editorRepetitions;

  /// No description provided for @editorAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get editorAmount;

  /// No description provided for @editorNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get editorNameEmpty;

  /// No description provided for @editorNoSteps.
  ///
  /// In en, this message translates to:
  /// **'Add at least one step'**
  String get editorNoSteps;

  /// No description provided for @editorNewStep.
  ///
  /// In en, this message translates to:
  /// **'New step'**
  String get editorNewStep;

  /// No description provided for @editorEditStep.
  ///
  /// In en, this message translates to:
  /// **'Edit step'**
  String get editorEditStep;

  /// No description provided for @editorStepType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get editorStepType;

  /// No description provided for @editorByTime.
  ///
  /// In en, this message translates to:
  /// **'By time'**
  String get editorByTime;

  /// No description provided for @editorByDistance.
  ///
  /// In en, this message translates to:
  /// **'By distance'**
  String get editorByDistance;

  /// No description provided for @editorMinutes.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get editorMinutes;

  /// No description provided for @editorSeconds.
  ///
  /// In en, this message translates to:
  /// **'Sec'**
  String get editorSeconds;

  /// No description provided for @editorMeters.
  ///
  /// In en, this message translates to:
  /// **'Meters'**
  String get editorMeters;

  /// No description provided for @editorOptionalTargets.
  ///
  /// In en, this message translates to:
  /// **'Optional targets'**
  String get editorOptionalTargets;

  /// No description provided for @editorWattsMin.
  ///
  /// In en, this message translates to:
  /// **'W min'**
  String get editorWattsMin;

  /// No description provided for @editorWattsMax.
  ///
  /// In en, this message translates to:
  /// **'W max'**
  String get editorWattsMax;

  /// No description provided for @editorTargetSpm.
  ///
  /// In en, this message translates to:
  /// **'Target SPM'**
  String get editorTargetSpm;

  /// No description provided for @editorSplitMin.
  ///
  /// In en, this message translates to:
  /// **'Split min'**
  String get editorSplitMin;

  /// No description provided for @editorSplitSec.
  ///
  /// In en, this message translates to:
  /// **'Split sec'**
  String get editorSplitSec;

  /// No description provided for @editorProgressions.
  ///
  /// In en, this message translates to:
  /// **'Progressions (only applies to series)'**
  String get editorProgressions;

  /// No description provided for @editorProgressionSpm.
  ///
  /// In en, this message translates to:
  /// **'SPM increment (+/rep)'**
  String get editorProgressionSpm;

  /// No description provided for @editorProgressionSpmHint.
  ///
  /// In en, this message translates to:
  /// **'e.g: 2'**
  String get editorProgressionSpmHint;

  /// No description provided for @editorProgressionWatts.
  ///
  /// In en, this message translates to:
  /// **'Watts increment (+/rep)'**
  String get editorProgressionWatts;

  /// No description provided for @editorProgressionWattsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g: 5'**
  String get editorProgressionWattsHint;

  /// No description provided for @editorProgressionSplit.
  ///
  /// In en, this message translates to:
  /// **'Split change in seconds (+/-/rep)'**
  String get editorProgressionSplit;

  /// No description provided for @editorProgressionSplitHint.
  ///
  /// In en, this message translates to:
  /// **'e.g: -2 (faster)'**
  String get editorProgressionSplitHint;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileConnectStrava.
  ///
  /// In en, this message translates to:
  /// **'Connect with Strava'**
  String get profileConnectStrava;

  /// No description provided for @profileConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get profileConnected;

  /// No description provided for @profileConnectedToStrava.
  ///
  /// In en, this message translates to:
  /// **'Connected to Strava'**
  String get profileConnectedToStrava;

  /// No description provided for @profileDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get profileDisconnect;

  /// No description provided for @profileDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Strava'**
  String get profileDisconnectTitle;

  /// No description provided for @profileDisconnectContent.
  ///
  /// In en, this message translates to:
  /// **'Your sessions won\'t be uploaded automatically. Continue?'**
  String get profileDisconnectContent;

  /// No description provided for @profileUploadSettings.
  ///
  /// In en, this message translates to:
  /// **'Upload Settings'**
  String get profileUploadSettings;

  /// No description provided for @profileAutoUpload.
  ///
  /// In en, this message translates to:
  /// **'Auto-upload'**
  String get profileAutoUpload;

  /// No description provided for @profileAutoUploadDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload sessions to Strava automatically after finishing'**
  String get profileAutoUploadDesc;

  /// No description provided for @profileAskUpload.
  ///
  /// In en, this message translates to:
  /// **'Ask me each time'**
  String get profileAskUpload;

  /// No description provided for @profileAskUploadDesc.
  ///
  /// In en, this message translates to:
  /// **'Show a dialog after each workout'**
  String get profileAskUploadDesc;

  /// No description provided for @profileManualUpload.
  ///
  /// In en, this message translates to:
  /// **'Manual only'**
  String get profileManualUpload;

  /// No description provided for @profileManualUploadDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload sessions manually from History'**
  String get profileManualUploadDesc;

  /// No description provided for @profileSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get profileSync;

  /// No description provided for @profileSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Download your rowing activities from Strava'**
  String get profileSyncDesc;

  /// No description provided for @profileSyncFromStrava.
  ///
  /// In en, this message translates to:
  /// **'Sync from Strava'**
  String get profileSyncFromStrava;

  /// No description provided for @profileSyncToStrava.
  ///
  /// In en, this message translates to:
  /// **'Sync to Strava'**
  String get profileSyncToStrava;

  /// No description provided for @profileSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get profileSyncing;

  /// No description provided for @profileUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get profileUploading;

  /// No description provided for @profileSyncResult.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions synced'**
  String profileSyncResult(int count);

  /// No description provided for @profileUploadResult.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions uploaded'**
  String profileUploadResult(int count);

  /// No description provided for @profileSyncToDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload all unsynced local sessions to Strava'**
  String get profileSyncToDesc;

  /// No description provided for @profilePendingUploads.
  ///
  /// In en, this message translates to:
  /// **'Pending Uploads'**
  String get profilePendingUploads;

  /// No description provided for @profileUploadToStrava.
  ///
  /// In en, this message translates to:
  /// **'Upload to Strava'**
  String get profileUploadToStrava;

  /// No description provided for @profileUploadingToStrava.
  ///
  /// In en, this message translates to:
  /// **'Uploading to Strava...'**
  String get profileUploadingToStrava;

  /// No description provided for @profileUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded to Strava'**
  String get profileUploaded;

  /// No description provided for @profileUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get profileUploadFailed;

  /// No description provided for @profileAskUploadDialog.
  ///
  /// In en, this message translates to:
  /// **'Upload this session to Strava?'**
  String get profileAskUploadDialog;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
