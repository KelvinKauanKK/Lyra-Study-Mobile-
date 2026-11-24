import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'theme.dart';

/// ❓ Tutorial: as mesmas seções do desktop (exportadas para assets/tutorial.json pelo tools/export_mobile.py).
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('❓ Tutorial')),
        body: FutureBuilder<String>(
          future: rootBundle.loadString('assets/tutorial.json'),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final secs = (jsonDecode(snap.data!) as List).cast<Map<String, dynamic>>();
            return ListView(padding: const EdgeInsets.all(10), children: [
              for (final s in secs)
                Panel(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text(s['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(s['text'] as String)],
                    )),
            ]);
          },
        ),
      );
}
