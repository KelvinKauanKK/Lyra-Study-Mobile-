import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/clock.dart';
import '../core/schedule.dart';
import '../core/tasks.dart';
import '../core/util.dart';
import '../state/app_state.dart';
import 'theme.dart';

const _meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];

/// Cronograma: grade da semana + calendário do mês. Tarefas/lembretes personalizados aparecem nos dois, com os mesmos chips dos estudos.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool calendar = false;
  DateTime month = DateTime(AppClock.today().year, AppClock.today().month);

  Future<void> _addFlow(BuildContext context) async {
    final today = AppClock.today();
    final d = await showDatePicker(
        context: context, initialDate: today, firstDate: DateTime(today.year - 1), lastDate: DateTime(today.year + 5), helpText: 'Escolha o dia (qualquer data)');
    if (d == null || !context.mounted) return;
    await showDialog<void>(context: context, builder: (_) => TaskDialog(day: d));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.subjects.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Nenhum cronograma ainda.'),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => showScheduleSetup(context), child: const Text('Montar cronograma')),
      ]));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addFlow(context), icon: const Icon(Icons.add_alert), label: const Text('Tarefa / lembrete')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Row(children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Semana')), ButtonSegment(value: true, label: Text('Calendário'))],
              selected: {calendar},
              onSelectionChanged: (s) => setState(() => calendar = s.first),
            ),
            const Spacer(),
            TextButton(onPressed: () => showScheduleSetup(context), child: const Text('Reconfigurar')),
          ]),
        ),
        Expanded(child: calendar ? _calendar(app) : _week(app)),
      ]),
    );
  }

  // ---------- semana ----------
  Widget _week(AppState app) {
    final today = AppClock.today();
    final mon = app.weekStart(today);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 90), children: [
      for (var i = 0; i < 7; i++) _dayCard(app, DateTime(mon.year, mon.month, mon.day + i), i, today),
    ]);
  }

  Widget _dayCard(AppState app, DateTime day, int i, DateTime today) {
    final items = app.schedule[dayNames[i]] ?? const <StudyTask>[];
    final tasks = app.tasksOn(day);
    final isToday = day == today;
    final iso = isoDate(day);
    final total = items.fold<int>(0, (a, t) => a + t.minutes);
    return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('${dayNames[i]} ${two(day.day)}/${two(day.month)}', style: TextStyle(fontWeight: FontWeight.bold, color: isToday ? kGold : null)),
        const Spacer(),
        Text(fmtDur(total), style: const TextStyle(color: kMuted)),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 4, children: [
        for (final t in items) MiniChip('${t.subject} · ${t.minutes}m', tagColor(t.subject)),
        for (final t in tasks) MiniChip(taskLabel(t), tagColor('🔔${t.title}')),
      ]),
      if (isToday) ...[
        const Divider(),
        for (final t in items)
          CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${t.subject} — ${fmtDur(t.minutes)}'),
              value: app.todoDone.contains('$iso|${t.subject}'),
              onChanged: (v) => app.setTodo('$iso|${t.subject}', v ?? false)),
        for (final t in tasks)
          CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(taskLabel(t)),
              value: app.todoDone.contains(taskKey(t)),
              onChanged: (v) => app.setTodo(taskKey(t), v ?? false)),
      ],
    ]));
  }

  // ---------- calendário do mês ----------
  Widget _calendar(AppState app) {
    final today = AppClock.today();
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final nDays = DateTime(month.year, month.month + 1, 0).day;
    final cells = <Widget>[for (var i = 0; i < lead; i++) const SizedBox.shrink()];
    for (var n = 1; n <= nDays; n++) {
      final dt = DateTime(month.year, month.month, n);
      final items = app.schedule[dayNames[dt.weekday - 1]] ?? const <StudyTask>[];
      final tasks = app.tasksOn(dt);
      final chips = <Widget>[
        for (final t in items) MiniChip('${t.subject} · ${t.minutes}m', tagColor(t.subject)),
        for (final t in tasks) MiniChip(taskLabel(t), tagColor('🔔${t.title}')),
      ];
      cells.add(InkWell(
        onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: kBg, builder: (_) => DaySheet(day: dt)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: dt == today ? kViolet : kEdge, width: dt == today ? 2 : 1)),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: dt == today ? kGold : null)),
              ...chips.take(3),
              if (chips.length > 3) Text('+${chips.length - 3}', style: const TextStyle(fontSize: 10, color: kMuted)),
            ]),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 90), children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
        Text('${_meses[month.month - 1]} ${month.year}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: () => setState(() => month = DateTime(today.year, today.month)), child: const Text('Hoje')),
      ]),
      Row(children: [for (final d in dayNames) Expanded(child: Center(child: Text(d, style: const TextStyle(color: kMuted, fontSize: 12))))]),
      const SizedBox(height: 4),
      GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: .5, mainAxisSpacing: 3, crossAxisSpacing: 3, children: cells),
    ]);
  }
}

