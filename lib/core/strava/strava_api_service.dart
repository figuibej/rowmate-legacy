import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../dev/dev_config.dart';
import '../models/workout_session.dart';
import '../models/interval_step.dart';
import 'strava_auth_service.dart';
import 'strava_config.dart';
import 'tcx_builder.dart';
import 'strava_metadata.dart';

/// Resultado de una actividad de Strava (para sync/download)
class StravaActivity {
  final int stravaId;
  final String name;
  final String sportType;
  final DateTime startDate;
  final int elapsedTime;
  final double distance;
  final int? calories;

  const StravaActivity({
    required this.stravaId,
    required this.name,
    required this.sportType,
    required this.startDate,
    required this.elapsedTime,
    required this.distance,
    this.calories,
  });

  factory StravaActivity.fromJson(Map<String, dynamic> json) => StravaActivity(
    stravaId: json['id'] as int,
    name: json['name'] as String? ?? '',
    sportType: json['sport_type'] as String? ?? '',
    startDate: DateTime.parse(json['start_date'] as String),
    elapsedTime: json['elapsed_time'] as int? ?? 0,
    distance: (json['distance'] as num?)?.toDouble() ?? 0,
    calories: json['calories'] as int?,
  );
}

/// Streams de telemetría descargados de Strava
class StravaStreams {
  final List<int> time;
  final List<int> watts;
  final List<double> cadence;
  final List<int> heartRate;
  final List<double> distance;

  const StravaStreams({
    required this.time,
    required this.watts,
    required this.cadence,
    required this.heartRate,
    required this.distance,
  });
}

/// Comunicación con la API REST de Strava v3
class StravaApiService {
  final StravaAuthService _auth;

  StravaApiService(this._auth);

  Future<Map<String, String>> get _headers async {
    final token = await _auth.getAccessToken();
    return {'Authorization': 'Bearer $token'};
  }

  // ─── Upload ────────────────────────────────────────────────────────────

  /// Sube una sesión a Strava como archivo TCX con metadata de intervalos.
  /// Retorna el strava activity ID o null si falla.
  Future<String?> uploadActivity(
    WorkoutSession session,
    List<DataPoint> points, {
    List<IntervalStep>? steps,
    String? description,
  }) async {
    if (kSimulator) {
      debugPrint('[Strava] Modo simulador: subida bloqueada (sesión ${session.id})');
      return null;
    }

    final token = await _auth.getAccessToken();
    if (token == null) {
      debugPrint('[Strava] Upload failed: no access token');
      return null;
    }

    final tcx = TcxBuilder.build(session, points, steps: steps, description: description);
    final name = session.routineName ?? 'RowMate Session';

    debugPrint('[Strava] Uploading session ${session.id} "$name" (${points.length} data points)');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${StravaConfig.apiBase}/uploads'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['data_type'] = 'tcx';
    request.fields['sport_type'] = 'Rowing';
    request.fields['name'] = name;
    request.fields['trainer'] = '1'; // indoor
    request.fields['external_id'] = 'rowmate_${session.id}';

    request.files.add(http.MultipartFile.fromString(
      'file',
      tcx,
      filename: 'rowmate_${session.id}.tcx',
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    debugPrint('[Strava] Upload POST status: ${response.statusCode}');
    debugPrint('[Strava] Upload POST body: ${response.body}');

    if (response.statusCode != 201) {
      debugPrint('[Strava] Upload failed with status ${response.statusCode}');
      return null;
    }

    final uploadData = json.decode(response.body) as Map<String, dynamic>;
    final uploadId = uploadData['id'];

    // Poll hasta que el upload se procese
    return _pollUpload(uploadId, token);
  }

  Future<String?> _pollUpload(dynamic uploadId, String token) async {
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));

      final response = await http.get(
        Uri.parse('${StravaConfig.apiBase}/uploads/$uploadId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        debugPrint('[Strava] Poll status: ${response.statusCode}');
        continue;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final activityId = data['activity_id'];
      final status = data['status'] as String?;
      final error = data['error'] as String?;

      debugPrint('[Strava] Poll #$i: status=$status, activityId=$activityId, error=$error');

      if (activityId != null) return '$activityId';

      if (error != null && error.isNotEmpty) {
        // Handle duplicate: Strava returns "...duplicate of activity XXXXX"
        final dupMatch = RegExp(r'duplicate of activity (\d+)').firstMatch(error);
        if (dupMatch != null) {
          final existingId = dupMatch.group(1)!;
          debugPrint('[Strava] Duplicate detected, using existing activity $existingId');
          return existingId;
        }
        debugPrint('[Strava] Upload processing error: $error');
        return null;
      }
    }
    debugPrint('[Strava] Poll timed out after 30 seconds');
    return null;
  }

  // ─── Download / Sync ──────────────────────────────────────────────────

  /// Lista actividades de rowing del atleta
  Future<List<StravaActivity>> getRowingActivities({
    DateTime? after,
    int page = 1,
    int perPage = 50,
  }) async {
    final headers = await _headers;
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    if (after != null) {
      params['after'] = '${after.millisecondsSinceEpoch ~/ 1000}';
    }

    final uri = Uri.parse('${StravaConfig.apiBase}/athlete/activities')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: headers);

    if (response.statusCode != 200) return [];

    final list = json.decode(response.body) as List;
    return list
        .map((e) => StravaActivity.fromJson(e as Map<String, dynamic>))
        .where((a) => a.sportType == 'Rowing' || a.sportType == 'VirtualRow')
        .toList();
  }

