import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/activation.dart';
import 'package:rozkladka_common/src/p256.dart';
import 'package:rozkladka_common/src/receipt_sheet.dart';

import '../vectors.dart';

void main() {
  final issuer = base64.decode(vectors['intrack_public_spki_b64']);
  final token = vectors['receipt_token'] as String;

  test('еталонна табличка InTrack читається', () {
    final s = ReceiptSheet.decode(token, issuer);
    expect(s.departmentId, 89);
    expect(s.departmentName, '4 ТВУЗ');
    expect(s.documentNumber, '45/2026');
    expect(s.documentDate, '2026-10-01');
    final i = s.items.single;
    expect(i.uid, '8ae238e6-1725-4fcd-9804-006ce26f3388');
    expect(i.inventoryNumber, '111376845');
    expect(i.serialNumber, 'DL5420-88231');
    expect(i.quantity, 1);
    expect(i.cost, 24500);
    expect(i.manufactureYear, 2024);
    expect(i.formularNumber, '29/04/01-9620/2026/ВН');
  });

  test('змінена, чужа й стороння відхиляються', () {
    final p = token.split('.');
    final forged = '${p[0]}.${p[1].substring(1)}A.${p[2]}';
    for (final t in [forged, 'не код', 'RZI1.abc.def']) {
      expect(
        () => ReceiptSheet.decode(t, issuer),
        throwsA(isA<ActivationException>()),
      );
    }
    expect(
      () => ReceiptSheet.decode(
        token,
        base64.decode(vectors['device_public_spki_b64']),
      ),
      throwsA(isA<ActivationException>()),
    );
  });
  test('другий документ і юридична особа (doc.x, doc.src)', () async {
    final pair = generateKeyPair();
    final body = b64u(
      ZLibCodec(raw: true).encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'dept': {'id': 89, 'name': '4 ТВУЗ'},
            'doc': {
              'k': 'discrepancy_act',
              'n': '7',
              'd': '2026-11-03',
              'x': {'n': '15/26', 'd': null},
              'src': 'ТОВ «Постачальник»',
            },
            'at': '2026-11-04T10:00:00Z',
            'it': [],
          }),
        ),
      ),
    );
    final sig = derSignatureToRaw(
      await signDer(pair.privateKey, ascii.encode('RZI1.$body')),
    );
    final s = ReceiptSheet.decode(
      'RZI1.$body.${b64u(sig)}',
      encodeSpki(pair.publicKey),
    );
    expect(s.documentKind, 'discrepancy_act');
    expect(s.extraNumber, '15/26');
    expect(s.extraDate, isNull);
    expect(s.sourceEntity, 'ТОВ «Постачальник»');
  });
}
