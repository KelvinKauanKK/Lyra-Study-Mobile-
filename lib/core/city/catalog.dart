import 'dart:convert';
import 'dart:math';

class BuildingModel {
  final String id, name;
  final int price, maxLevel;
  const BuildingModel(this.id, this.name, this.price, this.maxLevel);
}

class CarModel {
  final String id, name;
  final int price;
  const CarModel(this.id, this.name, this.price);
}

/// Praças: metas do MÊS (reiniciam todo mês). kind "h" = horas de estudo no mês; "d" = dias concluídos no mês.
class PlazaModel {
  final String id, name, kind;
  final int need;
  const PlazaModel(this.id, this.name, this.kind, this.need);
}

class SpriteMeta {
  final int w, h, bw;
  final double ax;
  const SpriteMeta(this.w, this.h, this.bw, this.ax);
}

class Catalog {
  // ---- urbanismo (mesmos valores do desktop) ----
  static const per = 336; // dias por ano
  static const street = 0.40;
  static const lot = 0.60;
  static const bldFill = 0.90;
  static const roadW = 0.34;
  static const traffic = 0.8;
  static const plazaEvery = 5;
  static const plazaMinUnlocked = 2;
  static const xpPerMinFallback = 4.0;

  static const cars = [
    CarModel('car_a', 'Sedan Urbano', 0),
    CarModel('car_b', 'Furgão Escolar', 0),
    CarModel('car_c', 'Esportivo GT', 600),
    CarModel('car_d', 'Esportivo RS', 900),
    CarModel('car_e', 'SUV Executivo', 1300),
    CarModel('car_f', 'Elétrico de Luxo', 2000),
  ];
  static const plazas = [
    PlazaModel('plaza_1', 'Praça dos Bancos', 'h', 1),
    PlazaModel('plaza_2', 'Praça da Fonte', 'd', 1),
    PlazaModel('plaza_3', 'Praça Jardim Real', 'd', 7),
  ];

  final List<BuildingModel> buildings;
  final Map<String, SpriteMeta> meta;
  Catalog(this.buildings, this.meta);

  /// Prédios e tamanhos dos sprites vêm de assets/city/buildings.json e meta.json (gerados pelo tools/process_assets.py do desktop).
  factory Catalog.fromJson(String buildingsJson, String metaJson) {
    final b = (jsonDecode(buildingsJson)['models'] as List)
        .map((m) => BuildingModel(m['id'] as String, m['n'] as String, (m['p'] as num).toInt(), (m['max'] as num).toInt()))
        .toList();
    final mj = jsonDecode(metaJson) as Map<String, dynamic>;
    final meta = {
      for (final e in mj.entries)
        e.key: SpriteMeta((e.value['w'] as num).toInt(), (e.value['h'] as num).toInt(), (e.value['bw'] as num).toInt(), (e.value['ax'] as num).toDouble())
    };
    return Catalog(b, meta);
  }

  BuildingModel building(String id) => buildings.firstWhere((b) => b.id == id);
  CarModel car(String id) => cars.firstWhere((c) => c.id == id);
  PlazaModel plaza(String id) => plazas.firstWhere((p) => p.id == id);

  /// Sprite do prédio conforme o NÍVEL atual (cai para o maior nível existente se faltar algum arquivo).
  String? buildingKey(String id, int lv) {
    final b = building(id);
    for (var l = min(lv, b.maxLevel); l >= 1; l--) {
      final k = 'buildings/${id}_$l';
      if (meta.containsKey(k)) return k;
    }
    return null;
  }
}
