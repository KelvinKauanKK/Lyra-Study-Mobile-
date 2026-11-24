import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../core/exam.dart';
import '../core/util.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Simulados: lista (mais novo primeiro), busca por nome sem acento, 10 por página, anexos e registro completo.
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});
  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  String query = '';
  int page = 1;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.exams;
    final pg = paginate(filterExams(all, query), page);
    final last = all.length > 8 ? all.sublist(all.length - 8) : all;
    final avg = all.isEmpty ? 0.0 : all.fold<double>(0, (a, e) => a + e.score10) / all.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ExamFormScreen())), icon: const Icon(Icons.add), label: const Text('Registrar simulado')),
      body: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 90), children: [
        Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${all.length} simulado(s) • média ${avg.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (last.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final e in last)
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text(e.score10.toStringAsFixed(1), style: const TextStyle(fontSize: 10)), Container(height: 6 + e.score10 * 6, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: kViolet, borderRadius: BorderRadius.circular(4)))])),
              ]),
            ),
          ],
        ])),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar pelo nome da prova'), onChanged: (v) => setState(() { query = v; page = 1; })),
        const SizedBox(height: 6),
        if (pg.items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nenhum simulado encontrado.', style: TextStyle(color: kMuted)))),
        for (final it in pg.items) _card(context, app, it),
        if (pg.pages > 1) Wrap(spacing: 6, children: [for (var p = 1; p <= pg.pages; p++) ChoiceChip(label: Text('$p'), selected: p == pg.page, onSelected: (_) => setState(() => page = p))]),
      ]),
    );
  }

  Widget _card(BuildContext context, AppState app, IndexedExam it) {
    final e = it.exam;
    return Panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(examName(e), style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${brDate(e.day)} • ${e.hits}/${e.scale} acertos${e.annulled > 0 ? ' • ${e.annulled} anulada(s)' : ''} • nota ${e.score10.toStringAsFixed(2)}'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final en in e.subjects.entries)
            Text('${en.key}: ${en.value.hits}/${en.value.total}${en.value.annulled > 0 ? ' (${en.value.annulled} anulada(s))' : ''} • ${en.value.score.toStringAsFixed(2)}${e.weighted ? ' • peso ${en.value.weight}' : ''}'),
          for (final a in e.attachments)
            Row(children: [
              Expanded(child: Text('📎 ${a.name}', overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: () => OpenFilex.open(app.attachmentPath(a)), child: const Text('Abrir')),
              TextButton(
                  onPressed: () async {
                    final bytes = await File(app.attachmentPath(a)).readAsBytes();
                    await FilePicker.platform.saveFile(dialogTitle: 'Salvar anexo', fileName: a.name, bytes: bytes);
                  },
                  child: const Text('Baixar')),
            ]),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(title: const Text('Excluir simulado?'), content: const Text('O registro e os anexos serão apagados.'), actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
                            ]));
                    if (ok == true) await app.deleteExam(it.index);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir'))),
        ],
      ),
    );
  }
}

class _RowCtl {
  final total = TextEditingController(), hits = TextEditingController(), ann = TextEditingController(), annHit = TextEditingController(), weight = TextEditingController(text: '1');
  bool annTouched = false;
  _RowCtl() {
    ann.addListener(() {
      if (!annTouched) annHit.text = ann.text; // por padrão, as anuladas contam como acertadas (editável)
    });
  }
  void dispose() {
    for (final c in [total, hits, ann, annHit, weight]) {
      c.dispose();
    }
  }
}

/// Registro completo: nome da prova, máximo de questões, matérias (do cronograma ou avulsas), anuladas, pesos e anexos.
class ExamFormScreen extends StatefulWidget {
  const ExamFormScreen({super.key});
  @override
  State<ExamFormScreen> createState() => _ExamFormScreenState();
}

class _ExamFormScreenState extends State<ExamFormScreen> {
  final name = TextEditingController(), maxQ = TextEditingController(), extra = TextEditingController();
  final Map<String, _RowCtl> rows = {};
  final List<String> extraNames = [];
  final List<String> files = [];
  bool weighted = false, saving = false;
  String err = '';

  @override
  void dispose() {
    name.dispose();
    maxQ.dispose();
    extra.dispose();
    for (final r in rows.values) {
      r.dispose();
    }
    super.dispose();
  }

