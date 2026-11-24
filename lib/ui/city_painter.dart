import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/city/catalog.dart';
import '../core/city/engine.dart';
import '../core/city/traffic.dart';

typedef Proj = Offset Function(num x, num y, [num z]);

/// Câmera FIXA: enquadra e centraliza a região da visão (dia/semana/mês/ano). Guardada para o toque achar o quadrado.
class CityCamera {
  double k = 20, ox = 0, oy = 0;
}

Color _rgb(List<int> c, [double f = 1]) => Color.fromARGB(255, min(255, (c[0] * f).round()), min(255, (c[1] * f).round()), min(255, (c[2] * f).round()));
const _bg = [10, 13, 26], _slab = [15, 19, 38], _lotC = [28, 35, 56], _spare = [22, 40, 34], _grid = [22, 27, 54], _grid6 = [42, 51, 88];
const _asph = [40, 45, 66], _arrow = [150, 160, 195], _dash = [120, 98, 48];
const _platFill = [[25, 35, 69], [31, 42, 90], [42, 42, 78]];
const _platGlow = [[53, 224, 255], [124, 108, 240], [242, 184, 75]];

class _Obj {
  final double depth;
  final VoidCallback draw;
  _Obj(this.depth, this.draw);
}

/// Desenho isométrico (port de city/render.py): malha viária de mão única, lotes, prédios e praças com sprites e carros NA MESMA lista
/// ordenada por profundidade — um carro que passa atrás de um prédio fica escondido por ele.
class CityPainter extends CustomPainter {
  CityPainter({required this.city, required this.images, required this.cars, required this.cam, this.pulse = 0});
  final CityEngine city;
  final Map<String, ui.Image> images;
  final List<Car> cars;
  final CityCamera cam;
  final double pulse;
  Catalog get cat => city.cat;

  double _tall(List<int> r) {
    var m = 1.0;
    for (final d in city.geom().days) {
      if (d.x >= r[0] && d.x < r[2] && d.y >= r[1] && d.y < r[3]) {
        final t = city.tile(d.i);
        if (t != null && t.b != null) {
          final key = cat.buildingKey(t.b!, t.lv);
          final meta = key == null ? null : cat.meta[key];
          if (meta != null) m = max(m, meta.h / meta.bw * 2 * Catalog.lot * Catalog.bldFill + .4);
        }
      }
    }
    return m;
  }

  Rect? _sprite(Canvas c, String key, Offset at, double k, {bool plaza = false}) {
    final im = images[key];
    final meta = cat.meta[key];
    if (im == null || meta == null) return null;
    Rect dst;
    if (plaza) {
      final s = k * 2 * (Catalog.lot + .12) / meta.w;
      dst = Rect.fromLTWH(at.dx - meta.w * s / 2, at.dy - meta.h * s * .58, meta.w * s, meta.h * s);
    } else {
      final s = k * 2 * Catalog.lot * Catalog.bldFill / meta.bw;
      dst = Rect.fromLTWH(at.dx - meta.ax * meta.w * s, at.dy + meta.bw * s / 4 - meta.h * s, meta.w * s, meta.h * s);
    }
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
    return dst;
  }

