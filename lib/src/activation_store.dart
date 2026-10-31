import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Стан активації — окремим файлом, не в базі: відновлення старого знімка
/// бази не повертає лічильник назад і не переносить доступ.
class ActivationStore {
  final Future<Directory> Function() _dir;

  ActivationStore({Future<Directory> Function()? dir})
    : _dir = dir ?? getApplicationSupportDirectory;

  Future<File> get _file async =>
      File(p.join((await _dir()).path, 'activation.json'));

  Future<Map<String, dynamic>> read() async {
    final f = await _file;
    if (!await f.exists()) return {};
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic> data) async {
    final f = await _file;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
