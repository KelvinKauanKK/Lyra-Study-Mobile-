import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'admin_sheet.dart';
import 'exams_screen.dart';
import 'focus_screen.dart';
import 'memory_screen.dart';
import 'schedule_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'tutorial_screen.dart';

/// Casca responsiva: barra de navegação inferior no celular; NavigationRail lateral em tablets/paisagem larga.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  static const pages = <Widget>[FocusScreen(), ScheduleScreen(), ExamsScreen(), StatsScreen()];
  static const labels = ['Foco', 'Cronograma', 'Simulados', 'Desempenho'];
  static const icons = [Icons.timer_outlined, Icons.calendar_month_outlined, Icons.assignment_outlined, Icons.insights_outlined];

  Future<void> _adminPrompt() async {
    final app = context.read<AppState>();
    if (app.admin) {
      showAdminSheet(context);
      return;
    }
    final ctl = TextEditingController();
    final pw = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('🔐 Modo Admin'),
              content: TextField(controller: ctl, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Senha'), onSubmitted: (v) => Navigator.pop(c, v)),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Entrar'))],
            ));
    if (pw == null || !mounted) return;
    if (app.loginAdmin(pw)) {
      showAdminSheet(context);
    } else {
      toast(context, 'Senha incorreta.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 720;
      return Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MemoryScreen())), // toque no logo: Modo Memória
            onLongPress: _adminPrompt, // pressionar e segurar: acesso Admin (não há botão visível)
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('✦ Lyra Study', style: TextStyle(color: kGold, fontWeight: FontWeight.bold)),
              if (app.admin) const Padding(padding: EdgeInsets.only(left: 8), child: Text('🛠 ADMIN', style: TextStyle(fontSize: 12, color: kGold))),
            ]),
          ),
          actions: [
            Center(child: Text('⭐ ${app.points}', style: const TextStyle(fontWeight: FontWeight.bold, color: kGold))),
            IconButton(tooltip: 'Tutorial', icon: const Icon(Icons.help_outline), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TutorialScreen()))),
          ],
        ),
        body: Row(children: [
          if (wide)
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [for (var i = 0; i < 4; i++) NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i]))],
            ),
          Expanded(child: pages[index]),
        ]),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => index = i),
                destinations: [for (var i = 0; i < 4; i++) NavigationDestination(icon: Icon(icons[i]), label: labels[i])],
              ),
      );
    });
  }
}