  void _label(Canvas c, String text, Offset at, Color color) {
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)), textDirection: TextDirection.ltr)..layout();
    final box = Rect.fromCenter(center: at, width: tp.width + 10, height: tp.height + 4);
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(5)), Paint()..color = const Color(0xE6131933));
    tp.paint(c, Offset(box.left + 5, box.top + 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _rgb(_bg));
    final r = city.region();
    final g = city.geom();
    final plats = city.platsFor(g, r);
    final tall = _tall(r);
    final xr = ((r[2] - r[0]) + (r[3] - r[1])).toDouble();
    final k = max(6.0, min(150.0, min(size.width * .94 / xr, size.height * .92 / (xr / 2 + tall))));
    cam.k = k;
    cam.ox = size.width / 2 - ((r[0] - r[3]) + (r[2] - r[1])) / 2 * k;
    cam.oy = size.height / 2 - ((r[0] + r[1] + r[2] + r[3]) / 4 - tall / 2) * k;
    Offset P(num x, num y, [num z = 0]) => Offset(cam.ox + (x - y) * k, cam.oy + (x + y) * k / 2 - z * k);

    void poly(List<Offset> pts, Color c) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = c);
    }

    void line(List<Offset> pts, Color c, double w) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = w);
    }

    void box(double x0, double y0, double x1, double y1, double z0, double z1, List<int> col, Proj pj) {
      poly([pj(x1, y0, z0), pj(x1, y1, z0), pj(x1, y1, z1), pj(x1, y0, z1)], _rgb(col, .8));
      poly([pj(x0, y1, z0), pj(x1, y1, z0), pj(x1, y1, z1), pj(x0, y1, z1)], _rgb(col, .6));
      poly([pj(x0, y0, z1), pj(x1, y0, z1), pj(x1, y1, z1), pj(x0, y1, z1)], _rgb(col, 1.15));
    }

    // laje do território + grade
    final x0 = r[0].toDouble(), y0 = r[1].toDouble(), x1 = r[2].toDouble(), y1 = r[3].toDouble();
    poly([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)], _rgb(_slab));
    poly([P(x1, y0), P(x1, y1), P(x1, y1, -.5), P(x1, y0, -.5)], _rgb(_slab, .5));
    poly([P(x0, y1), P(x1, y1), P(x1, y1, -.5), P(x0, y1, -.5)], _rgb(_slab, .7));
    if (k >= 7) {
      for (var i = r[0]; i <= r[2]; i++) {
        line([P(i, y0), P(i, y1)], _rgb(i % 6 == 0 ? _grid6 : _grid), 1);
      }
      for (var i = r[1]; i <= r[3]; i++) {
        line([P(x0, i), P(x1, i)], _rgb(i % 6 == 0 ? _grid6 : _grid), 1);
      }
    }

    // plataformas fundidas (semana / mês / ano)
    final cov = <int, int>{};
    for (final pl in plats) {
      for (var xx = 0; xx < pl.w; xx++) {
        for (var yy = 0; yy < pl.h; yy++) {
          final key = cellKey(pl.gx + xx, pl.gy + yy);
          cov[key] = max(pl.kind, cov[key] ?? -1);
        }
      }
      final z = const [0.05, 0.1, 0.16][pl.kind];
      box(pl.gx.toDouble(), pl.gy.toDouble(), (pl.gx + pl.w).toDouble(), (pl.gy + pl.h).toDouble(), 0, z, _platFill[pl.kind], P);
      line([P(pl.gx, pl.gy, z), P(pl.gx + pl.w, pl.gy, z), P(pl.gx + pl.w, pl.gy + pl.h, z), P(pl.gx, pl.gy + pl.h, z), P(pl.gx, pl.gy, z)], _rgb(_platGlow[pl.kind]), 1.0 + pl.kind);
    }
    double zof(int x, int y) => const [0.02, 0.05, 0.1, 0.16][(cov[cellKey(x, y)] ?? -1) + 1];

    // malha viária: asfalto em toda a grade; setas/tracejado onde há lotes (mão única: ↘ ao longo de x e ↙ ao longo de y)
    final hw = Catalog.roadW / 2;
    final marks = k >= 9;
    for (var j = r[1]; j <= r[3]; j++) {
      final ya = max(y0, j - hw), yb = min(y1, j + hw);
      for (var x = r[0]; x < r[2]; x++) {
        final z = max(zof(x, j - 1), zof(x, j));
        poly([P(x, ya, z), P(x + 1, ya, z), P(x + 1, yb, z), P(x, yb, z)], _rgb(_asph));
        if (marks && (g.dev.contains(cellKey(x, j - 1)) || g.dev.contains(cellKey(x, j)))) {
          if ((x + j) % 2 == 0) {
            poly([P(x + .63, j, z + .004), P(x + .42, j - .07, z + .004), P(x + .42, j + .07, z + .004)], _rgb(_arrow));
          } else {
            line([P(x + .3, j, z + .004), P(x + .7, j, z + .004)], _rgb(_dash), 1);
          }
        }
      }
    }
    for (var i = r[0]; i <= r[2]; i++) {
      final xa = max(x0, i - hw), xb = min(x1, i + hw);
      for (var y = r[1]; y < r[3]; y++) {
        final z = max(zof(i - 1, y), zof(i, y));
        poly([P(xa, y, z), P(xb, y, z), P(xb, y + 1, z), P(xa, y + 1, z)], _rgb(_asph));
        if (marks && (g.dev.contains(cellKey(i - 1, y)) || g.dev.contains(cellKey(i, y)))) {
          if ((i + y) % 2 == 0) {
            poly([P(i, y + .63, z + .004), P(i - .07, y + .42, z + .004), P(i + .07, y + .42, z + .004)], _rgb(_arrow));
          } else {
            line([P(i, y + .3, z + .004), P(i, y + .7, z + .004)], _rgb(_dash), 1);
          }
        }
      }
    }

    // objetos (lotes, prédios, praças, carros) ordenados por profundidade
    final objs = <_Obj>[];
    final tops = <int, Offset>{};
    final m = Catalog.street / 2;
    final glowYear = city.jn() == Catalog.per;
    void lamp(double x, double y, double z) {
      line([P(x, y, z), P(x, y, z + .16)], _rgb(const [89, 96, 127]), 1);
      canvas.drawCircle(P(x, y, z + .17), max(1.2, k * .05), Paint()..color = _rgb(glowYear ? const [255, 240, 176] : const [255, 210, 122]));
    }

    void lot(double x, double y, double z, List<int> col) {
      Offset q(num a, num b, [num e = 0]) => P(a, b, e + z);
      box(x + m, y + m, x + 1 - m, y + 1 - m, 0, .02, col, q);
    }

    for (final d in g.days) {
      if (!(d.x >= r[0] && d.x < r[2] && d.y >= r[1] && d.y < r[3])) continue;
      final x = d.x.toDouble(), y = d.y.toDouble(), z = zof(d.x, d.y);
      final t = city.tile(d.i);
      final idx = d.i;
      objs.add(_Obj(x + y + 1, () {
        lot(x, y, z, _lotC);
        lamp(x + m - .02, y + 1 - m + .02, z);
        lamp(x + 1 - m + .02, y + m - .02, z);
        final key = (t == null || t.b == null) ? null : cat.buildingKey(t.b!, t.lv);
        if (key == null) {
          final pts = [P(x + .3, y + .3, z + .03), P(x + .7, y + .3, z + .03), P(x + .7, y + .7, z + .03), P(x + .3, y + .7, z + .03), P(x + .3, y + .3, z + .03)];
          line(pts, Color.fromARGB((120 + 80 * sin(pulse)).round(), 53, 224, 255), 2);
        } else {
          final dst = _sprite(canvas, key, P(x + .5, y + .5, z + .02), k);
          if (dst != null) tops[idx] = Offset(dst.center.dx, dst.top);
        }
      }));
    }
    for (final sp in g.spare) {
      if (!(sp[0] >= r[0] && sp[0] < r[2] && sp[1] >= r[1] && sp[1] < r[3])) continue;
      final x = sp[0].toDouble(), y = sp[1].toDouble(), z = zof(sp[0], sp[1]);
      final st = city.s.pz['${sp[0]},${sp[1]}'];
      objs.add(_Obj(x + y + 1, () {
        lot(x, y, z, st != null ? _spare : _lotC);
        if (st != null) _sprite(canvas, 'plazas/$st', P(x + .5, y + .5, z + .02), k, plaza: true);
      }));
    }
    for (final c in cars) {
      final x = c.x + c.dx * c.t, y = c.y + c.dy * c.t;
      if (x < r[0] || x > r[2] || y < r[1] || y > r[3]) continue;
      objs.add(_Obj(x + y + .02, () => _car(canvas, c, P(x, y, .01), k)));
    }
    objs.sort((a, b) => a.depth.compareTo(b.depth));
    for (final o in objs) {
      o.draw();
    }

    // seleção e prédio em foco
    final ys = city.ys();
    final sel = city.s.sel;
    if (sel >= ys && sel < city.D) {
      final p = city.pos(sel - ys);
      if (p[0] >= r[0] && p[0] < r[2] && p[1] >= r[1] && p[1] < r[3]) {
        final a = (150 + 105 * sin(pulse)).round().clamp(0, 255);
        line([P(p[0] + .1, p[1] + .1, .04), P(p[0] + .9, p[1] + .1, .04), P(p[0] + .9, p[1] + .9, .04), P(p[0] + .1, p[1] + .9, .04), P(p[0] + .1, p[1] + .1, .04)], Color.fromARGB(a, 242, 184, 75), 2);
      }
    }
    for (final i in {city.s.sel, city.s.focus}) {
      final t = city.tile(i);
      final top = tops[i];
      if (t != null && t.b != null && top != null) {
        _label(canvas, 'Nv ${t.lv}/${cat.building(t.b!).maxLevel}', Offset(top.dx, top.dy - 10), i == city.s.focus ? const Color(0xFF35E0FF) : kGoldColor);
      }
    }
  }

  static const kGoldColor = Color(0xFFF2B84B);

  void _car(Canvas canvas, Car car, Offset at, double k) {
    final key = 'cars/${car.m}';
    final im = images[key];
    final meta = cat.meta[key];
    if (im == null || meta == null) return;
    final s = k * .8 / meta.w;
    final w = meta.w * s, h = meta.h * s;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (car.dx != 0) canvas.scale(-1, 1); // a arte só tem a vista frontal: ↙ normal, ↘ espelhado
    canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH(-w / 2, -h * .8, w, h), Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CityPainter oldDelegate) => true; // animação contínua (carros e pulso)
}
