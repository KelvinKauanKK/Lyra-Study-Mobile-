// Paridade com o desktop: os arquivos de test/golden/*.json são gerados pelo CÓDIGO PYTHON
// (python tools/export_mobile.py golden). Se algum teste falhar, a regra em Dart divergiu da regra em Python.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra_study/core/analysis.dart';
import 'package:lyra_study/core/economy.dart';
import 'package:lyra_study/core/exam.dart';
import 'package:lyra_study/core/schedule.dart';
import 'package:lyra_study/core/util.dart';

dynamic load(String name) => jsonDecode(File('test/golden/$name').readAsStringSync());
Map<String, int> intMap(Map m) => {for (final e in m.entries) e.key as String: (e.value as num).toInt()};

void main() {
  test('cronograma: mesmas matérias, dias e minutos do Python (60 casos)', () {
    for (final c in load('schedule.json') as List) {
      final subjects = intMap(c['subjects'] as Map);
      final h = (c['dailyH'] as num).toDouble();
      final pd = (c['perDay'] as num).toInt();
      expect(weeklyMinutes(subjects, h), intMap(c['weekly'] as Map), reason: 'minutos semanais ${jsonEncode(c['subjects'])} h=$h');
      final got = buildSchedule(subjects, h, pd);
      final exp = c['schedule'] as Map;
      for (final day in dayNames) {
        final gotDay = got[day]!.map((t) => '${t.subject}:${t.minutes}').toList();
        final expDay = (exp[day] as List).map((t) => '${t['subject']}:${t['minutes']}').toList();
        expect(gotDay, expDay, reason: '${jsonEncode(c['subjects'])} h=$h perDay=$pd dia $day');
      }
    }
  });

  test('simulados: anuladas, pesos e mensagens de erro iguais às do Python (80 casos)', () {
    final g = load('exam.json') as Map;
    for (final a in g['adjust'] as List) {
      expect(adjust(a['total'] as int, a['hits'] as int, a['annulled'] as int, a['annulledHit'] as int), (a['expected'] as List).cast<int>());
    }
    for (final c in g['exams'] as List) {
      final rows = [
        for (final r in c['rows'] as List)
          SubjectRow(r['subject'] as String,
              total: r['total'] as int, hits: r['hits'] as int, annulled: r['annulled'] as int, annulledHit: r['annulled_hit'] as int, weight: (r['weight'] as num).toDouble())
      ];
      Exam run() => computeExam(id: 'x', name: c['name'] as String, maxQ: c['maxQ'] as int, rows: rows, weighted: c['weighted'] as bool, day: '2027-01-01');
      if (c['error'] != null) {
        expect(run, throwsA(isA<ExamException>().having((e) => e.message, 'mensagem', c['error'] as String)), reason: jsonEncode(c));
        continue;
      }
      final e = run();
      final exp = c['expected'] as Map;
      expect(e.hits, exp['hits']);
      expect(e.scale, exp['scale']);
      expect(e.annulled, exp['annulled']);
      expect(e.score10, closeTo((exp['score10'] as num).toDouble(), 0.0101), reason: 'nota geral ${jsonEncode(c)}'); // tolerância de 1 centésimo: empates em x,xx5
      for (final s in (exp['subjects'] as Map).entries) {
        final v = e.subjects[s.key]!;
        expect([v.hits, v.total, v.origHits, v.origTotal, v.annulled, v.annulledHit], [s.value['hits'], s.value['total'], s.value['orig_hits'], s.value['orig_total'], s.value['annulled'], s.value['annulled_hit']]);
        expect(v.score, closeTo((s.value['score'] as num).toDouble(), 0.0101));
      }
    }
  });

  test('análise e reajuste: só matérias do cronograma, últimos 3 simulados (40 casos)', () {
    for (final c in load('analysis.json') as List) {
      final official = intMap(c['subjects'] as Map);
      final exams = [for (final x in c['exams'] as List) Exam.fromJson(x as Map<String, dynamic>)];
      final got = {for (final r in analyze(exams, official)) r.subject: r};
      final exp = {for (final r in c['official'] as List) r['subject'] as String: r};
      expect(got.keys.toSet(), exp.keys.toSet(), reason: 'conjunto de matérias oficiais');
      for (final k in exp.keys) {
        final r = got[k]!, e = exp[k]!;
        expect(r.avg, closeTo((e['avg'] as num).toDouble(), 1e-9));
        expect(r.last, closeTo((e['last'] as num).toDouble(), 1e-9));
        expect(r.trend, closeTo((e['trend'] as num).toDouble(), 1e-9));
        expect(r.n, e['n']);
        expect(r.wn, closeTo((e['wn'] as num).toDouble(), 1e-9));
        expect(r.prio, closeTo((e['prio'] as num).toDouble(), 1e-9));
      }
      expect({for (final r in analyze(exams, official, onlyOfficial: false)) r.subject}, {for (final r in c['all'] as List) r['subject'] as String});
      final p = proposeAdjustment(exams, official);
      expect(p.subjects, intMap(c['proposal'] as Map), reason: 'dificuldades propostas');
      expect(p.changes.map((x) => x.subject).toSet(), (c['changed'] as List).cast<String>().toSet());
    }
  });

  test('economia: pontos por meta, fmtDur, norm e arredondamento bancário', () {
    final g = load('economy.json') as Map;
    for (final c in g['dayPoints'] as List) {
      expect(Economy.dayPoints(c['minutes'] as int, c['goal'] as int), closeTo((c['expected'] as num).toDouble(), 1e-9), reason: '${c['minutes']} min, meta ${c['goal']}');
    }
    for (final c in g['fmtDur'] as List) {
      expect(fmtDur(c['minutes'] as int), c['expected']);
    }
    for (final c in g['norm'] as List) {
      expect(norm(c['text'] as String), c['expected']);
    }
    for (final c in g['round'] as List) {
      expect(pyRound((c['x'] as num).toDouble()), c['expected']);
    }
  });

  test('pontos devidos no dia não têm erro de arredondamento (120 x 1 min = 100)', () {
    var paid = 0;
    for (var m = 1; m <= 120; m++) {
      final due = Economy.due(m, 120);
      expect(due >= paid, isTrue);
      paid = due;
    }
    expect(paid, 100);
    expect(Economy.due(240, 120), 125);
    expect(Economy.due(999, 120), 125); // teto
  });
}
