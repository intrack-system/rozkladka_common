import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rozkladka_common/src/transfer.dart';

void main() {
  test('частина серії вміщається в QR-код найбільший QR-код (версія 40)', () {
    final codes = splitForQr(List.generate(5000, (i) => (i * 7) % 256));
    for (final c in codes) {
      final r = QrValidator.validate(
        data: c,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );
      expect(r.isValid, isTrue);
      expect(r.qrCode!.typeNumber, lessThanOrEqualTo(40));
    }
  });
}
