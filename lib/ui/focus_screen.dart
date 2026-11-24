import 'dart:async';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../core/clock.dart';
import '../core/economy.dart';
import '../core/util.dart';
import '../state/app_state.dart';
import 'city_painter.dart';
import 'city_sheets.dart';
import 'theme.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth > 900) {
          return const Row(children: [SizedBox(width: 380, child: SingleChildScrollView(child: TimerCard())), Expanded(child: CityPanelView())]);
        }
        return const Column(children: [TimerCard(), Expanded(child: CityPanelView())]);
      });
}

/// Cronômetro: Pomodoro (25/5) ou progressivo. Usa o relógio de parede, então continua certo se o app ficar em segundo plano.
class TimerCard extends StatefulWidget {
  const TimerCard({super.key});
  @override
  State<TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<TimerCard> {
  Timer? _tick;
  DateTime? _start;
  Duration _acc = Duration.zero;
  bool running = false, pomodoro = true, onBreak = false;
  int credited = 0;
  String subject = 'Geral';
  static const focusMin = 25, breakMin = 5;

  Duration get elapsed => running ? _acc + DateTime.now().difference(_start!) : _acc;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (running) {
        _acc = elapsed;
        running = false;
        _tick?.cancel();
      } else {
        _start = DateTime.now();
        running = true;
        _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
      }
    });
  }

  void _reset() {
    _tick?.cancel();
    setState(() {
      running = false;
      _acc = Duration.zero;
      credited = 0;
      onBreak = false;
    });
  }

  void _onTick() {
    final app = context.read<AppState>();
    if (!onBreak) {
      final mins = elapsed.inMinutes;
      while (credited < mins) {
        credited++;
        app.addMinute(subject); // pontos pela META + XP do prédio em foco (pausas não rendem)
      }
    }
    if (pomodoro && elapsed >= Duration(minutes: onBreak ? breakMin : focusMin)) {
      onBreak = !onBreak;
      _acc = Duration.zero;
      _start = DateTime.now();
      credited = 0;
      app.say(onBreak ? '☕ Pausa de $breakMin min' : '🎯 De volta ao foco');
    }
    if (mounted) setState(() {});
  }

  String _clock() {
    final d = pomodoro ? Duration(minutes: onBreak ? breakMin : focusMin) - elapsed : elapsed;
    final s = max(d.inSeconds, 0);
    return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final today = AppClock.today();
    final g = app.goalMin(), got = app.studiedOn(today);
    final names = [...app.subjects.keys, 'Geral'];
    if (!names.contains(subject)) subject = 'Geral';
    return Panel(
      margin: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(onBreak ? '☕ Pausa' : '🎯 Foco', style: const TextStyle(fontWeight: FontWeight.bold))),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Pomodoro')), ButtonSegment(value: false, label: Text('Livre'))],
            selected: {pomodoro},
            onSelectionChanged: running ? null : (s) => setState(() { pomodoro = s.first; _acc = Duration.zero; credited = 0; onBreak = false; }),
          ),
        ]),
        Center(child: Text(_clock(), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: kGold, fontFeatures: [FontFeature.tabularFigures()]))),
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: subject,
              items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
              onChanged: (v) => setState(() => subject = v ?? 'Geral'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _toggle, child: Text(running ? '⏸ Pausar' : '▶ Iniciar')),
          IconButton(onPressed: _reset, icon: const Icon(Icons.restart_alt)),
        ]),
        if (subject == 'Geral') const Text('Estudo Geral conta direto para a Meta do Dia', style: TextStyle(color: kMuted, fontSize: 12)),
        LabeledBar('Meta de hoje', g > 0 ? got / g : 0, right: '${fmtDur(got)} / ${fmtDur(g)}'),
        Text(g > 0 ? 'Meta completa = ${Economy.dailyPoints} pts (${(Economy.dailyPoints / g).toStringAsFixed(2)} pts/min) • além da meta rende ${(Economy.overtimeRate * 100).round()}% • semana: +${Economy.weeklyBonus}' : 'Defina a meta diária no Cronograma para ganhar pontos.',
            style: const TextStyle(color: kMuted, fontSize: 11.5)),
      ]),
    );
  }
}

/// Mapa da cidade (câmera fixa) + seletor de visão + botões Loja e Funções (abrem por cima, como painéis deslizantes).
class CityPanelView extends StatelessWidget {
  const CityPanelView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'dia', label: Text('Dia')), ButtonSegment(value: 'sem', label: Text('Sem.')), ButtonSegment(value: 'mes', label: Text('Mês')), ButtonSegment(value: 'ano', label: Text('Ano'))],
              selected: {app.city.s.view},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                app.city.s.view = s.first;
                app.cityChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.tonal(onPressed: () => showShopSheet(context), child: const Text('🛒 Loja')),
          const SizedBox(width: 4),
          FilledButton.tonal(onPressed: () => showFunctionsSheet(context), child: const Text('⚙ Funções')),
        ]),
      ),
      const Expanded(child: CityView()),
    ]);
  }
}

class CityView extends StatefulWidget {
  const CityView({super.key});
  @override
  State<CityView> createState() => _CityViewState();
}

class _CityViewState extends State<CityView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero, _lastPaint = Duration.zero;
  final CityCamera cam = CityCamera();
  double _pulse = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration d) {
    final dt = (d - _last).inMicroseconds / 1e6;
    _last = d;
    context.read<AppState>().traffic.step(min(dt, 0.1));
    _pulse += dt * 4;
    if ((d - _lastPaint).inMilliseconds >= 33 && mounted) {
      _lastPaint = d; // ~30 fps
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Toque no mapa: seleciona o quadrado (mesma conta inversa da projeção do desktop).
  void _tap(AppState app, Offset p) {
    final u = (p.dx - cam.ox) / cam.k, v = 2 * (p.dy - cam.oy) / cam.k;
    final gx = ((u + v) / 2).floor(), gy = ((v - u) / 2).floor();
    final r = app.city.region();
    for (final d in app.city.geom().days) {
      if (d.x == gx && d.y == gy && gx >= r[0] && gx < r[2] && gy >= r[1] && gy < r[3]) {
        app.city.s.sel = d.i;
        app.cityChanged();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _tap(app, d.localPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          size: Size.infinite,
          painter: CityPainter(city: app.city, images: app.images, cars: app.traffic.cars, cam: cam, pulse: _pulse),
        ),
      ),
    );
  }
}
