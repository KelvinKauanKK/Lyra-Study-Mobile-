import 'package:flutter/material.dart';

const kBg = Color(0xFF0D1020);
const kCard = Color(0xFF171B30);
const kCard2 = Color(0xFF1F2440);
const kEdge = Color(0xFF2C3358);
const kGold = Color(0xFFF2B84B);
const kTeal = Color(0xFF3FB8A5);
const kRed = Color(0xFFE5634D);
const kViolet = Color(0xFF7C6CF0);
const kMuted = Color(0xFF8D93AB);
const _tags = [kViolet, kTeal, kGold, kRed, Color(0xFF4A90D9), Color(0xFFD96FA8), Color(0xFF6FCF97), Color(0xFFF2994A)];

/// Cor estável por matéria / tarefa (mesma paleta do desktop).
Color tagColor(String name) {
  var s = 0;
  for (final c in name.runes) {
    s += c;
  }
  return _tags[s % _tags.length];
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: kViolet, brightness: Brightness.dark),
      scaffoldBackgroundColor: kBg,
      appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0),
    );

/// Etiqueta colorida: o MESMO visual para exercícios de estudo, metas e tarefas/lembretes.
class MiniChip extends StatelessWidget {
  const MiniChip(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF14161F))),
      );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.margin = const EdgeInsets.symmetric(vertical: 5)});
  final Widget child;
  final EdgeInsets padding, margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kEdge)),
        child: child,
      );
}

class LabeledBar extends StatelessWidget {
  const LabeledBar(this.label, this.value, {super.key, this.right = '', this.color = kTeal});
  final String label, right;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(label)), Text(right, style: const TextStyle(color: kMuted, fontSize: 12))]),
          const SizedBox(height: 3),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 8, color: color, backgroundColor: kEdge)),
        ]),
      );
}

void toast(BuildContext c, String msg) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));
