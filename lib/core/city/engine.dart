import 'dart:math';
import '../clock.dart';
import '../economy.dart';
import '../util.dart';
import 'catalog.dart';
import 'layout.dart';

class Tile {
  String? b;
  int lv, m;
  double xp;
  String date;
  Tile({this.b, this.lv = 0, this.xp = 0, this.date = '', this.m = 0});
  factory Tile.fromJson(Map<String, dynamic> j) => Tile(
      b: j['b'] as String?, lv: (j['lv'] as num?)?.toInt() ?? 0, xp: (j['xp'] as num?)?.toDouble() ?? 0, date: (j['date'] as String?) ?? '', m: (j['m'] as num?)?.toInt() ?? 0);
}

/// Eventos para a interface animar/avisar: toast, pop (construção/evolução) e merge (fusão dia→semana→mês→ano).
class CityEvent {
  final String type, text;
  final int index;
  final List<int> rect;
  const CityEvent._(this.type, this.text, this.index, this.rect);
  factory CityEvent.toast(String text) => CityEvent._('toast', text, -1, const []);
  factory CityEvent.pop(int index) => CityEvent._('pop', '', index, const []);
  factory CityEvent.merge(List<int> rect, String text) => CityEvent._('merge', text, -1, rect);
}

class DayCell {
  final int j, i, x, y;
  const DayCell(this.j, this.i, this.x, this.y);
}

class Plat {
  final int gx, gy, w, h, kind;
  const Plat(this.gx, this.gy, this.w, this.h, this.kind);
}

class Geom {
  final List<DayCell> days;
  final Set<int> dev;
  final List<List<int>> spare;
  final List<Plat> plats;
  final int jn;
  const Geom(this.days, this.dev, this.spare, this.plats, this.jn);
}

class PlazaProgress {
  final PlazaModel plaza;
  final double value;
  final int need;
  final bool done;
  const PlazaProgress(this.plaza, this.value, this.need, this.done);
}

int cellKey(int x, int y) => x * 1000 + y;

/// Estado persistível da cidade (tabela city_tiles + kv "city" + city_history).
class CityState {
  int d = 0;
  final List<Tile> t = [];
  List<String> ob = [], oc = ['car_a', 'car_b'], pend = [], counted = [];
  String plaza = 'auto', cycle = '', view = 'sem', model = '';
  final Map<String, String> pz = {};
  final Map<String, bool> cy = {};
  int since = 0, sel = -1, focus = -1;
  bool auto = true, rand = false;
  int seed;
  final List<Map<String, dynamic>> history = [];
  CityState(this.seed);

  Map<String, dynamic> metaJson() => {
        'D': d, 'ob': ob, 'oc': oc, 'plaza': plaza, 'pz': pz, 'pend': pend, 'since': since, 'cycle': cycle, 'cy': cy,
        'sel': sel, 'focus': focus, 'view': view, 'auto': auto, 'rand': rand, 'model': model, 'counted': counted, 'seed': seed,
      };

  void loadMeta(Map<String, dynamic> j) {
    d = (j['D'] as num?)?.toInt() ?? 0;
    ob = List<String>.from(j['ob'] ?? []);
    oc = List<String>.from(j['oc'] ?? ['car_a', 'car_b']);
    plaza = (j['plaza'] as String?) ?? 'auto';
    pz
      ..clear()
      ..addAll(Map<String, String>.from(j['pz'] ?? {}));
    pend = List<String>.from(j['pend'] ?? []);
    since = (j['since'] as num?)?.toInt() ?? 0;
    cycle = (j['cycle'] as String?) ?? '';
    cy
      ..clear()
      ..addAll(Map<String, bool>.from((j['cy'] ?? {}) as Map));
    sel = (j['sel'] as num?)?.toInt() ?? -1;
    focus = (j['focus'] as num?)?.toInt() ?? -1;
    view = (j['view'] as String?) ?? 'sem';
    auto = j['auto'] != false;
    rand = j['rand'] == true;
    model = (j['model'] as String?) ?? '';
    counted = List<String>.from(j['counted'] ?? []);
    seed = (j['seed'] as num?)?.toInt() ?? seed;
  }
}

