import 'dart:math';
import 'exam.dart';

class AnalysisRow {
  final String subject;
  final double avg, last, trend, wn, prio;
  final int n;
  const AnalysisRow(this.subject, this.avg, this.last, this.trend, this.n, this.wn, this.prio);
}

class Change {
  final String subject;
  final int oldDifficulty, newDifficulty;
  final double avg, trend, wn;
  const Change(this.subject, this.oldDifficulty, this.newDifficulty, this.avg, this.trend, this.wn);
}

class Proposal {
  final Map<String, int> subjects;
  final List<Change> changes;
  const Proposal(this.subjects, this.changes);
}

Map<String, double> subScores(Exam e) => {for (final en in e.subjects.entries) en.key: en.value.score};

/// Peso de cada matéria na prova (1 quando a prova não tinha pesos diferentes). [only] = matérias consideradas.
Map<String, double> subWeights(Exam e, [Set<String>? only]) {
  final w = {for (final en in e.subjects.entries) en.key: e.weighted ? (en.value.weight == 0 ? 1.0 : en.value.weight) : 1.0};
  if (only == null) return w;
  return {for (final en in w.entries) if (only.contains(en.key)) en.key: en.value};
}

/// Peso relativo à média da prova. Com [only], matérias de fora da grade não entram na média.
double wnorm(Exam e, String s, [Set<String>? only]) {
  final w = subWeights(e, only);
  final m = w.isEmpty ? 1.0 : w.values.fold<double>(0, (a, b) => a + b) / w.length;
  return m == 0 ? 1.0 : (w[s] ?? 1.0) / m;
}

/// Últimos [last] simulados: nota média 0-10, tendência e PRIORIDADE = taxa de erro x peso relativo.
/// onlyOfficial=true (usado ao gerar/recalcular o cronograma): IGNORA qualquer matéria fora da grade oficial.
List<AnalysisRow> analyze(List<Exam> exams, Map<String, int> official, {int last = 3, bool onlyOfficial = true}) {
  final sims = exams.length > last ? exams.sublist(exams.length - last) : exams;
  final off = onlyOfficial ? official.keys.toSet() : null;
  final names = <String>[];
  for (final x in sims) {
    for (final k in x.subjects.keys) {
      if (!names.contains(k) && (off == null || off.contains(k))) names.add(k);
    }
  }
  final out = <AnalysisRow>[];
  for (final s in names) {
    final scores = <double>[];
    var wsum = 0.0;
    for (final x in sims) {
      if (!x.subjects.containsKey(s)) continue;
      scores.add(x.subjects[s]!.score);
      wsum += wnorm(x, s, off);
    }
    final avg = scores.fold<double>(0, (a, b) => a + b) / scores.length;
    final wn = wsum / scores.length;
    final trend = scores.length > 1 ? scores.last - scores[scores.length - 2] : 0.0;
    out.add(AnalysisRow(s, avg, scores.last, trend, scores.length, wn, (1 - avg / 10) * wn));
  }
  final idx = {for (var i = 0; i < out.length; i++) out[i].subject: i};
  out.sort((a, b) {
    final c = b.prio.compareTo(a.prio);
    if (c != 0) return c;
    final d = a.avg.compareTo(b.avg);
    if (d != 0) return d;
    return idx[a.subject]!.compareTo(idx[b.subject]!);
  });
  return out;
}

/// Dificuldades (1-5) calculadas ESTRITAMENTE com os últimos 3 simulados: 1 + 4 x prioridade (máx. 5), com ±0,5 se a nota caiu/subiu muito.
Proposal proposeAdjustment(List<Exam> exams, Map<String, int> subjects) {
  final next = Map<String, int>.from(subjects);
  final changes = <Change>[];
  for (final r in analyze(exams, subjects)) {
    final s = r.subject;
    if (!next.containsKey(s)) continue;
    final adj = r.trend <= -1.5 ? 0.5 : (r.trend >= 1.5 ? -0.5 : 0.0);
    final nw = max(1, min(5, (1 + 4 * min(1.0, r.prio) + adj + 0.5).toInt()));
    if (nw != next[s]) changes.add(Change(s, next[s]!, nw, r.avg, r.trend, r.wn));
    next[s] = nw;
  }
  return Proposal(next, changes);
}
