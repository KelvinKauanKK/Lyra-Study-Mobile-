import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../core/city/engine.dart';
import '../core/exam.dart';
import '../core/util.dart';
import '../state/app_state.dart';
import 'city_painter.dart';
import 'theme.dart';

/// 🕰 Modo Memória: a "foto" de cada ano concluído (rebuild pelo histórico) + os simulados e anexos daquele ano.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final hist = app.city.s.history;
    return Scaffold(
      appBar: AppBar(title: const Text('🕰 Modo Memória')),
      body: hist.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Complete os 336 dias de um ano para guardar a primeira foto da cidade.', textAlign: TextAlign.center, style: TextStyle(color: kMuted))))
          : ListView(padding: const EdgeInsets.all(10), children: [
              for (final e in hist.reversed)
                Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ano ${e['year']} • concluído em ${brDate(e['date'] as String)}', style: const TextStyle(fontWeight: FontWeight.bold, color: kGold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: CityPainter(city: CityEngine.fromHistory(e, app.catalog, app.layout), images: app.images, cars: const [], cam: CityCamera()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${(e['stats'] as Map)['days']} dias • ${fmtDur(((e['stats'] as Map)['minutes'] as num))} de estudo • ${(e['stats'] as Map)['plazas']} praça(s)', style: const TextStyle(color: kMuted)),
                  ..._exams(app, ((e['idx'] as num).toInt())),
                ])),
            ]),
    );
  }

  List<Widget> _exams(AppState app, int idx) {
    final list = app.exams.where((x) => x.cityYear == idx).toList();
    if (list.isEmpty) return [];
    return [
      const SizedBox(height: 8),
      const Text('Simulados deste ano', style: TextStyle(fontWeight: FontWeight.bold)),
      for (final x in list) ...[
        Text('• ${examName(x)} — ${x.score10.toStringAsFixed(2)}'),
        for (final a in x.attachments) TextButton(onPressed: () => OpenFilex.open(app.attachmentPath(a)), child: Text('📎 ${a.name}', overflow: TextOverflow.ellipsis)),
      ],
    ];
  }
}