/// Regras da cidade (port de city/engine.py): XP/níveis, dias, fusões, praças com ciclo mensal e histórico anual.
class CityEngine {
  CityEngine(this.s, this.cat, this.layout, {required this.goalMin, required this.studiedOn, required this.cycleHours, Random? rng}) : rng = rng ?? Random() {
    sanitize();
  }
  final CityState s;
  final Catalog cat;
  final Layout layout;
  final Random rng;
  final int Function() goalMin; // meta diária em minutos
  final int Function(DateTime) studiedOn; // minutos estudados no dia
  final double Function(String) cycleHours; // horas estudadas no mês ("YYYY-MM")
  int rev = 0;
  Geom? _g;

  void touch() {
    rev++;
    _g = null;
  }

  /// Saves antigos (modelos removidos) continuam abrindo: ids desconhecidos viram o modelo atual.
  void sanitize() {
    final ids = cat.buildings.map((b) => b.id).toList();
    final free = cat.buildings.where((b) => b.price == 0).map((b) => b.id).toList();
    s.ob = s.ob.where(ids.contains).toList();
    if (s.ob.isEmpty) s.ob = List<String>.from(free);
    if (!s.ob.contains(s.model)) s.model = s.ob.isNotEmpty ? s.ob.first : '';
    for (final t in s.t) {
      if (t.b != null && !ids.contains(t.b)) t.b = s.model.isEmpty ? null : s.model;
      t.lv = t.b == null ? 0 : max(1, min(t.lv == 0 ? 1 : t.lv, cat.building(t.b!).maxLevel));
    }
  }

  // ---------- ano corrente ----------
  int get D => s.d;
  int ys() => D == 0 ? 0 : ((D - 1) ~/ Catalog.per) * Catalog.per;
  int jn() => D - ys();
  int year() => ys() ~/ Catalog.per;
  Tile? tile(int i) => (i >= 0 && i < s.t.length) ? s.t[i] : null;
  List<int> pos(int j) => layout.dayCell(year(), j);

  Geom geom() {
    final cached = _g;
    if (cached != null) return cached;
    final y = year(), n = jn();
    final days = <DayCell>[];
    final dev = <int>{};
    final spare = <List<int>>[];
    final plats = <Plat>[];
    for (var j = 0; j < n; j++) {
      final p = pos(j);
      days.add(DayCell(j, ys() + j, p[0], p[1]));
      dev.add(cellKey(p[0], p[1]));
    }
    for (var w = 0; w < (n + 6) ~/ 7; w++) {
      for (final p in layout.spareCells(y, w ~/ 4, w % 4)) {
        spare.add(p);
        dev.add(cellKey(p[0], p[1]));
      }
    }
    for (var w = 0; w < n ~/ 7; w++) {
      if (w ~/ 4 >= n ~/ 28) {
        final o = layout.weekOrigin(y, w ~/ 4, w % 4);
        plats.add(Plat(o[0], o[1], 3, 3, 0));
      }
    }
    for (var m = 0; m < n ~/ 28; m++) {
      final o = layout.monthOrigin(y, m);
      plats.add(Plat(o[0], o[1], 6, 6, 1));
    }
    if (n == Catalog.per) plats.add(const Plat(0, 0, Layout.yearW, Layout.yearH, 2));
    final g = Geom(days, dev, spare, plats, n);
    _g = g;
    return g;
  }

  /// Retângulo [x0, y0, x1, y1] de cada visão (dia, semana, mês, ano). O Ano é a grade compacta 4x3 de blocões.
  List<int> region([String? view]) {
    final v = view ?? s.view;
    final n = jn();
    if (v == 'ano' || n == 0) return [0, 0, Layout.yearW, Layout.yearH];
    if (v == 'dia') {
      final i = (s.focus >= ys() && s.focus < D) ? s.focus : D - 1;
      final p = pos(i - ys());
      return [p[0], p[1], p[0] + 1, p[1] + 1];
    }
    final j = n - 1;
    final m = j ~/ 28, w = (j % 28) ~/ 7;
    if (v == 'sem') {
      final o = layout.weekOrigin(year(), m, w);
      return [o[0], o[1], o[0] + 3, o[1] + 3];
    }
    final o = layout.monthOrigin(year(), m);
    return [o[0], o[1], o[0] + 6, o[1] + 6];
  }

