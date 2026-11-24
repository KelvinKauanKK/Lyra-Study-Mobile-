import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../core/city/engine.dart';
import '../core/exam.dart';
import '../core/tasks.dart';

class SessionsData {
  final Map<String, Map<String, int>> byDay = {};
  final Set<String> simulated = {};
}

/// Camada SQLite. O esquema vem de assets/db/schema.sql (o MESMO arquivo que tools/export_mobile.py usa na migração do desktop).
/// Chaves estrangeiras ligadas (ON DELETE CASCADE nos simulados) e escritas por transação onde há várias tabelas.
class AppDatabase {
  AppDatabase._(this.db, this.dir);
  final Database db;
  final String dir; // documentos do app: lyra.db e anexos/ ficam aqui
  static const schemaVersion = 1;

  static Future<AppDatabase> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final schema = await rootBundle.loadString('assets/db/schema.sql');
    final db = await openDatabase(p.join(docs.path, 'lyra.db'),
        version: schemaVersion,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (d, v) async {
          for (final stmt in _statements(schema)) {
            await d.execute(stmt);
          }
          await d.insert('kv', {'k': 'schema_version', 'v': '$schemaVersion'});
        });
    return AppDatabase._(db, docs.path);
  }

  static List<String> _statements(String sql) =>
      sql.split('\n').where((l) => !l.trim().startsWith('--')).join('\n').split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  // ---------- kv ----------
  Future<Map<String, String>> loadKv() async {
    final rows = await db.query('kv');
    return {for (final r in rows) r['k'] as String: r['v'] as String};
  }

  Future<void> setKv(String k, String v) async {
    await db.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- matérias, sessões, tarefas ----------
  Future<Map<String, int>> loadSubjects() async {
    final rows = await db.query('subjects', orderBy: 'position, rowid');
    return {for (final r in rows) r['name'] as String: (r['difficulty'] as num).toInt()};
  }

  Future<void> replaceSubjects(Map<String, int> subjects) async {
    await db.transaction((txn) async {
      await txn.delete('subjects');
      var i = 0;
      for (final e in subjects.entries) {
        await txn.insert('subjects', {'name': e.key, 'difficulty': e.value, 'position': i++});
      }
    });
  }

  Future<SessionsData> loadSessions() async {
    final out = SessionsData();
    for (final r in await db.query('sessions')) {
      final day = r['day'] as String;
      out.byDay.putIfAbsent(day, () => {})[r['subject'] as String] = (r['minutes'] as num).toInt();
      if ((r['simulated'] as num) != 0) out.simulated.add(day);
    }
    return out;
  }

  Future<void> putSession(String day, String subject, int minutes, {bool simulated = false}) async {
    await db.insert('sessions', {'day': day, 'subject': subject, 'minutes': minutes, 'simulated': simulated ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSimulatedSessions({String? after}) async {
    await db.delete('sessions', where: after == null ? 'simulated = 1' : 'simulated = 1 AND day > ?', whereArgs: after == null ? null : [after]);
  }

  Future<List<CustomTask>> loadTasks() async {
    final rows = await db.query('custom_tasks', orderBy: 'day, at_time');
    return [for (final r in rows) CustomTask(r['id'] as String, r['day'] as String, r['title'] as String, r['at_time'] as String)];
  }

  Future<void> putTask(CustomTask t) async {
    await db.insert('custom_tasks', {'id': t.id, 'day': t.day, 'title': t.title, 'at_time': t.time}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTask(String id) async {
    await db.delete('custom_tasks', where: 'id = ?', whereArgs: [id]);
    await db.delete('todo_done', where: 'k = ?', whereArgs: ['task:$id']);
  }

  Future<Set<String>> loadTodo() async => {for (final r in await db.query('todo_done')) r['k'] as String};

  Future<void> setTodo(String key, bool done) async {
    if (done) {
      await db.insert('todo_done', {'k': key}, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete('todo_done', where: 'k = ?', whereArgs: [key]);
    }
  }

  // ---------- simulados ----------
  Future<List<Exam>> loadExams() async {
    final out = <Exam>[];
    for (final r in await db.query('exams', orderBy: 'day, rowid')) {
      final id = r['id'] as String;
      final subs = <String, ExamSubject>{};
      for (final s in await db.query('exam_subjects', where: 'exam_id = ?', whereArgs: [id], orderBy: 'rowid')) {
        subs[s['subject'] as String] = ExamSubject(
            hits: (s['hits'] as num).toInt(), total: (s['total'] as num).toInt(), origHits: (s['orig_hits'] as num).toInt(), origTotal: (s['orig_total'] as num).toInt(),
            annulled: (s['annulled'] as num).toInt(), annulledHit: (s['annulled_hit'] as num).toInt(), score: (s['score'] as num).toDouble(), weight: (s['weight'] as num).toDouble());
      }
      final atts = [
        for (final a in await db.query('attachments', where: 'exam_id = ?', whereArgs: [id], orderBy: 'id')) Attachment(a['name'] as String, a['file'] as String, (a['size'] as num).toInt())
      ];
      out.add(Exam(
          id: id, name: r['name'] as String, day: r['day'] as String, maxQ: (r['max_q'] as num).toInt(), hits: (r['hits'] as num).toInt(), scale: (r['scale'] as num).toInt(),
          annulled: (r['annulled'] as num).toInt(), score10: (r['score10'] as num).toDouble(), weighted: (r['weighted'] as num) != 0, cityYear: (r['city_year'] as num).toInt(),
          subjects: subs, attachments: atts));
    }
    return out;
  }

  Future<void> putExam(Exam e) async {
    await db.transaction((txn) async {
      await txn.insert('exams', {
        'id': e.id, 'name': e.name, 'day': e.day, 'max_q': e.maxQ, 'hits': e.hits, 'scale': e.scale, 'annulled': e.annulled,
        'score10': e.score10, 'weighted': e.weighted ? 1 : 0, 'city_year': e.cityYear,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('exam_subjects', where: 'exam_id = ?', whereArgs: [e.id]);
      await txn.delete('attachments', where: 'exam_id = ?', whereArgs: [e.id]);
      for (final en in e.subjects.entries) {
        final s = en.value;
        await txn.insert('exam_subjects', {
          'exam_id': e.id, 'subject': en.key, 'hits': s.hits, 'total': s.total, 'orig_hits': s.origHits, 'orig_total': s.origTotal,
          'annulled': s.annulled, 'annulled_hit': s.annulledHit, 'score': s.score, 'weight': s.weight,
        });
      }
      for (final a in e.attachments) {
        await txn.insert('attachments', {'exam_id': e.id, 'name': a.name, 'file': a.file, 'size': a.size});
      }
    });
  }

  Future<void> deleteExam(String id) async {
    await db.delete('exams', where: 'id = ?', whereArgs: [id]); // ON DELETE CASCADE remove matérias e anexos (os arquivos são apagados pelo AppState)
  }

  // ---------- cidade ----------
  Future<List<Tile>> loadTiles() async {
    final rows = await db.query('city_tiles', orderBy: 'idx');
    return [for (final r in rows) Tile(b: r['building'] as String?, lv: (r['level'] as num).toInt(), xp: (r['xp'] as num).toDouble(), date: r['day'] as String, m: (r['minutes'] as num).toInt())];
  }

  Future<void> putTiles(Map<int, Tile> tiles) async {
    final b = db.batch();
    tiles.forEach((i, t) => b.insert('city_tiles', {'idx': i, 'building': t.b, 'level': t.lv, 'xp': t.xp, 'day': t.date, 'minutes': t.m}, conflictAlgorithm: ConflictAlgorithm.replace));
    await b.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> loadHistory() async {
    final rows = await db.query('city_history', orderBy: 'year');
    return [for (final r in rows) Map<String, dynamic>.from(jsonDecode(r['data'] as String) as Map)];
  }

  Future<void> putHistory(int year, String completedOn, Map<String, dynamic> data) async {
    await db.insert('city_history', {'year': year, 'completed_on': completedOn, 'data': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, List<int>>> loadPerms() async {
    final rows = await db.query('layout_perm');
    return {for (final r in rows) r['k'] as String: List<int>.from(jsonDecode(r['perm'] as String) as List)};
  }

  Future<void> putPerm(String key, List<int> perm) async {
    await db.insert('layout_perm', {'k': key, 'perm': jsonEncode(perm)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Zera só a cidade (tiles, histórico e posições). Sessões, simulados e anexos NÃO são tocados.
  Future<void> clearCity() async {
    await db.transaction((txn) async {
      await txn.delete('city_tiles');
      await txn.delete('city_history');
      await txn.delete('layout_perm');
      await txn.delete('kv', where: 'k = ?', whereArgs: ['city']);
    });
  }
}
