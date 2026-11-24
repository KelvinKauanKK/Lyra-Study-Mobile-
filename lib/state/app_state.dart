import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import '../core/analysis.dart';
import '../core/city/catalog.dart';
import '../core/city/engine.dart';
import '../core/city/layout.dart';
import '../core/city/traffic.dart';
import '../core/clock.dart';
import '../core/economy.dart';
import '../core/exam.dart';
import '../core/schedule.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import '../data/database.dart';
import 'admin_secret.dart';

class DbPermStore implements PermStore {
  DbPermStore(this.db);
  final AppDatabase db;
  final Map<String, List<int>> data = {};
  @override
  List<int>? getPerm(String key) => data[key];
  @override
  void putPerm(String key, List<int> perm) {
    data[key] = perm;
    db.putPerm(key, perm); // grava sem bloquear o desenho
  }
}

/// Estado central do app (Provider). Toda regra de negócio vive em lib/core; aqui só há persistência e orquestração.
class AppState extends ChangeNotifier {
  AppState(this.db) : perms = DbPermStore(db);
  final AppDatabase db;
  final DbPermStore perms;
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  final Traffic traffic = Traffic();
  final Map<String, ui.Image> images = {};
  late Catalog catalog;
  late Layout layout;
  late CityEngine city;

  Map<String, int> subjects = {};
  double dailyGoalH = 2.0;
  int perDay = 2;
  Map<String, List<StudyTask>> schedule = {};
  final Map<String, Map<String, int>> sessions = {}; // dia -> matéria -> minutos (o total do dia é a soma; "Geral" = Estudo Geral)
  final Set<String> simDays = {};
  int points = 0;
  Map<String, int> dayPaid = {};
  List<String> weeklyPaid = [];
  List<CustomTask> tasks = [];
  final Set<String> todoDone = {};
  List<Exam> exams = [];
  bool admin = false;
  int _savedD = -1, _savedHist = 0;