  List<Plat> platsFor(Geom g, List<int> r, [String? view]) {
    final v = view ?? s.view;
    final n = g.jn;
    if (v == 'ano' || n == 0) return g.plats;
    if (v == 'dia') return [];
    final j = n - 1;
    if (v == 'sem') return (n ~/ 7 > j ~/ 7) ? [Plat(r[0], r[1], 3, 3, 0)] : [];
    if (n ~/ 28 > j ~/ 28) return [Plat(r[0], r[1], 6, 6, 1)];
    return g.plats.where((p) => p.kind == 0 && p.gx >= r[0] && p.gx < r[2] && p.gy >= r[1] && p.gy < r[3]).toList();
  }

  // ---------- praças: metas do ciclo mensal ----------
  String cycleKey(DateTime t) => '${t.year}-${two(t.month)}';
  double cycleHoursNow() => cycleHours(s.cycle);
  int cycleDays() => s.counted.where((x) => x.startsWith(s.cycle)).length;
  List<PlazaProgress> plazaProgress() => Catalog.plazas
      .map((p) => PlazaProgress(p, p.kind == 'h' ? cycleHoursNow() : cycleDays().toDouble(), p.need, s.cy[p.id] == true))
      .toList();
  List<String> styles() => [for (final p in Catalog.plazas) if (s.cy[p.id] == true) p.id];

  /// Todo mês o progresso e o acesso às praças reiniciam (as praças já construídas continuam no mapa).
  List<CityEvent> rollCycle(DateTime today) {
    final key = cycleKey(today);
    if (s.cycle == key) return [];
    final first = s.cycle.isEmpty;
    s.cycle = key;
    s.cy.clear();
    return first ? [] : [CityEvent.toast('🗓 Novo mês: as metas das praças reiniciaram')];
  }

  List<List<int>> freeSpare() {
    final used = s.pz.keys.toSet();
    return geom().spare.where((p) => !used.contains('${p[0]},${p[1]}')).toList();
  }

  /// Coloca uma praça em um lote de sobra sorteado. Sem lote livre, a praça fica na fila (pend) até surgir espaço.
  List<CityEvent> spawnPlaza([String? style]) {
    final st = styles();
    var sty = style;
    if (sty == null) {
      if (st.contains(s.plaza)) {
        sty = s.plaza;
      } else if (st.isNotEmpty) {
        sty = st[rng.nextInt(st.length)];
      }
    }
    if (sty == null) return [];
    final free = freeSpare();
    if (free.isEmpty) {
      s.pend.add(sty);
      return [];
    }
    final c = free[rng.nextInt(free.length)];
    s.pz['${c[0]},${c[1]}'] = sty;
    touch();
    return [CityEvent.toast('🌳 Nova praça: ${cat.plaza(sty).name}')];
  }

  void flushPending() {
    final pend = s.pend;
    s.pend = [];
    for (final st in pend) {
      spawnPlaza(st);
    }
  }

  List<CityEvent> checkPlazas(DateTime today) {
    final ev = rollCycle(today);
    for (final p in plazaProgress()) {
      if (p.value >= p.need && !p.done) {
        s.cy[p.plaza.id] = true;
        ev.add(CityEvent.toast('🌳 ${p.plaza.name} desbloqueada neste mês!'));
        ev.addAll(spawnPlaza(p.plaza.id));
      }
    }
    return ev;
  }

  // ---------- dias e fusões ----------
  /// Prédio de um novo dia: aleatório entre os desbloqueados (opção "rand") ou o modelo fixo escolhido.
  String? pickBuilding() {
    if (!s.auto || s.ob.isEmpty) return null;
    if (s.rand) return s.ob[rng.nextInt(s.ob.length)];
    return s.ob.contains(s.model) ? s.model : s.ob.first;
  }

