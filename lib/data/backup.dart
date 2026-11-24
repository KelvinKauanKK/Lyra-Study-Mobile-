import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'database.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

/// Importa o backup (.zip) gerado por `python tools/export_mobile.py db` no desktop: lyra.db + anexos/.
/// O banco é VALIDADO antes de substituir o atual (integrity_check, chaves estrangeiras e versão do esquema).
/// Depois de importar, o app precisa ser reaberto.
Future<void> importBackup(AppDatabase app, String zipPath) async {
  final Archive arc;
  try {
    arc = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
  } catch (_) {
    throw BackupException('O arquivo não é um .zip válido.');
  }
  ArchiveFile? dbEntry;
  for (final f in arc.files) {
    if (f.isFile && p.basename(f.name) == 'lyra.db') dbEntry = f;
  }
  if (dbEntry == null) throw BackupException('O .zip não contém o arquivo lyra.db.');

  // 1) banco em arquivo temporário -> validação
  final tmp = File(p.join(app.dir, 'import_tmp.db'));
  await tmp.writeAsBytes(dbEntry.content as List<int>, flush: true);
  final probe = await openDatabase(tmp.path, readOnly: true);
  try {
    final ic = await probe.rawQuery('PRAGMA integrity_check');
    if (ic.isEmpty || ic.first.values.first != 'ok') throw BackupException('Banco corrompido (integrity_check falhou).');
    if ((await probe.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) throw BackupException('Banco com referências quebradas (foreign_key_check).');
    final v = await probe.query('kv', where: 'k = ?', whereArgs: ['schema_version']);
    if (v.isEmpty || int.tryParse(v.first['v'] as String) != AppDatabase.schemaVersion) throw BackupException('Versão do esquema incompatível com este app.');
  } catch (e) {
    await probe.close();
    await tmp.delete();
    if (e is BackupException) rethrow;
    throw BackupException('Não foi possível ler o banco do backup.');
  }
  await probe.close();

  // 2) anexos -> documentos do app (com proteção contra caminhos fora da pasta)
  for (final f in arc.files) {
    if (!f.isFile) continue;
    final parts = p.split(f.name);
    final i = parts.indexOf('anexos');
    if (i < 0 || i == parts.length - 1) continue;
    final dest = p.normalize(p.join(app.dir, p.joinAll(parts.sublist(i))));
    if (!p.isWithin(app.dir, dest)) continue;
    await Directory(p.dirname(dest)).create(recursive: true);
    await File(dest).writeAsBytes(f.content as List<int>, flush: true);
  }

  // 3) troca o banco (fecha o atual e substitui o arquivo)
  await app.db.close();
  await tmp.copy(p.join(app.dir, 'lyra.db'));
  await tmp.delete();
}
