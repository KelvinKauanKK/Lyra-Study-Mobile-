import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyra_study/core/city/catalog.dart';
import 'package:lyra_study/core/city/engine.dart';
import 'package:lyra_study/core/city/layout.dart';
import 'package:lyra_study/core/tasks.dart';
import 'package:lyra_study/core/util.dart';

Catalog catalog() => Catalog.fromJson(File('assets/city/buildings.json').readAsStringSync(), File('assets/city/meta.json').readAsStringSync());

void main() {
  final cat = catalog();

  test('catálogo: 9 modelos (2 grátis) e sprites existentes para todos os níveis', () {
    expect(cat.buildings.length, 9);
    expect(cat.buildings.where((b) => b.price == 0).length, 2);
    for (final b in cat.buildings) {
      for (var l = 1; l <= b.maxLevel; l++) {
        expect(cat.meta.containsKey('buildings/${b.id}_$l'), isTrue, reason: '${b.id} nível $l');
        expect(File('assets/city/buildings/${b.id}_$l.webp').existsSync(), isTrue);
      }
    }
  });

  test('layout: 432 células únicas em 24x18 (336 dias + 96 sobras), sem buraco', () {
    final l = Layout(MemoryPermStore(), 123);
    final seen = <int>{};
    for (var j = 0; j < 336; j++) {
      final c = l.dayCell(0, j);
      expect(c[0], inInclusiveRange(0, 23));
      expect(c[1], inInclusiveRange(0, 17));
      expect(seen.add(cellKey(c[0], c[1])), isTrue, reason: 'dia $j repetido');
    }
    for (var m = 0; m < 12; m++) {
      for (var w = 0; w < 4; w++) {
        for (final c in l.spareCells(0, m, w)) {
          expect(seen.add(cellKey(c[0], c[1])), isTrue);
        }
      }
    }
    expect(seen.length, 24 * 18);
  });

  test('layout: permutações guardadas mantêm o mapa idêntico ao reabrir', () {
    final store = MemoryPermStore();
    final a = Layout(store, 5);
    final first = [for (var j = 0; j < 60; j++) a.dayCell(0, j)];
    final b = Layout(store, 999); // semente diferente, mas as permutações persistidas vencem
    expect([for (var j = 0; j < 60; j++) b.dayCell(0, j)], first);
  });

  CityEngine make({int goal = 120, Map<String, int>? minutes}) {
    final m = minutes ?? <String, int>{};
    return CityEngine(CityState(7), cat, Layout(MemoryPermStore(), 7),
        goalMin: () => goal, studiedOn: (d) => m[isoDate(d)] ?? 0, cycleHours: (k) => m.entries.where((e) => e.key.startsWith(k)).fold<int>(0, (a, e) => a + e.value) / 60);
  }

  test('XP do prédio é proporcional à meta (nível 2 após 75 min com meta de 2 h)', () {
    final e = make();
    e.addDay(quiet: true, today: DateTime(2027, 3, 1));
    e.s.focus = 0;
    for (var i = 0; i < 74; i++) {
      e.study(1, today: DateTime(2027, 3, 1));
    }
    expect(e.tile(0)!.lv, 1);
    e.study(2, today: DateTime(2027, 3, 1));
    expect(e.tile(0)!.lv, 2);
  });

  test('praças: 1 h no mês => praça 1; 1 dia => praça 2; 7 dias => praça 3; virada do mês reinicia', () {
    final minutes = <String, int>{};
    final e = make(goal: 3, minutes: minutes);
    minutes['2027-03-01'] = 60;
    e.study(60, today: DateTime(2027, 3, 1));
    expect(e.styles(), ['plaza_1', 'plaza_2']);
    expect(e.s.pz.length, 2);
    for (var d = 2; d <= 8; d++) {
      final day = DateTime(2027, 3, d);
      minutes[isoDate(day)] = 3;
      e.study(3, today: day);
    }
    expect(e.styles().contains('plaza_3'), isTrue);
    expect(e.cycleDays(), 8);
    final before = Map<String, String>.from(e.s.pz);
    minutes['2027-04-01'] = 3;
    e.study(3, today: DateTime(2027, 4, 1));
    expect(e.s.cy.containsKey('plaza_3'), isFalse); // acesso reiniciou
    expect(e.s.pz.entries.every((x) => before[x.key] == x.value || !before.containsKey(x.key)), isTrue); // praças construídas continuam
    expect(e.s.pz.keys.toSet().containsAll(before.keys), isTrue);
  });

  test('ano completo: 336 dias geram o snapshot e o ano seguinte começa limpo', () {
    final e = make(goal: 1);
    var day = DateTime(2027, 1, 1);
    for (var i = 0; i < 336; i++) {
      e.addDay(quiet: true, today: day);
      day = DateTime(day.year, day.month, day.day + 1);
    }
    expect(e.D, 336);
    expect(e.s.history.length, 1);
    expect(e.s.history.first['year'], 1);
    e.addDay(quiet: true, today: day);
    expect(e.year(), 1);
    expect(e.jn(), 1);
    expect(e.s.pz.isEmpty, isTrue);
    final photo = CityEngine.fromHistory(e.s.history.first, cat, e.layout);
    expect(photo.D, 336);
    expect(photo.region(), [0, 0, 24, 18]); // a foto do ano é a grade compacta 4x3 de blocões
  });

  test('tarefas e lembretes: validação, rótulo e ordenação por horário', () {
    final a = makeTask('2027-03-01', 'Entregar redação', '9:05');
    final b = makeTask('2027-03-01', 'Ligar para a escola', '');
    expect(a.time, '09:05');
    expect(taskLabel(a), '🔔 09:05 Entregar redação');
    expect(taskLabel(b), '🔔 Ligar para a escola');
    final list = [b, a]..sort(compareTasks);
    expect(list.first.title, 'Entregar redação');
    expect(() => makeTask('2027-03-01', '', ''), throwsA(isA<TaskException>()));
    expect(() => makeTask('2027-03-01', 'x', '25:99'), throwsA(isA<TaskException>()));
    expect(() => makeTask('2027-03-01', 'x', 'abc'), throwsA(isA<TaskException>()));
  });
}
