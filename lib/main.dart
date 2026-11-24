import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/database.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final state = AppState(db);
  await state.init();
  runApp(ChangeNotifierProvider<AppState>.value(value: state, child: const LyraApp()));
}

class LyraApp extends StatelessWidget {
  const LyraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return MaterialApp(
      title: 'Lyra Study',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: state.messengerKey,
      theme: buildTheme(),
      home: const HomeShell(),
    );
  }
}
