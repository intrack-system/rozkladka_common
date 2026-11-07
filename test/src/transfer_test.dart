import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/transfer.dart';

void main() {
  test('серія QR-кодів збирається в будь-якому порядку', () {
    final data = List.generate(250000, (i) => i % 256);
    final codes = splitForQr(data);
    expect(codes, hasLength(120));
    expect(codes.every((c) => c.length <= qrMaxChars), isTrue);
    final a = QrAssembler();
    Uint8List? result;
    for (final c in codes.reversed) {
      expect(result, isNull);
      result = a.add(c);
      a.add('сторонній код');
    }
    expect(result, data);
  });
}
