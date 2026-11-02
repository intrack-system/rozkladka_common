import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'activation.dart';
import 'activation_service.dart';

/// Знімок бази для обліку майна: активований телефон віддає лише підписаний
/// зашифрований `.rzs`, неактивований — копію `.db`, як раніше.
Future<void> shareSnapshot(
  BuildContext context, {
  required String title,
  required Future<List<int>> Function() bytes,
  required Future<File> Function(String path) exportDb,
  String? text,
}) async {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  final dir = await getTemporaryDirectory();
  final activation = ActivationService.current;
  final File file;
  if (activation?.isActivated ?? false) {
    try {
      final sealed = await activation!.seal(Uint8List.fromList(await bytes()));
      file = await File(
        '${dir.path}/${title}_знімок_$stamp.rzs',
      ).writeAsBytes(sealed);
    } on ActivationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
  } else {
    file = await exportDb('${dir.path}/${title}_знімок_$stamp.db');
  }
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text ?? 'Знімок бази $title'),
  );
}
