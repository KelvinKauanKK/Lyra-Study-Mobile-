import 'dart:math';

/// Economia de pontos calculada sobre a META que a pessoa definiu (espelha rules.py do desktop).
class Economy {
  static const dailyPoints = 100; // pontos por 100% da meta diária
  static const overtimeRate = 0.25; // minutos além da meta rendem 25% do ritmo normal...
  static const overtimeCap = 1.0; // ...até +100% da meta (teto de 125 pontos por dia)
  static const weeklyBonus = 100; // bônus único por semana ao bater a meta semanal (7 x meta diária)
  static const xpDaily = 160; // XP do prédio em foco por 100% da meta diária
  static const devBonus = 5000;

  static double dayPoints(int minutes, int goal) {
    if (goal <= 0) return 0;
    final over = min(max(minutes - goal, 0).toDouble(), goal * overtimeCap) / goal * dailyPoints * overtimeRate;
    return min(minutes, goal) / goal * dailyPoints + over;
  }

  /// Pontos inteiros devidos no dia, sem erro de arredondamento (o app credita só a diferença para o que já foi pago).
  static int due(int minutes, int goal) => (dayPoints(minutes, goal) + 1e-9).floor();
}
