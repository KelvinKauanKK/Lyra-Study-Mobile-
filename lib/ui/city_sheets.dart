import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/city/catalog.dart';
import '../core/util.dart';
import '../state/app_state.dart';
import 'theme.dart';

void showShopSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: kBg, builder: (_) => const FractionallySizedBox(heightFactor: .92, child: ShopSheet()));

void showFunctionsSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: kBg, builder: (_) => const FractionallySizedBox(heightFactor: .92, child: FunctionsSheet()));

Widget _header(BuildContext c, String title, [String right = '']) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGold)),
        const Spacer(),
        Text(right, style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
      ]),
    );

/// 🛒 Loja (overlay): prédios, veículos e praças.
class ShopSheet extends StatelessWidget {
  const ShopSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        _header(context, '🛒 Loja da cidade', '⭐ ${app.points} pts'),
        const TabBar(tabs: [Tab(text: 'Prédios'), Tab(text: 'Veículos'), Tab(text: 'Praças')]),
        Expanded(child: TabBarView(children: [_buildings(app), _cars(app), _plazas(app)])),
      ]),
    );
  }

  Widget _buy(AppState app, String kind, String id, int price, bool own) => own
      ? const Text('✔ Desbloqueado', style: TextStyle(color: kTeal))
      : FilledButton(onPressed: app.points >= price ? () => app.buy(kind, id) : null, child: Text('Comprar • $price pts'));

  Widget _thumbs(AppState app, List<String> keys, double h) => Row(children: [
        for (final k in keys)
          if (app.images[k] != null) Padding(padding: const EdgeInsets.only(right: 4), child: RawImage(image: app.images[k], height: h, fit: BoxFit.contain)),
      ]);

  Widget _buildings(AppState app) => ListView(padding: const EdgeInsets.all(10), children: [
        for (final b in app.catalog.buildings)
          Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: _thumbs(app, [for (var l = 1; l <= b.maxLevel; l++) 'buildings/${b.id}_$l'], 80)),
            const SizedBox(height: 6),
            Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Níveis 1–${b.maxLevel} • ${b.price == 0 ? 'Grátis' : '${b.price} pts'}', style: const TextStyle(color: kMuted)),
            _buy(app, 'b', b.id, b.price, app.city.s.ob.contains(b.id)),
          ])),
      ]);

  Widget _cars(AppState app) => ListView(padding: const EdgeInsets.all(10), children: [
        for (final c in Catalog.cars)
          Panel(
              child: Row(children: [
            _thumbs(app, ['cars/${c.id}'], 56),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)), Text(c.price == 0 ? 'Grátis' : '${c.price} pts • Premium', style: const TextStyle(color: kMuted))])),
            _buy(app, 'c', c.id, c.price, app.city.s.oc.contains(c.id)),
          ])),
      ]);

  Widget _plazas(AppState app) {
    final c = app.city;
    final left = (Catalog.plazaEvery - c.s.since).clamp(0, Catalog.plazaEvery);
    final n = c.styles().length;
    return ListView(padding: const EdgeInsets.all(10), children: [
      Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🗓 Metas do mês', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('O progresso e o acesso reiniciam todo mês (as praças já construídas ficam no mapa).', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(n >= Catalog.plazaMinUnlocked ? '🌳 Nova praça aleatória em $left dia(s).' : 'Libere ${Catalog.plazaMinUnlocked} praças no mês para ganhar uma nova a cada ${Catalog.plazaEvery} dias.', style: const TextStyle(color: kGold)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final opt in ['auto', ...c.styles()])
            ChoiceChip(
              label: Text(opt == 'auto' ? '🎲 Aleatório' : c.cat.plaza(opt).name),
              selected: c.s.plaza == opt,
              onSelected: (_) {
                c.s.plaza = opt;
                app.cityChanged();
              },
            ),
        ]),
      ])),
      for (final p in c.plazaProgress())
        Panel(
            child: Row(children: [
          _thumbs(app, ['plazas/${p.plaza.id}'], 64),
          const SizedBox(width: 10),
          Expanded(
              child: LabeledBar(p.plaza.name, p.value / p.need,
                  color: p.done ? kTeal : kViolet,
                  right: p.done ? '✔ liberada' : (p.plaza.kind == 'h' ? '${fmtDur(p.value * 60)} / ${fmtDur(p.need * 60)}' : '${p.value.toInt()}/${p.need} dia(s)'))),
        ])),
    ]);
  }
}