  List<CityEvent> addDay({bool quiet = false, DateTime? today}) {
    final t = today ?? AppClock.today();
    final ev = <CityEvent>[];
    final i = D;
    final b = pickBuilding();
    if (D > 0 && jn() == Catalog.per) {
      s.pz.clear();
      s.pend = [];
    }
    s.t.add(Tile(b: b, lv: b != null ? 1 : 0, xp: 0, date: isoDate(t), m: studiedOn(t)));
    s.d += 1;
    s.sel = i;
    s.since += 1;
    final n = jn();
    final y = year();
    if (n % Catalog.per == 0) {
      snapshot(t);
      ev.add(CityEvent.merge([0, 0, Layout.yearW, Layout.yearH], '🏙 Quadrado do Ano ${y + 1}! Foto guardada no Modo Memória'));
    } else if (n % 28 == 0) {
      final o = layout.monthOrigin(y, n ~/ 28 - 1);
      ev.add(CityEvent.merge([o[0], o[1], 6, 6], '🌆 4 semanas fundidas: Quadrado do Mês!'));
    } else if (n % 7 == 0) {
      final j0 = n - 7;
      final o = layout.weekOrigin(y, j0 ~/ 28, (j0 % 28) ~/ 7);
      ev.add(CityEvent.merge([o[0], o[1], 3, 3], '🏙 7 dias fundidos: Quadrado da Semana!'));
    } else {
      ev.add(CityEvent.toast(b != null ? '🧱 Novo dia: ${cat.building(b).name} construído' : '🧱 Dia concluído: nova fundação'));
    }
    touch();
    nextFocus();
    if (styles().length >= Catalog.plazaMinUnlocked && s.since >= Catalog.plazaEvery) {
      s.since = 0;
      ev.addAll(spawnPlaza()); // praça nova ao acaso a cada 5 dias
    }
    flushPending();
    ev.add(CityEvent.pop(i));
    touch();
    return quiet ? [] : ev;
  }

  /// O prédio em foco continua em uso entre os dias; ao atingir o nível máximo, passa ao próximo que ainda evolui.
  void nextFocus() {
    final cur = tile(s.focus);
    if (cur != null && cur.b != null && s.focus >= ys() && cur.lv < cat.building(cur.b!).maxLevel) return;
    for (var i = D - 1; i >= ys(); i--) {
      final t = tile(i);
      if (t != null && t.b != null && t.lv < cat.building(t.b!).maxLevel) {
        s.focus = i;
        return;
      }
    }
  }

  /// Prédios dos últimos 7 dias (o "quadrado ativo") que podem receber XP.
  List<int> candidates() => [for (var i = D - 1; i >= max(ys(), D - 7); i--) if (tile(i)?.b != null) i];

  // ---------- histórico anual (Modo Memória) ----------
  static Map<String, dynamic> yearStats(List<Map<String, dynamic>> tiles, int plazas, int cars) {
    final by = <String, int>{};
    final lv = <String, int>{};
    var minutes = 0;
    for (final t in tiles) {
      minutes += (t['m'] as num?)?.toInt() ?? 0;
      final b = t['b'] as String?;
      if (b != null) {
        by[b] = (by[b] ?? 0) + 1;
        final k = '${t['lv']}';
        lv[k] = (lv[k] ?? 0) + 1;
      }
    }
    final n = lv.values.fold<int>(0, (a, b) => a + b);
    var sum = 0.0;
    lv.forEach((k, v) => sum += int.parse(k) * v);
    return {'days': tiles.length, 'minutes': minutes, 'buildings': by, 'levels': lv, 'avg_level': n == 0 ? 0.0 : (sum / n * 100).round() / 100, 'plazas': plazas, 'cars': cars};
  }

  /// Ao fechar um ano: guarda o estado visual (para renderizar a "foto") + estatísticas.
  void snapshot(DateTime t) {
    final tiles = [for (var i = ys(); i < D; i++) {'b': s.t[i].b, 'lv': s.t[i].lv, 'm': s.t[i].m}];
    s.history.add({
      'year': year() + 1, 'idx': year(), 'date': isoDate(t), 'seed': this.s.seed, 'tiles': tiles, 'pz': Map<String, String>.from(s.pz), 'oc': List<String>.from(s.oc),
      'stats': yearStats(tiles, s.pz.length, s.oc.length),
    });
  }

