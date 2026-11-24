import 'dart:math';
import 'catalog.dart';
import 'engine.dart';

class Car {
  final String m;
  int x, y, dx, dy;
  double t;
  Car(this.m, this.x, this.y, this.dx, this.dy, this.t);
}

/// Carros em ruas de MÃO ÚNICA (↘ ao longo de x, ↙ ao longo de y) — a arte só tem a vista frontal. Sem colisão; tráfego -20%.
class Traffic {
  final Random rng = Random();
  List<Car> cars = [];
  Set<int> dev = {};
  List<List<int>> nodes = [];
  List<int> r = [0, 0, 0, 0];

  bool _in(int x, int y) => x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3];

  bool _ok(int x, int y, int dx, int dy) {
    final cells = dx != 0 ? [[min(x, x + dx), y - 1], [min(x, x + dx), y]] : [[x - 1, min(y, y + dy)], [x, min(y, y + dy)]];
    return cells.any((c) => dev.contains(cellKey(c[0], c[1])));
  }

  bool _pick(Car c) {
    final o = <List<int>>[];
    for (final d in const [[1, 0], [0, 1]]) {
      if (_ok(c.x, c.y, d[0], d[1]) && _in(c.x + d[0], c.y + d[1])) o.add(d);
    }
    if (o.isEmpty) return false;
    final d = o[rng.nextInt(o.length)];
    c.dx = d[0];
    c.dy = d[1];
    return true;
  }

  Car? _spawn(String m) {
    for (var i = 0; i < 40 && nodes.isNotEmpty; i++) {
      final n = nodes[rng.nextInt(nodes.length)];
      final c = Car(m, n[0], n[1], 1, 0, rng.nextDouble());
      if (_pick(c)) return c;
    }
    return null;
  }

  void sync(CityEngine city) {
    final g = city.geom();
    dev = g.dev;
    r = city.region();
    nodes = [];
    final owned = city.s.oc;
    if (city.s.view == 'dia' || dev.isEmpty || owned.isEmpty) {
      cars = [];
      return;
    }
    for (final k in dev) {
      final x = k ~/ 1000, y = k % 1000;
      for (final d in const [[0, 0], [1, 0], [0, 1], [1, 1]]) {
        if (_in(x + d[0], y + d[1])) nodes.add([x + d[0], y + d[1]]);
      }
    }
    final area = (r[2] - r[0]) * (r[3] - r[1]);
    final total = max(1, min((owned.length * min(4, 1 + dev.length ~/ 8) * Catalog.traffic).round(), area ~/ 5));
    cars = cars.where((c) => owned.contains(c.m) && _in(c.x, c.y)).take(total).toList();
    while (cars.length < total) {
      final c = _spawn(owned[cars.length % owned.length]);
      if (c == null) break;
      cars.add(c);
    }
  }

  void step(double dt) {
    for (final k in cars) {
      k.t += dt * 0.9;
      while (k.t >= 1) {
        k.t -= 1;
        k.x += k.dx;
        k.y += k.dy;
        if (!_pick(k)) {
          final n = _spawn(k.m);
          if (n == null) {
            k.t = 0;
            break;
          }
          k.x = n.x;
          k.y = n.y;
          k.dx = n.dx;
          k.dy = n.dy;
          k.t = n.t;
        }
      }
    }
  }
}
