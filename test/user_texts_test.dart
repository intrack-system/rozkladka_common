import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Застосунки не показують назву системи обліку: у рядках коду пакета (не в
/// коментарях) її немає — так само, як у самих застосунках.
void main() {
  test('назва системи обліку не потрапляє в написи', () {
    final comment = RegExp(r'^\s*//');
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (!comment.hasMatch(line) &&
                line.toLowerCase().contains('intrack'))
              '${f.path}:${i + 1}',
    ];
    expect(offenders, isEmpty);
  });
}