  // ---------- estudo ----------
  Tile? _dayTile(String iso) {
    for (var i = D - 1; i >= max(0, D - 3); i--) {
      final t = tile(i);
      if (t != null && t.date == iso) return t;
    }
    return null;
  }

  /// A cada minuto de foco (ou em lote pelo Admin): XP no prédio em foco (proporcional à meta) + dia concluído + metas das praças.
  List<CityEvent> study(int minutes, {DateTime? today}) {
    final t = today ?? AppClock.today();
    final ev = <CityEvent>[];
    final cur = tile(s.focus);
    if (cur != null && cur.b != null) {
      final b = cat.building(cur.b!);
      if (cur.lv < b.maxLevel) {
        final g = goalMin();
        cur.xp = ((cur.xp + minutes * (g > 0 ? Economy.xpDaily / g : Catalog.xpPerMinFallback)) * 100).round() / 100;
        while (cur.lv < b.maxLevel && cur.xp >= 100 * cur.lv) {
          cur.xp -= 100 * cur.lv;
          cur.lv += 1;
          ev.add(CityEvent.pop(s.focus));
          ev.add(CityEvent.toast('⬆ ${b.name} evoluiu para o nível ${cur.lv}!'));
        }
        if (cur.lv >= b.maxLevel) {
          cur.xp = 0;
          ev.add(CityEvent.toast('🏆 ${b.name} no nível máximo — foco passa ao próximo prédio'));
          nextFocus();
        }
      }
    }
    final dt = _dayTile(isoDate(t));
    if (dt != null) dt.m += minutes;
    ev.addAll(checkDay(t));
    ev.addAll(checkPlazas(t));
    touch();
    return ev;
  }

  /// Dia concluído = meta diária batida (uma vez por data).
  List<CityEvent> checkDay(DateTime t) {
    final g = goalMin();
    final iso = isoDate(t);
    if (g > 0 && !s.counted.contains(iso) && studiedOn(t) >= g) {
      s.counted.add(iso);
      return addDay(today: t);
    }
    return [];
  }

  // ---------- ações do usuário / admin ----------
  /// Constrói na fundação livre i. bid == null => prédio aleatório entre os desbloqueados.
  List<CityEvent> build(int i, [String? bid]) {
    final t = tile(i);
    if (t == null || t.b != null || s.ob.isEmpty) return [];
    final id = bid ?? s.ob[rng.nextInt(s.ob.length)];
    t
      ..b = id
      ..lv = 1
      ..xp = 0;
    final t2 = tile(s.focus);
    if (t2 == null || t2.b == null) s.focus = i;
    touch();
    return [CityEvent.pop(i), CityEvent.toast('🏗 ${cat.building(id).name} construído')];
  }

  List<CityEvent> levelUp(int n) {
    final t = tile(s.focus);
    if (t == null || t.b == null) return [];
    final mx = cat.building(t.b!).maxLevel;
    var ev = <CityEvent>[];
    if (t.lv < mx) {
      t.lv = min(mx, t.lv + n);
      t.xp = 0;
      ev = [CityEvent.pop(s.focus), CityEvent.toast('⬆ Nível ${t.lv}')];
    }
    if (t.lv >= mx) nextFocus();
    touch();
    return ev;
  }

  /// Reconstrói o mapa de um ano concluído (para a "foto" do Modo Memória).
  static CityEngine fromHistory(Map<String, dynamic> e, Catalog cat, Layout layout) {
    final idx = (e['idx'] as num).toInt();
    final st = CityState((e['seed'] as num?)?.toInt() ?? 1);
    st.d = (idx + 1) * Catalog.per;
    for (var i = 0; i < idx * Catalog.per; i++) {
      st.t.add(Tile());
    }
    for (final t in (e['tiles'] as List)) {
      st.t.add(Tile(b: t['b'] as String?, lv: (t['lv'] as num).toInt(), m: (t['m'] as num?)?.toInt() ?? 0));
    }
    st.pz.addAll(Map<String, String>.from(e['pz'] as Map));
    st.oc = List<String>.from(e['oc'] as List);
    st.view = 'ano';
    final eng = CityEngine(st, cat, layout, goalMin: () => 0, studiedOn: (_) => 0, cycleHours: (_) => 0);
    return eng;
  }
}