/// ⚙ Funções (overlay): Função de Território, Modo Foco, Fluxo Automático e Quadrado Selecionado.
class FunctionsSheet extends StatelessWidget {
  const FunctionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = app.city, s = c.s, jn = c.jn();
    final cand = c.candidates();
    final t = c.tile(s.focus);
    final sel = c.tile(s.sel);
    String candLabel(int i) {
      final tt = c.tile(i)!;
      return 'Dia ${i + 1} — ${c.cat.building(tt.b!).name} (Nv ${tt.lv}/${c.cat.building(tt.b!).maxLevel})';
    }

    return Column(children: [
      _header(context, '⚙ Funções'),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(10), children: [
          Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🏙 Função de Território', style: TextStyle(fontWeight: FontWeight.bold)),
            LabeledBar('Dia → Semana (${jn % 7}/7)', (jn % 7) / 7),
            LabeledBar('Semana → Mês (${(jn ~/ 7) % 4}/4)', ((jn ~/ 7) % 4) / 4),
            LabeledBar('Mês → Ano (${jn ~/ 28}/12)', jn / Catalog.per, color: kGold),
          ])),
          Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🎯 Modo Foco', style: TextStyle(fontWeight: FontWeight.bold)),
            if (cand.isEmpty) const Text('Construa um prédio numa fundação para direcionar o XP.', style: TextStyle(color: kMuted)),
            if (cand.isNotEmpty)
              DropdownButton<int>(
                isExpanded: true,
                value: cand.contains(s.focus) ? s.focus : cand.first,
                items: [for (final i in cand) DropdownMenuItem(value: i, child: Text(candLabel(i), overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  s.focus = v ?? s.focus;
                  app.cityChanged();
                },
              ),
            if (t != null && t.b != null && t.lv < c.cat.building(t.b!).maxLevel) LabeledBar('XP ${t.xp.toInt()}/${100 * t.lv}', t.xp / (100 * t.lv)),
          ])),
          Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚙ Fluxo automático', style: TextStyle(fontWeight: FontWeight.bold)),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Construir sozinho a cada novo dia'), value: s.auto, onChanged: (v) { s.auto = v; app.cityChanged(); }),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('🎲 Prédio do dia aleatório'), value: s.rand, onChanged: (v) { s.rand = v; app.cityChanged(); }),
            if (s.ob.isNotEmpty)
              DropdownButton<String>(
                isExpanded: true,
                value: s.ob.contains(s.model) ? s.model : s.ob.first,
                items: [for (final id in s.ob) DropdownMenuItem(value: id, child: Text(c.cat.building(id).name))],
                onChanged: (v) { s.model = v ?? s.model; app.cityChanged(); },
              ),
          ])),
          Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📍 Quadrado selecionado', style: TextStyle(fontWeight: FontWeight.bold)),
            if (sel == null) const Text('Toque num quadrado do mapa.', style: TextStyle(color: kMuted)),
            if (sel != null && sel.b != null) Text('Dia ${s.sel + 1} • ${c.cat.building(sel.b!).name} • nível ${sel.lv}/${c.cat.building(sel.b!).maxLevel}'),
            if (sel != null && sel.b == null) ...[
              Text('Dia ${s.sel + 1} • fundação livre', style: const TextStyle(color: kMuted)),
              Wrap(spacing: 6, children: [
                FilledButton(onPressed: () => app.buildAt(s.sel), child: const Text('🎲 Aleatório')),
                for (final id in s.ob) FilledButton.tonal(onPressed: () => app.buildAt(s.sel, id), child: Text(c.cat.building(id).name)),
              ]),
            ],
          ])),
        ]),
      ),
    ]);
  }
}