  // ---------- inicialização ----------
  Future<void> init() async {
    final kv = await db.loadKv();
    catalog = Catalog.fromJson(await rootBundle.loadString('assets/city/buildings.json'), await rootBundle.loadString('assets/city/meta.json'));
    await _loadImages();
    points = int.parse(kv['points'] ?? '0');
    dailyGoalH = double.parse(kv['daily_goal_h'] ?? '2.0');
    perDay = int.parse(kv['per_day'] ?? '2');
    dayPaid = {for (final e in (jsonDecode(kv['day_paid'] ?? '{}') as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()};
    weeklyPaid = List<String>.from(jsonDecode(kv['weekly_paid'] ?? '[]') as List);
    AppClock.offsetDays = int.parse(kv['admin_offset'] ?? '0');
    subjects = await db.loadSubjects();
    final sd = await db.loadSessions();
    sessions
      ..clear()
      ..addAll(sd.byDay);
    simDays
      ..clear()
      ..addAll(sd.simulated);
    schedule = buildSchedule(subjects, dailyGoalH, perDay);
    tasks = await db.loadTasks();
    todoDone.addAll(await db.loadTodo());
    exams = await db.loadExams();
    final cs = CityState(Random().nextInt(1 << 30) + 1);
    if (kv['city'] != null) cs.loadMeta(jsonDecode(kv['city']!) as Map<String, dynamic>);
    cs.t.addAll(await db.loadTiles());
    cs.history.addAll(await db.loadHistory());
    perms.data.addAll(await db.loadPerms());
    _savedHist = cs.history.length;
    _buildCity(cs);
    _syncDays();
    traffic.sync(city);
    await _persistCity();
  }

  void _buildCity(CityState cs) {
    layout = Layout(perms, cs.seed);
    city = CityEngine(cs, catalog, layout, goalMin: goalMin, studiedOn: studiedOn, cycleHours: cycleHours);
  }

  Future<void> _loadImages() async {
    for (final key in catalog.meta.keys) {
      try {
        final data = await rootBundle.load('assets/city/$key.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        images[key] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
  }

  /// Ao abrir: dias passados com a meta batida viram quadrados (sem animações).
  void _syncDays() {
    final g = goalMin();
    final days = sessions.keys.toList()..sort();
    for (final iso in days) {
      final total = sessions[iso]!.values.fold<int>(0, (a, b) => a + b);
      if (g > 0 && !city.s.counted.contains(iso) && total >= g) {
        city.s.counted.add(iso);
        city.addDay(quiet: true, today: parseIso(iso));
      }
    }
    city.checkPlazas(AppClock.today());
    city.touch();
  }

  // ---------- consultas ----------
  int goalMin() => (dailyGoalH * 60).toInt();
  int studiedOn(DateTime d) => sessions[isoDate(d)]?.values.fold<int>(0, (a, b) => a + b) ?? 0;
  int generalOn(DateTime d) => sessions[isoDate(d)]?['Geral'] ?? 0; // Estudo Geral conta direto para a Meta do Dia
  double cycleHours(String key) {
    var t = 0;
    sessions.forEach((day, m) {
      if (day.startsWith(key)) t += m.values.fold<int>(0, (a, b) => a + b);
    });
    return t / 60;
  }

  DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  int weekMinutes(DateTime d) {
    final mon = weekStart(d);
    var t = 0;
    for (var i = 0; i < 7; i++) {
      t += studiedOn(DateTime(mon.year, mon.month, mon.day + i));
    }
    return t;
  }

  void say(String text) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  // ---------- pontos e estudo ----------
  /// Registra minutos e credita os pontos pela META (diária + bônus semanal). Retorna [pontos creditados, bônus semanal].
  List<int> addMinutes(DateTime day, int minutes, String subject) {
    final iso = isoDate(day);
    final m = sessions.putIfAbsent(iso, () => {});
    final before = m.values.fold<int>(0, (a, b) => a + b);
    m[subject] = (m[subject] ?? 0) + minutes;
    final g = goalMin();
    final due = Economy.due(before + minutes, g); // total devido no dia; só a diferença para o já pago é creditada (sem erro de arredondamento)
    final gain = max(0, due - (dayPaid[iso] ?? 0));
    dayPaid[iso] = max(dayPaid[iso] ?? 0, due);
    if (dayPaid.length > 400) {
      final keys = dayPaid.keys.toList()..sort();
      for (final k in keys.take(dayPaid.length - 400)) {
        dayPaid.remove(k);
      }
    }
    var bonus = 0;
    final wk = isoDate(weekStart(day));
    if (g > 0 && !weeklyPaid.contains(wk) && weekMinutes(day) >= g * 7) {
      weeklyPaid.add(wk);
      bonus = Economy.weeklyBonus;
    }
    points += gain + bonus;
    db.putSession(iso, subject, m[subject]!);
    _persistMoney();
    return [gain + bonus, bonus];
  }

  /// Chamado pelo cronômetro a cada minuto de foco concluído.
  Future<void> addMinute(String subject) async {
    final today = AppClock.today();
    final r = addMinutes(today, 1, subject);
    if (r[1] > 0) say('🎁 Meta da semana batida: +${r[1]} pontos');
    await _applyCity(city.study(1, today: today));
  }

  Future<void> _persistMoney() async {
    await db.setKv('points', '$points');
    await db.setKv('day_paid', jsonEncode(dayPaid));
    await db.setKv('weekly_paid', jsonEncode(weeklyPaid));
  }

  // ---------- cidade ----------
  Future<void> _applyCity(List<CityEvent> ev) async {
    String? msg;
    for (final e in ev) {
      if (e.type == 'toast' || e.type == 'merge') msg = e.text;
    }
    if (msg != null) say(msg);
    traffic.sync(city);
    await _persistCity();
    notifyListeners();
  }

  Future<void> _persistCity() async {
    final s = city.s;
    final upd = <int, Tile>{};
    if (s.d != _savedD) {
      for (var i = 0; i < s.t.length; i++) {
        upd[i] = s.t[i];
      }
    } else {
      for (var i = max(0, s.t.length - 4); i < s.t.length; i++) {
        upd[i] = s.t[i];
      }
      if (s.focus >= 0 && s.focus < s.t.length) upd[s.focus] = s.t[s.focus];
    }
    await db.putTiles(upd);
    _savedD = s.d;
    for (var i = _savedHist; i < s.history.length; i++) {
      final h = s.history[i];
      await db.putHistory((h['year'] as num).toInt(), h['date'] as String, h);
    }
    _savedHist = s.history.length;
    await db.setKv('city', jsonEncode(s.metaJson()));
  }

  Future<void> cityChanged() async {
    city.touch();
    traffic.sync(city);
    await _persistCity();
    notifyListeners();
  }

  Future<void> buildAt(int i, [String? id]) async => _applyCity(city.build(i, id));

  Future<bool> buy(String kind, String id) async {
    final own = kind == 'b' ? city.s.ob : city.s.oc;
    final price = kind == 'b' ? catalog.building(id).price : catalog.car(id).price;
    if (own.contains(id) || points < price) return false;
    points -= price;
    own.add(id);
    await _persistMoney();
    say('🛒 ${kind == 'b' ? catalog.building(id).name : catalog.car(id).name} adquirido!');
    await cityChanged();
    return true;
  }

  // ---------- cronograma, tarefas e lembretes ----------
  Future<void> configureSchedule(Map<String, int> subs, double hours, int perDayN) async {
    subjects = subs;
    dailyGoalH = hours;
    perDay = min(perDayN, max(1, subs.length));
    schedule = buildSchedule(subjects, dailyGoalH, perDay);
    await db.replaceSubjects(subjects);
    await db.setKv('daily_goal_h', '$dailyGoalH');
    await db.setKv('per_day', '$perDay');
    notifyListeners();
  }

  List<CustomTask> tasksOn(DateTime d) {
    final iso = isoDate(d);
    return tasks.where((t) => t.day == iso).toList()..sort(compareTasks);
  }

  Future<void> addTask(DateTime day, String title, String time) async {
    final t = makeTask(isoDate(day), title, time); // TaskException para a interface mostrar
    tasks.add(t);
    await db.putTask(t);
    notifyListeners();
  }

  Future<void> removeTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
    todoDone.remove('task:$id');
    await db.deleteTask(id);
    notifyListeners();
  }

  Future<void> setTodo(String key, bool v) async {
    if (v) {
      todoDone.add(key);
    } else {
      todoDone.remove(key);
    }
    await db.setTodo(key, v);
    notifyListeners();
  }

  // ---------- simulados ----------
  String attachmentPath(Attachment a) => p.join(db.dir, 'anexos', a.file);

  Future<Exam> registerExam({required String name, required int maxQ, required List<SubjectRow> rows, required bool weighted, required List<String> files}) async {
    final id = newId();
    final exam = computeExam(id: id, name: name, maxQ: maxQ, rows: rows, weighted: weighted, cityYear: city.year(), day: isoDate(AppClock.today())); // ExamException
    if (files.isNotEmpty) {
      final dir = Directory(p.join(db.dir, 'anexos', id));
      await dir.create(recursive: true);
      for (final path in files) {
        final base = p.basename(path);
        var dest = p.join(dir.path, base);
        var i = 1;
        while (await File(dest).exists()) {
          dest = p.join(dir.path, '${p.basenameWithoutExtension(base)} ($i)${p.extension(base)}');
          i++;
        }
        await File(path).copy(dest);
        exam.attachments.add(Attachment(base, '$id/${p.basename(dest)}', await File(dest).length()));
      }
    }
    // Matéria avulsa fica só no registro: NÃO entra no cronograma (subjects não é alterado).
    exams.add(exam);
    await db.putExam(exam);
    notifyListeners();
    return exam;
  }

  Future<void> deleteExam(int index) async {
    final e = exams[index];
    await db.deleteExam(e.id);
    final dir = Directory(p.join(db.dir, 'anexos', e.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    exams.removeAt(index);
    notifyListeners();
  }

  Proposal proposal() => proposeAdjustment(exams, subjects);

  Future<void> applyProposal(Proposal pr) async {
    subjects = Map<String, int>.from(pr.subjects);
    schedule = buildSchedule(subjects, dailyGoalH, perDay);
    await db.replaceSubjects(subjects);
    notifyListeners();
  }

  // ---------- Admin (testes) ----------
  bool loginAdmin(String pw) {
    if (!verifyAdminPassword(pw)) return false;
    admin = true;
    notifyListeners();
    return true;
  }

  void logoutAdmin() {
    admin = false;
    notifyListeners();
  }

  Future<void> adminAddStudy(int minutes, String subject) async {
    final today = AppClock.today();
    addMinutes(today, minutes, subject); // mesma economia do foco real
    await _applyCity(city.study(minutes, today: today));
  }

  Future<void> adminAddPoints(int n) async {
    points += n;
    await _persistMoney();
    notifyListeners();
  }

  Future<void> adminLevelUp(int n) async => _applyCity(city.levelUp(n));

  /// Avança o calendário n dias. credit=true: cada dia vira uma sessão que bate a meta (sem pontos) e entra na cidade.
  Future<void> adminAdvanceDays(int n, bool credit) async {
    final g = goalMin();
    final ev = <CityEvent>[];
    for (var i = 0; i < n; i++) {
      AppClock.offsetDays += 1;
      final t = AppClock.today();
      final iso = isoDate(t);
      if (credit && g > 0) {
        sessions[iso] = {'Geral': g};
        simDays.add(iso);
        await db.putSession(iso, 'Geral', g, simulated: true);
      }
      ev.addAll(city.checkDay(t));
      ev.addAll(city.checkPlazas(t));
    }
    await db.setKv('admin_offset', '${AppClock.offsetDays}');
    await _applyCity(ev);
  }

  Future<void> adminRestoreClock() async {
    AppClock.offsetDays = 0;
    final real = isoDate(AppClock.today());
    for (final d in simDays.where((d) => d.compareTo(real) > 0).toList()) {
      sessions.remove(d);
      simDays.remove(d);
    }
    await db.deleteSimulatedSessions(after: real);
    await db.setKv('admin_offset', '0');
    notifyListeners();
  }

  /// Zera a cidade e as sessões simuladas. Simulados, anexos e pontos NÃO são tocados.
  Future<void> adminResetCity() async {
    await db.clearCity();
    await db.deleteSimulatedSessions();
    for (final d in simDays) {
      sessions.remove(d);
    }
    simDays.clear();
    AppClock.offsetDays = 0;
    await db.setKv('admin_offset', '0');
    perms.data.clear();
    _savedD = -1;
    _savedHist = 0;
    _buildCity(CityState(Random().nextInt(1 << 30) + 1));
    traffic.sync(city);
    await _persistCity();
    notifyListeners();
  }
}
