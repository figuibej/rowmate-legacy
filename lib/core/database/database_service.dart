import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../dev/dev_config.dart';
import '../models/routine.dart';
import '../models/interval_step.dart';
import '../models/workout_session.dart';

/// Servicio de base de datos SQLite para rutinas y sesiones de entrenamiento
class DatabaseService {
  // El simulador usa su propia base para no mezclar sesiones de prueba con las reales
  static const _dbName = kSimulator ? 'rower_app_dev.db' : 'rower_app.db';
  static const _dbVersion = 7;
  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN target_split_seconds INTEGER',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN group_id TEXT',
      );
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN group_repeat_count INTEGER',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE data_points ADD COLUMN step_index INTEGER',
      );
      // Borrar sesiones anteriores que no tienen step_index
      await db.execute('DELETE FROM data_points');
      await db.execute('DELETE FROM workout_sessions');
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE data_points ADD COLUMN step_type TEXT',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE workout_sessions ADD COLUMN strava_activity_id TEXT',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN progression_spm INTEGER',
      );
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN progression_watts INTEGER',
      );
      await db.execute(
        'ALTER TABLE interval_steps ADD COLUMN progression_split_seconds INTEGER',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE routines (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at  TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE interval_steps (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        routine_id        INTEGER NOT NULL,
        step_order        INTEGER NOT NULL,
        type              TEXT NOT NULL,
        duration_seconds  INTEGER,
        distance_meters   INTEGER,
        target_watts_min  INTEGER,
        target_watts_max  INTEGER,
        target_spm            INTEGER,
        target_split_seconds  INTEGER,
        group_id              TEXT,
        group_repeat_count    INTEGER,
        progression_spm       INTEGER,
        progression_watts     INTEGER,
        progression_split_seconds INTEGER,
        FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_sessions (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        routine_id            INTEGER,
        routine_name          TEXT,
        started_at            TEXT NOT NULL,
        finished_at           TEXT,
        total_distance_meters INTEGER NOT NULL DEFAULT 0,
        total_time_seconds    INTEGER NOT NULL DEFAULT 0,
        avg_power_watts       INTEGER NOT NULL DEFAULT 0,
        avg_stroke_rate       REAL    NOT NULL DEFAULT 0,
        total_calories        INTEGER NOT NULL DEFAULT 0,
        strava_activity_id    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE data_points (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id        INTEGER NOT NULL,
        elapsed_seconds   INTEGER NOT NULL,
        stroke_rate       REAL    NOT NULL DEFAULT 0,
        stroke_count      INTEGER NOT NULL DEFAULT 0,
        distance_meters   INTEGER NOT NULL DEFAULT 0,
        pace_500m_seconds INTEGER NOT NULL DEFAULT 0,
        power_watts       INTEGER NOT NULL DEFAULT 0,
        calories          INTEGER NOT NULL DEFAULT 0,
        heart_rate        INTEGER NOT NULL DEFAULT 0,
        step_index        INTEGER,
        step_type         TEXT,
        FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
      )
    ''');
  }

  // ─── Rutinas ─────────────────────────────────────────────────────────────

  Future<List<Routine>> getRoutines() async {
    final db = await database;
    final rows = await db.query('routines', orderBy: 'created_at DESC');
    final routines = <Routine>[];
    for (final row in rows) {
      final steps = await getStepsForRoutine(row['id'] as int);
      routines.add(Routine.fromMap(row, steps: steps));
    }
    return routines;
  }

  Future<Routine> insertRoutine(Routine routine) async {
    final db = await database;
    final id = await db.insert('routines', routine.toMap());
    final steps = <IntervalStep>[];
    for (var i = 0; i < routine.steps.length; i++) {
      final step = await _insertStep(db, routine.steps[i].copyWith(routineId: id, order: i));
      steps.add(step);
    }
    return routine.copyWith(id: id, steps: steps);
  }

  Future<Routine> updateRoutine(Routine routine) async {
    final db = await database;
    await db.update(
      'routines',
      routine.toMap(),
      where: 'id = ?',
      whereArgs: [routine.id],
    );
    // Reemplaza todos los pasos
    await db.delete('interval_steps', where: 'routine_id = ?', whereArgs: [routine.id]);
    final steps = <IntervalStep>[];
    for (var i = 0; i < routine.steps.length; i++) {
      final step = await _insertStep(db, routine.steps[i].copyWith(routineId: routine.id, order: i));
      steps.add(step);
    }
    return routine.copyWith(steps: steps);
  }

  Future<void> deleteRoutine(int id) async {
    final db = await database;
    await db.delete('routines', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Pasos de rutina ─────────────────────────────────────────────────────

  Future<List<IntervalStep>> getStepsForRoutine(int routineId) async {
    final db = await database;
    final rows = await db.query(
      'interval_steps',
      where: 'routine_id = ?',
      whereArgs: [routineId],
      orderBy: 'step_order ASC',
    );
    return rows.map(IntervalStep.fromMap).toList();
  }

  Future<IntervalStep> _insertStep(Database db, IntervalStep step) async {
    final id = await db.insert('interval_steps', step.toMap());
    return step.copyWith(id: id);
  }

  Future<Routine?> getRoutineById(int id) async {
    final db = await database;
    final rows = await db.query('routines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final steps = await getStepsForRoutine(id);
    return Routine.fromMap(rows.first, steps: steps);
  }

  // ─── Sesiones ─────────────────────────────────────────────────────────────

  Future<int> insertSession(WorkoutSession session) async {
    final db = await database;
    return db.insert('workout_sessions', session.toMap());
  }

  Future<void> updateSession(WorkoutSession session) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> updateSessionStravaId(int sessionId, String stravaActivityId) async {
    final db = await database;
    await db.update(
      'workout_sessions',
      {'strava_activity_id': stravaActivityId},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<WorkoutSession?> getSessionById(int id) async {
    final db = await database;
    final rows = await db.query('workout_sessions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return WorkoutSession.fromMap(rows.first);
  }

  Future<List<WorkoutSession>> getSessions() async {
    final db = await database;
    final rows = await db.query('workout_sessions', orderBy: 'started_at DESC');
    return rows.map(WorkoutSession.fromMap).toList();
  }

  Future<void> insertDataPoints(List<DataPoint> points) async {
    final db = await database;
    final batch = db.batch();
    for (final p in points) {
      batch.insert('data_points', p.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<DataPoint>> getDataPointsForSession(int sessionId) async {
    final db = await database;
    final rows = await db.query(
      'data_points',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'elapsed_seconds ASC',
    );
    return rows
        .map((r) => DataPoint(
              id: r['id'] as int?,
              sessionId: r['session_id'] as int,
              elapsedSeconds: r['elapsed_seconds'] as int,
              strokeRate: (r['stroke_rate'] as num).toDouble(),
              strokeCount: r['stroke_count'] as int,
              distanceMeters: r['distance_meters'] as int,
              pace500mSeconds: r['pace_500m_seconds'] as int,
              powerWatts: r['power_watts'] as int,
              calories: r['calories'] as int,
              heartRate: r['heart_rate'] as int,
            stepIndex: r['step_index'] as int?,
            stepType: r['step_type'] as String?,
          ))
        .toList();
  }

  Future<Map<int, SessionStats>> getStatsForSessions(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return {};
    final db = await database;
    final placeholders = sessionIds.map((_) => '?').join(',');
    final rows = await db.query(
      'data_points',
      columns: [
        'session_id', 'power_watts', 'stroke_rate',
        'pace_500m_seconds', 'distance_meters', 'elapsed_seconds', 'calories',
      ],
      where: 'session_id IN ($placeholders)',
      whereArgs: sessionIds,
    );

    final grouped = <int, List<DataPoint>>{};
    for (final row in rows) {
      final sid = row['session_id'] as int;
      grouped.putIfAbsent(sid, () => []).add(DataPoint(
        sessionId: sid,
        elapsedSeconds: row['elapsed_seconds'] as int,
        strokeRate: (row['stroke_rate'] as num).toDouble(),
        distanceMeters: row['distance_meters'] as int,
        pace500mSeconds: row['pace_500m_seconds'] as int,
        powerWatts: row['power_watts'] as int,
        calories: row['calories'] as int,
      ));
    }

    return grouped.map(
      (sid, points) => MapEntry(sid, SessionStats.compute(points)),
    );
  }

  /// Elimina todas las sesiones descargadas de Strava (para re-sincronizar)
  Future<void> deleteStravaSessions() async {
    final db = await database;
    // Primero eliminar los data points de las sesiones de Strava
    await db.execute('''
      DELETE FROM data_points
      WHERE session_id IN (
        SELECT id FROM workout_sessions
        WHERE strava_activity_id IS NOT NULL
      )
    ''');
    // Luego eliminar las sesiones de Strava
    await db.delete('workout_sessions', where: 'strava_activity_id IS NOT NULL');
  }

  Future<void> close() async => _db?.close();
}