/// Um dia do calendário: estudo planejado + tarefas (concluir, excluir) + adicionar.
class DaySheet extends StatefulWidget {
  const DaySheet({super.key, required this.day});
  final DateTime day;
  @override
  State<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<DaySheet> {
  final title = TextEditingController(), time = TextEditingController();
  String err = '';

  @override
  void dispose() {
    title.dispose();
    time.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    try {
      await context.read<AppState>().addTask(widget.day, title.text, time.text);
      title.clear();
      time.clear();
      setState(() => err = '');
    } on TaskException catch (e) {
      setState(() => err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = widget.day;
    final items = app.schedule[dayNames[d.weekday - 1]] ?? const <StudyTask>[];
    final tasks = app.tasksOn(d);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${dayNames[d.weekday - 1]} • ${two(d.day)}/${two(d.month)}/${d.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kGold)),
          const SizedBox(height: 8),
          const Text('Estudo planejado', style: TextStyle(fontWeight: FontWeight.bold)),
          if (items.isEmpty) const Text('Nada planejado para este dia da semana.', style: TextStyle(color: kMuted)),
          Wrap(spacing: 4, children: [for (final t in items) MiniChip('${t.subject} · ${t.minutes}m', tagColor(t.subject))]),
          const SizedBox(height: 10),
          const Text('Tarefas e lembretes', style: TextStyle(fontWeight: FontWeight.bold)),
          if (tasks.isEmpty) const Text('Nenhuma ainda.', style: TextStyle(color: kMuted)),
          for (final t in tasks)
            Row(children: [
              Expanded(
                  child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(taskLabel(t)),
                      value: app.todoDone.contains(taskKey(t)),
                      onChanged: (v) => app.setTodo(taskKey(t), v ?? false))),
              IconButton(onPressed: () => app.removeTask(t.id), icon: const Icon(Icons.delete_outline)),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: title, decoration: const InputDecoration(labelText: 'Nova tarefa ou lembrete'))),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'HH:MM'))),
            IconButton(onPressed: _add, icon: const Icon(Icons.add_circle, color: kViolet)),
          ]),
          if (err.isNotEmpty) Text(err, style: const TextStyle(color: kRed)),
        ]),
      ),
    );
  }
}

/// ➕ Tarefa / lembrete para a data escolhida no seletor de datas.
class TaskDialog extends StatefulWidget {
  const TaskDialog({super.key, required this.day});
  final DateTime day;
  @override
  State<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<TaskDialog> {
  final title = TextEditingController(), time = TextEditingController();
  String err = '';

  @override
  void dispose() {
    title.dispose();
    time.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await context.read<AppState>().addTask(widget.day, title.text, time.text);
      if (mounted) Navigator.pop(context);
    } on TaskException catch (e) {
      setState(() => err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    return AlertDialog(
      title: Text('➕ ${two(d.day)}/${two(d.month)}/${d.year}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Título (ex.: Entregar redação)')),
        TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Horário (opcional, HH:MM)')),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: kRed))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: _save, child: const Text('Salvar'))],
    );
  }
}

Future<void> showScheduleSetup(BuildContext context) => showDialog<void>(context: context, builder: (_) => const ScheduleSetupDialog());

/// Monta/reconfigura o cronograma: matérias, dificuldade (1–5), horas por dia e matérias por dia.
class ScheduleSetupDialog extends StatefulWidget {
  const ScheduleSetupDialog({super.key});
  @override
  State<ScheduleSetupDialog> createState() => _ScheduleSetupDialogState();
}

class _ScheduleSetupDialogState extends State<ScheduleSetupDialog> {
  late final TextEditingController names, hours, perDay;
  final Map<String, int> diff = {};
  String err = '';

  @override
  void initState() {
    super.initState();
    final a = context.read<AppState>();
    names = TextEditingController(text: a.subjects.keys.join(', '));
    hours = TextEditingController(text: '${a.dailyGoalH}');
    perDay = TextEditingController(text: '${a.perDay}');
    diff.addAll(a.subjects);
  }

  @override
  void dispose() {
    names.dispose();
    hours.dispose();
    perDay.dispose();
    super.dispose();
  }

  List<String> get list => names.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

  Future<void> _save() async {
    final n = list;
    final h = double.tryParse(hours.text.trim().replaceAll(',', '.'));
    final pd = int.tryParse(perDay.text.trim());
    if (n.isEmpty) return setState(() => err = 'Informe ao menos uma matéria.');
    if (h == null || h <= 0) return setState(() => err = 'Horas por dia: informe um número maior que zero.');
    if (pd == null || pd < 1) return setState(() => err = 'Matérias por dia: informe um inteiro a partir de 1.');
    await context.read<AppState>().configureSchedule({for (final s in n) s: diff[s] ?? 3}, h, pd);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('🗓 Cronograma'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: names, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Matérias (separe por vírgula)')),
            TextField(controller: hours, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Horas de estudo por dia (meta diária)')),
            TextField(controller: perDay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Matérias por dia')),
            for (final s in list)
              Row(children: [
                Expanded(flex: 2, child: Text(s, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 3, child: Slider(min: 1, max: 5, divisions: 4, value: (diff[s] ?? 3).toDouble(), label: '${diff[s] ?? 3}', onChanged: (v) => setState(() => diff[s] = v.round()))),
                Text('${diff[s] ?? 3}'),
              ]),
            if (err.isNotEmpty) Text(err, style: const TextStyle(color: kRed)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: _save, child: const Text('Salvar'))],
      );
}
