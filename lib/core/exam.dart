import 'dart:math';
import 'util.dart';

class ExamException implements Exception {
  final String message;
  ExamException(this.message);
  @override
  String toString() => message;
}

/// Uma linha digitada no formulário (uma matéria do simulado).
class SubjectRow {
  final String subject;
  final int total, hits, annulled;
  final int? annulledHit;
  final double weight;
  const SubjectRow(this.subject, {required this.total, required this.hits, this.annulled = 0, this.annulledHit, this.weight = 1});
}

class ExamSubject {
  final int hits, total, origHits, origTotal, annulled, annulledHit;
  final double score, weight;
  const ExamSubject({required this.hits, required this.total, required this.origHits, required this.origTotal, required this.annulled, required this.annulledHit, required this.score, required this.weight});
  factory ExamSubject.fromJson(Map<String, dynamic> j) => ExamSubject(
      hits: (j['hits'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      origHits: (j['orig_hits'] as num?)?.toInt() ?? (j['hits'] as num).toInt(),
      origTotal: (j['orig_total'] as num?)?.toInt() ?? (j['total'] as num).toInt(),
      annulled: (j['annulled'] as num?)?.toInt() ?? 0,
      annulledHit: (j['annulled_hit'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num).toDouble(),
      weight: (j['weight'] as num?)?.toDouble() ?? 1);
}

class Attachment {
  final String name, file;
  final int size;
  const Attachment(this.name, this.file, this.size);
}

class Exam {
  final String id, name, day;
  final int maxQ, hits, scale, annulled, cityYear;
  final double score10;
  final bool weighted;
  final Map<String, ExamSubject> subjects;
  final List<Attachment> attachments;
  Exam({required this.id, required this.name, required this.day, required this.maxQ, required this.hits, required this.scale, required this.annulled, required this.score10, required this.weighted, required this.cityYear, required this.subjects, List<Attachment>? attachments})
      : attachments = attachments ?? [];

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      day: j['date'] as String,
      maxQ: (j['max_q'] as num?)?.toInt() ?? 0,
      hits: (j['hits'] as num?)?.toInt() ?? 0,
      scale: (j['scale'] as num?)?.toInt() ?? 0,
      annulled: (j['annulled'] as num?)?.toInt() ?? 0,
      score10: (j['score10'] as num).toDouble(),
      weighted: j['weighted'] == true,
      cityYear: (j['city_year'] as num?)?.toInt() ?? 0,
      subjects: {for (final e in (j['subjects'] as Map<String, dynamic>).entries) e.key: ExamSubject.fromJson(e.value as Map<String, dynamic>)});
}

/// Questão anulada deixa de existir: o teto da matéria cai exatamente em `annulled` e os acertos marcados nelas são abatidos.
/// Ex.: 20 questões, 3 anuladas, 9 acertos (incluindo as 3) -> 6 acertos em 17. Retorna [acertos, teto].
List<int> adjust(int total, int hits, [int annulled = 0, int? annulledHit]) {
  final ah = annulledHit ?? annulled;
  final effTotal = total - annulled;
  return [max(0, min(effTotal, hits - ah)), effTotal];
}

double _round2(double v) => pyRound(v * 100) / 100;

/// Valida e calcula o simulado (mesmas regras e mensagens do desktop). A soma das questões das matérias DEVE ser igual a [maxQ].
Exam computeExam({required String id, required String name, required int maxQ, required List<SubjectRow> rows, bool weighted = false, int cityYear = 0, required String day}) {
  final nm = name.trim();
  if (nm.isEmpty) throw ExamException('Informe o nome da prova.');
  if (maxQ < 1) throw ExamException('A quantidade máxima de questões deve ser um número inteiro maior que zero.');
  if (rows.isEmpty) throw ExamException('Selecione ao menos uma matéria.');
  final soma = rows.fold<int>(0, (a, r) => a + r.total);
  if (soma != maxQ) throw ExamException('A soma das questões das matérias ($soma) precisa ser igual ao máximo de questões da prova ($maxQ).');
  final subs = <String, ExamSubject>{};
  var hAll = 0, tAll = 0, aAll = 0;
  for (final r in rows) {
    final s = r.subject, t = r.total, h = r.hits, a = r.annulled;
    final ah = r.annulledHit ?? a;
    final w = weighted ? r.weight : 1.0;
    if (t < 1) throw ExamException('$s: informe a quantidade de questões (mínimo 1).');
    if (h < 0 || h > t) throw ExamException('$s: os acertos (0 a $t) não podem passar do total de questões.');
    if (a < 0 || a > t) throw ExamException('$s: as anuladas (0 a $t) não podem passar do total de questões.');
    if (ah < 0 || ah > min(a, h)) throw ExamException('$s: dentre as anuladas, os acertos marcados (0 a ${min(a, h)}) não podem passar das anuladas nem dos acertos.');
    if (weighted && w <= 0) throw ExamException('$s: o peso precisa ser maior que zero.');
    final adj = adjust(t, h, a, ah);
    if (adj[1] < 1) throw ExamException('$s: todas as questões foram anuladas — remova a matéria do simulado.');
    subs[s] = ExamSubject(hits: adj[0], total: adj[1], origHits: h, origTotal: t, annulled: a, annulledHit: ah, score: _round2(adj[0] / adj[1] * 10), weight: w);
    hAll += adj[0];
    tAll += adj[1];
    aAll += a;
  }
  double score;
  if (weighted) {
    var num = 0.0, den = 0.0;
    for (final v in subs.values) {
      num += v.weight * v.score;
      den += v.weight;
    }
    score = num / den;
  } else {
    score = hAll / tAll * 10;
  }
  return Exam(id: id, name: nm, day: day, maxQ: maxQ, hits: hAll, scale: tAll, annulled: aAll, score10: _round2(score), weighted: weighted, cityYear: cityYear, subjects: subs);
}

// ---------- busca e paginação ----------
String examName(Exam e) => e.name.isNotEmpty ? e.name : 'Simulado ${brDate(e.day)}';

class IndexedExam {
  final int index;
  final Exam exam;
  const IndexedExam(this.index, this.exam);
}

/// Do mais novo para o mais antigo, filtrado por nome (sem acento/maiúsculas; todas as palavras).
List<IndexedExam> filterExams(List<Exam> exams, String query) {
  final words = norm(query).split(' ').where((w) => w.isNotEmpty).toList();
  final out = <IndexedExam>[];
  for (var i = exams.length - 1; i >= 0; i--) {
    final n = norm(examName(exams[i]));
    if (words.every((w) => n.contains(w))) out.add(IndexedExam(i, exams[i]));
  }
  return out;
}

class PageOf<T> {
  final List<T> items;
  final int pages, page;
  const PageOf(this.items, this.pages, this.page);
}

/// No máximo [per] itens por página (10 simulados por aba).
PageOf<T> paginate<T>(List<T> items, int page, {int per = 10}) {
  final pages = max(1, (items.length / per).ceil());
  final p = max(1, min(page, pages));
  return PageOf(items.skip((p - 1) * per).take(per).toList(), pages, p);
}