  /// Descarga los streams de telemetría de una actividad
  Future<StravaStreams?> getActivityStreams(int activityId) async {
    final headers = await _headers;
    final uri = Uri.parse(
      '${StravaConfig.apiBase}/activities/$activityId/streams'
      '?keys=time,watts,cadence,heartrate,distance'
      '&key_by_type=true',
    );
    final response = await http.get(uri, headers: headers);

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;

    List<T> extractStream<T>(String key, T defaultVal) {
      final stream = data[key] as Map<String, dynamic>?;
      if (stream == null) return [];
      final values = stream['data'] as List?;
      if (values == null) return [];
      return values.map((v) => v is T ? v : defaultVal).toList();
    }

    final time = extractStream<int>('time', 0);
    if (time.isEmpty) return null;

    return StravaStreams(
      time: time,
      watts: extractStream<int>('watts', 0),
      cadence: (data['cadence'] as Map<String, dynamic>?)?['data'] != null
          ? ((data['cadence'] as Map<String, dynamic>)['data'] as List)
              .map((v) => (v as num).toDouble())
              .toList()
          : List.filled(time.length, 0.0),
      heartRate: extractStream<int>('heartrate', 0),
      distance: (data['distance'] as Map<String, dynamic>?)?['data'] != null
          ? ((data['distance'] as Map<String, dynamic>)['data'] as List)
              .map((v) => (v as num).toDouble())
              .toList()
          : List.filled(time.length, 0.0),
    );
  }

  /// Obtiene detalles completos de una actividad (descripción y laps)
  Future<StravaActivityDetails?> getActivityDetails(int activityId) async {
    final headers = await _headers;
    final uri = Uri.parse('${StravaConfig.apiBase}/activities/$activityId');
    final response = await http.get(uri, headers: headers);

    if (response.statusCode != 200) return null;

    final data = json.decode(response.body) as Map<String, dynamic>;
    final description = data['description'] as String?;
    final lapsData = data['laps'] as List?;

    final laps = lapsData
        ?.map((l) => StravaLap.fromJson(l as Map<String, dynamic>))
        .toList() ?? [];

    return StravaActivityDetails(
      description: description,
      laps: laps,
      metadata: StravaMetadata.decode(description),
    );
  }
}

/// Detalles extendidos de una actividad de Strava
class StravaActivityDetails {
  final String? description;
  final List<StravaLap> laps;
  final StravaMetadata? metadata;

  const StravaActivityDetails({
    this.description,
    required this.laps,
    this.metadata,
  });
}

/// Un lap de Strava
class StravaLap {
  final int id;
  final int startIndex; // índice en los streams donde empieza este lap
  final int endIndex;   // índice en los streams donde termina
  final int elapsedTime;
  final double distance;

  const StravaLap({
    required this.id,
    required this.startIndex,
    required this.endIndex,
    required this.elapsedTime,
    required this.distance,
  });

  factory StravaLap.fromJson(Map<String, dynamic> json) => StravaLap(
    id: json['id'] as int,
    startIndex: json['start_index'] as int? ?? 0,
    endIndex: json['end_index'] as int? ?? 0,
    elapsedTime: json['elapsed_time'] as int? ?? 0,
    distance: (json['distance'] as num?)?.toDouble() ?? 0,
  );
}
