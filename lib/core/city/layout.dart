import 'dart:math';

/// Onde cada bloco aparece. Tudo é ALEATÓRIO, mas reprodutível: cada permutação é sorteada UMA vez e guardada no SQLite
/// (tabela layout_perm), então o mapa não muda ao reabrir o app — e as cidades migradas do desktop mantêm suas posições.
/// Ano = 12 blocões de 6x6 em grade 4x3 (24x18) • Mês = 4 semanas 3x3 em 2x2 • Semana = 9 células (7 dias + 2 sobras).
abstract class PermStore {
  List<int>? getPerm(String key);
  void putPerm(String key, List<int> perm);
}

class MemoryPermStore implements PermStore {
  final Map<String, List<int>> data = {};
  @override
  List<int>? getPerm(String key) => data[key];
  @override
  void putPerm(String key, List<int> perm) => data[key] = perm;
}

int stableHash(String s) {
  var h = 2166136261;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

class Layout {
  Layout(this.store, this.seed);
  final PermStore store;
  final int seed;
  static const cols = 4, rows = 3, month = 6, week = 3, yearW = 24, yearH = 18;

  List<int> perm(String key, int n) {
    final got = store.getPerm(key);
    if (got != null && got.length == n) return got;
    final a = List<int>.generate(n, (i) => i)..shuffle(Random(seed ^ stableHash(key)));
    store.putPerm(key, a);
    return a;
  }

  List<int> monthOrigin(int year, int m) {
    final s = perm('m:$year', cols * rows)[m];
    return [(s % cols) * month, (s ~/ cols) * month];
  }

  List<int> weekOrigin(int year, int m, int w) {
    final mo = monthOrigin(year, m);
    final s = perm('w:$year:$m', 4)[w];
    return [mo[0] + (s % 2) * week, mo[1] + (s ~/ 2) * week];
  }

  /// k = 0..6 dias da semana; 7 e 8 = lotes de sobra (praças).
  List<int> weekCell(int year, int m, int w, int k) {
    final wo = weekOrigin(year, m, w);
    final c = perm('c:$year:$m:$w', 9)[k];
    return [wo[0] + c % 3, wo[1] + c ~/ 3];
  }

  List<int> dayCell(int year, int j) => weekCell(year, j ~/ 28, (j % 28) ~/ 7, j % 7);
  List<List<int>> spareCells(int year, int m, int w) => [weekCell(year, m, w, 7), weekCell(year, m, w, 8)];
}
