import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/clock.dart';
import '../core/economy.dart';
import '../state/app_state.dart';
import 'theme.dart';

void showAdminSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: kBg, builder: (_) => const FractionallySizedBox(heightFactor: .92, child: AdminSheet()));

/// 🛠 Admin (testes): estudo e pontos instantâneos, nível, avanço de calendário (dias/mês) e reset da cidade.
class AdminSheet extends StatefulWidget {
  const AdminSheet({super.key});
  @override
  State<AdminSheet> createState() => _AdminSheetState();
}

class _AdminSheetState extends State<AdminSheet> {
  final minutes = TextEditingController(text: '60'), pts = TextEditingController(text: '${Economy.devBonus}'), levels = TextEditingController(text: '1'), days = TextEditingController(text: '7');
  bool credit = true;
  String subject = 'Geral';

  @override
  void dispose() {
    for (final c in [minutes, pts, levels, days]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Widget _row(String label, TextEditingController c, String button, VoidCallback on) => Row(children: [
        Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label))),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: on, child: Text(button)),
      ]);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final names = [...app.subjects.keys, 'Geral'];
    final today = AppClock.today();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
        child: Row(children: [
          const Text('🛠 Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kGold)),
          const Spacer(),
          TextButton(
              onPressed: () {
                app.logoutAdmin();
                Navigator.pop(context);
              },
              child: const Text('Sair do Admin')),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text('Data do app: ${today.day}/${today.month}/${today.year} (deslocamento ${AppClock.offsetDays} dia(s))', style: const TextStyle(color: kMuted)),
          const SizedBox(height: 8),
          DropdownButton<String>(isExpanded: true, value: names.contains(subject) ? subject : 'Geral', items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))], onChanged: (v) => setState(() => subject = v ?? 'Geral')),
          _row('Minutos de estudo', minutes, 'Registrar', () => app.adminAddStudy(_n(minutes), subject)),
          _row('Pontos', pts, 'Adicionar', () => app.adminAddPoints(_n(pts))),
          _row('Níveis do prédio em foco', levels, 'Subir', () => app.adminLevelUp(_n(levels))),
          const Divider(height: 28),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Avanço com estudo creditado (sem pontos)'), value: credit, onChanged: (v) => setState(() => credit = v)),
          _row('Dias a avançar', days, 'Avançar', () => app.adminAdvanceDays(_n(days), credit)),
          const SizedBox(height: 6),
          FilledButton.tonal(
              onPressed: () {
                final t = AppClock.today();
                final n = DateTime.utc(t.year, t.month + 1, 1).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
                app.adminAdvanceDays(n, credit);
              },
              child: const Text('Avançar para o próximo mês')),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: app.adminRestoreClock, child: const Text('Restaurar a data real')),
          const Divider(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () async {
              final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                        title: const Text('Resetar a cidade?'),
                        content: const Text('A cidade e as sessões simuladas serão apagadas. Simulados, anexos e pontos continuam.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Resetar'))],
                      ));
              if (ok == true) await app.adminResetCity();
            },
            child: const Text('Resetar cidade'),
          ),
        ]),
      ),
    ]);
  }
}