  void _toggle(String s) => setState(() {
        if (rows.containsKey(s)) {
          rows.remove(s)?.dispose();
        } else {
          rows[s] = _RowCtl();
        }
      });

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _distribute() {
    final mq = int.tryParse(maxQ.text.trim()) ?? 0;
    if (rows.isEmpty || mq < 1) return;
    final n = rows.length;
    var i = 0;
    for (final r in rows.values) {
      r.total.text = '${mq ~/ n + (i < mq % n ? 1 : 0)}';
      i++;
    }
    setState(() {});
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null) return;
    setState(() => files.addAll(res.paths.whereType<String>()));
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final list = [
      for (final e in rows.entries)
        SubjectRow(e.key,
            total: _i(e.value.total), hits: _i(e.value.hits), annulled: _i(e.value.ann), annulledHit: _i(e.value.annHit), weight: double.tryParse(e.value.weight.text.trim().replaceAll(',', '.')) ?? 1)
    ];
    setState(() {
      saving = true;
      err = '';
    });
    try {
      await app.registerExam(name: name.text, maxQ: _i(maxQ), rows: list, weighted: weighted, files: files);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, '✅ Simulado registrado');
    } on ExamException catch (e) {
      setState(() {
        err = e.message;
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final soma = rows.values.fold<int>(0, (a, r) => a + _i(r.total));
    final mq = _i(maxQ);
    final names = [...app.subjects.keys, ...extraNames];
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar simulado')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome da prova (obrigatório)')),
        TextField(controller: maxQ, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Máximo de questões da prova')),
        const SizedBox(height: 10),
        const Text('Matérias da prova', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 6, children: [for (final s in names) FilterChip(label: Text(s), selected: rows.containsKey(s), onSelected: (_) => _toggle(s))]),
        Row(children: [
          Expanded(child: TextField(controller: extra, decoration: const InputDecoration(labelText: 'Matéria avulsa (só neste simulado)'))),
          IconButton(
              onPressed: () {
                final t = extra.text.trim();
                if (t.isEmpty) return;
                setState(() {
                  if (!extraNames.contains(t) && !app.subjects.containsKey(t)) extraNames.add(t);
                  rows.putIfAbsent(t, () => _RowCtl());
                  extra.clear();
                });
              },
              icon: const Icon(Icons.add_circle, color: kViolet)),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Matérias com pesos diferentes'), value: weighted, onChanged: (v) => setState(() => weighted = v)),
        for (final e in rows.entries) _subjectCard(e.key, e.value),
        if (rows.isNotEmpty)
          Row(children: [
            Expanded(child: Text('Soma das questões: $soma / $mq', style: TextStyle(color: soma == mq && mq > 0 ? kTeal : kRed, fontWeight: FontWeight.bold))),
            TextButton(onPressed: _distribute, child: const Text('Distribuir igualmente')),
          ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.attach_file), label: const Text('Anexar arquivos')),
          for (final f in files) Chip(label: Text(f.split('/').last, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => files.remove(f))),
        ]),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: kRed))),
        const SizedBox(height: 10),
        FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Salvando…' : 'Salvar simulado')),
      ]),
    );
  }

  Widget _subjectCard(String s, _RowCtl c) {
    final t = _i(c.total), h = _i(c.hits), a = _i(c.ann), ah = _i(c.annHit);
    final ok = t >= 1 && h >= 0 && h <= t && a >= 0 && a <= t && ah >= 0 && ah <= (a < h ? a : h);
    final adj = ok ? adjust(t, h, a, ah) : null;
    Widget f(String label, TextEditingController ctl, {bool dec = false, void Function(String)? on}) => Expanded(
        child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextField(controller: ctl, keyboardType: dec ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number, onChanged: (v) { on?.call(v); setState(() {}); }, decoration: InputDecoration(labelText: label, isDense: true))));
    return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Row(children: [f('Questões', c.total), f('Acertos', c.hits), f('Anuladas', c.ann)]),
      const SizedBox(height: 6),
      Row(children: [f('Acertei das anuladas', c.annHit, on: (_) => c.annTouched = true), if (weighted) f('Peso', c.weight, dec: true)]),
      if (adj != null && adj[1] > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('→ ${adj[0]}/${adj[1]} • nota ${(adj[0] / adj[1] * 10).toStringAsFixed(2)}', style: const TextStyle(color: kTeal))),
    ]));
  }
}
