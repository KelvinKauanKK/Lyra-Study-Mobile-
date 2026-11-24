import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:provider/provider.dart';
import '../core/analysis.dart';
import '../core/clock.dart';
import '../core/util.dart';
import '../data/backup.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Desempenho: metas de hoje/semana, análise dos últimos 3 simulados e reajuste das dificuldades.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final today = AppClock.today();
    final g = app.goalMin();
    final got = app.studiedOn(today);
    final wk = app.weekMinutes(today);
    final rows = analyze(app.exams, app.subjects, onlyOfficial: false); // aqui aparecem TAMBÉM as matérias avulsas
    return ListView(padding: const EdgeInsets.all(10), children: [
      Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎯 Metas', style: TextStyle(fontWeight: FontWeight.bold)),
        LabeledBar('Hoje', g > 0 ? got / g : 0, right: '${fmtDur(got)} / ${fmtDur(g)}'),
        LabeledBar('Semana', g > 0 ? wk / (g * 7) : 0, right: '${fmtDur(wk)} / ${fmtDur(g * 7)}', color: kViolet),
        Text('Estudo Geral hoje: ${fmtDur(app.generalOn(today))} (já incluído no total)', style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text('⭐ ${app.points} pontos', style: const TextStyle(color: kGold, fontWeight: FontWeight.bold)),
      ])),
      Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📊 Últimos 3 simulados', style: TextStyle(fontWeight: FontWeight.bold)),
        if (rows.isEmpty) const Text('Registre simulados para ver a análise por matéria.', style: TextStyle(color: kMuted)),
        for (final r in rows)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(app.subjects.containsKey(r.subject) ? r.subject : '${r.subject} (fora do cronograma)', overflow: TextOverflow.ellipsis)),
                Text(r.avg.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text(r.trend == 0 ? '—' : (r.trend > 0 ? '▲ ${r.trend.toStringAsFixed(1)}' : '▼ ${(-r.trend).toStringAsFixed(1)}'), style: TextStyle(color: r.trend >= 0 ? kTeal : kRed)),
              ])),
      ])),
      FilledButton.icon(onPressed: app.exams.isEmpty ? null : () => _propose(context, app), icon: const Icon(Icons.tune), label: const Text('Reajustar dificuldades (últimos 3 simulados)')),
      const Padding(padding: EdgeInsets.all(8), child: Text('O reajuste considera só as matérias do cronograma; matérias avulsas de um simulado nunca entram na grade.', style: TextStyle(color: kMuted, fontSize: 12))),
      Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💾 Dados do desktop', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('Importe o backup (.zip) gerado no computador com tools/export_mobile.py. Ele substitui os dados deste aparelho.', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 6),
        OutlinedButton.icon(onPressed: () => _import(context, app), icon: const Icon(Icons.upload_file), label: const Text('Importar backup (.zip)')),
      ])),
    ]);
  }

  Future<void> _import(BuildContext context, AppState app) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final path = res?.files.single.path;
    if (path == null || !context.mounted) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Substituir os dados deste aparelho?'),
              content: const Text('O banco atual será trocado pelo do backup (a validação é feita antes). O app fecha em seguida; abra-o de novo.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Importar'))],
            ));
    if (ok != true || !context.mounted) return;
    try {
      await importBackup(app.db, path);
      await SystemNavigator.pop();
    } on BackupException catch (e) {
      if (context.mounted) toast(context, 'Importação cancelada: ${e.message}');
    }
  }

  Future<void> _propose(BuildContext context, AppState app) async {
    final pr = app.proposal();
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Reajuste proposto'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (pr.changes.isEmpty) const Text('Nenhuma dificuldade precisa mudar.'),
                for (final ch in pr.changes) Text('${ch.subject}: ${ch.oldDifficulty} → ${ch.newDifficulty}  (média ${ch.avg.toStringAsFixed(1)})'),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(pr.changes.isEmpty ? 'Fechar' : 'Manter')),
                if (pr.changes.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aplicar e refazer cronograma')),
              ],
            ));
    if (ok == true) await app.applyProposal(pr);
  }
}
