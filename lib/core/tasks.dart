import 'util.dart';

/// Tarefa ou lembrete personalizado: QUALQUER data, exibido como os itens de estudo.
class CustomTask {
  final String id, day, title, time; // day = "YYYY-MM-DD"; time = "" ou "HH:MM"
  const CustomTask(this.id, this.day, this.title, this.time);
}

class TaskException implements Exception {
  final String message;
  TaskException(this.message);
  @override
  String toString() => message;
}

final RegExp _timeRe = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');
bool validTime(String s) => s.trim().isEmpty || _timeRe.hasMatch(s.trim());

CustomTask makeTask(String day, String title, String time) {
  final t = title.trim();
  var tm = time.trim();
  if (t.isEmpty) throw TaskException('Escreva o título da tarefa ou lembrete.');
  if (!validTime(tm)) throw TaskException('Horário inválido. Use HH:MM (ex.: 14:30) ou deixe em branco.');
  if (tm.isNotEmpty) {
    final p = tm.split(':');
    tm = '${two(int.parse(p[0]))}:${p[1]}';
  }
  return CustomTask(newId(), day, t, tm);
}

String taskLabel(CustomTask t) => '🔔 ${t.time.isNotEmpty ? '${t.time} ' : ''}${t.title}';
String taskKey(CustomTask t) => 'task:${t.id}'; // a conclusão usa a mesma tabela todo_done das tarefas de estudo

/// Ordena por horário (sem horário vem depois) e título.
int compareTasks(CustomTask a, CustomTask b) {
  final ta = a.time.isEmpty ? '99:99' : a.time, tb = b.time.isEmpty ? '99:99' : b.time;
  final c = ta.compareTo(tb);
  return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}
