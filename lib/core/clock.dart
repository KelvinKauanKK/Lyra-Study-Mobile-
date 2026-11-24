/// Relógio do app. O modo Admin pode ADIANTAR a data (simulação de dias, meses e anos) sem mexer no relógio do sistema.
class AppClock {
  static int offsetDays = 0;

  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + offsetDays); // o construtor normaliza o dia (sem erro de horário de verão)
  }
}
