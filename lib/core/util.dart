import 'dart:math';

/// Arredondamento "bancário" (metade vai para o par), idêntico ao round() do Python — mantém a paridade com o desktop.
int pyRound(double x) {
  final f = x.floorToDouble();
  final diff = x - f;
  final fi = f.toInt();
  if (diff < 0.5) return fi;
  if (diff > 0.5) return fi + 1;
  return fi.isEven ? fi : fi + 1;
}

/// Minutos -> texto legível: 45 -> "45 min" • 60 -> "1h" • 150 -> "2h e 30 min".
String fmtDur(num minutes) {
  final m = max(pyRound(minutes.toDouble()), 0);
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r min';
  return r == 0 ? '${h}h' : '${h}h e $r min';
}

String two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
DateTime parseIso(String s) => DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));
String brDate(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Minúsculas e sem acento (busca por nome). "º" e "ª" viram "o" e "a", como no desktop.
String norm(String t) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñºª';
  const to = 'aaaaaeeeeiiiiooooouuuucnoa';
  final sb = StringBuffer();
  for (final ch in t.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString();
}

final Random _idRng = Random();
String newId() => List.generate(10, (_) => _idRng.nextInt(16).toRadixString(16)).join();
