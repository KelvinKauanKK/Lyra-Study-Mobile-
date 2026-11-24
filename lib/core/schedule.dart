import 'dart:math';
import 'util.dart';

const dayNames = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

class StudyTask {
  final String subject;
  final int minutes;
  const StudyTask(this.subject, this.minutes);
}

/// soma pesos -> horas/dia x 7 x 60 / soma = minutos por ponto -> x peso (peso mínimo 1).
Map<String, int> weeklyMinutes(Map<String, int> subjects, double dailyH) {
  final w = {for (final e in subjects.entries) e.key: max(1, e.value)};
  final total = w.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return {};
  final base = dailyH * 7 * 60 / total;
  return {for (final e in w.entries) e.key: pyRound(base * e.value)};
}

/// Distribui as matérias nos 7 dias (port fiel de rules.build_schedule): toda matéria aparece ao menos 1x/semana;
/// com mais matérias que vagas, os dias que sobram recebem uma a mais (espaçados); vagas extras vão para as mais difíceis.
Map<String, List<StudyTask>> buildSchedule(Map<String, int> subjects, double dailyH, int perDay) {
  final mins = weeklyMinutes(subjects, dailyH);
  final subs = mins.keys.toList();
  final sched = {for (final d in dayNames) d: <StudyTask>[]};
  if (subs.isEmpty) return sched;
  final w = {for (final s in subs) s: max(1, subjects[s]!)};
  final slots = max(7 * max(1, min(perDay, subs.length)), subs.length);
  final apps = {for (final s in subs) s: 1};
  for (var k = 0; k < slots - subs.length; k++) {
    final pool = subs.where((s) => apps[s]! < 7).toList();
    if (pool.isEmpty) break;
    var best = pool.first;
    for (final s in pool) {
      if (w[s]! / apps[s]! > w[best]! / apps[best]!) best = s; // empate: o primeiro, como o max() do Python
    }
    apps[best] = apps[best]! + 1;
  }
  final base = slots ~/ 7;
  final extra = slots % 7;
  final heavy = <int>{for (var j = 0; j < extra; j++) ((j + 0.5) * 7 / extra).floor()};
  final cap = [for (var i = 0; i < 7; i++) base + (heavy.contains(i) ? 1 : 0)];
  final days = List.generate(7, (_) => <String>[]);
  final order = List<int>.generate(subs.length, (i) => i);
  order.sort((a, b) {
    final c1 = apps[subs[b]]!.compareTo(apps[subs[a]]!);
    if (c1 != 0) return c1;
    final c2 = w[subs[b]]!.compareTo(w[subs[a]]!);
    if (c2 != 0) return c2;
    return a.compareTo(b); // estável, como o sorted() do Python
  });
  for (final si in order) {
    final s = subs[si];
    for (var n = 0; n < apps[s]!; n++) {
      final free = [for (var i = 0; i < 7; i++) if (cap[i] > 0) i];
      if (free.isEmpty) break;
      var ok = [for (final i in free) if (!days[i].contains(s)) i];
      if (ok.isEmpty) ok = free;
      int spread(int i) {
        var m = 7;
        for (var j = 0; j < 7; j++) {
          if (days[j].contains(s)) m = min(m, min((i - j) % 7, (j - i) % 7));
        }
        return m;
      }

      var put = ok.first;
      var bs = spread(put);
      var bc = cap[put];
      for (final i in ok.skip(1)) {
        final sp = spread(i);
        if (sp > bs || (sp == bs && cap[i] > bc)) {
          put = i;
          bs = sp;
          bc = cap[i];
        }
      }
      days[put].add(s);
      cap[put] -= 1;
    }
  }
  for (final s in subs) {
    var n = 0;
    for (final d in days) {
      n += d.where((x) => x == s).length;
    }
    n = max(1, n);
    final chunk = mins[s]! ~/ n;
    final rem = mins[s]! % n;
    var first = true;
    for (var i = 0; i < 7; i++) {
      final c = days[i].where((x) => x == s).length;
      for (var k = 0; k < c; k++) {
        sched[dayNames[i]]!.add(StudyTask(s, chunk + (first ? rem : 0)));
        first = false;
      }
    }
  }
  return sched;
}
