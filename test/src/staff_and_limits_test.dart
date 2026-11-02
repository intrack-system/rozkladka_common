import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/activation.dart';
import 'package:rozkladka_common/src/activation_service.dart';
import 'package:rozkladka_common/src/activation_store.dart';
import 'package:rozkladka_common/src/device_key.dart';
import 'package:rozkladka_common/src/p256.dart';
import 'package:rozkladka_common/src/submission_reminder.dart';

import '../vectors.dart';

/// Стиснутий QR-код зі списком особового складу — як мав би видати InTrack.
Future<String> compactToken(Map<String, Object?> payload) async {
  final body = b64u(
    ZLibCodec(raw: true, level: 9).encode(utf8.encode(jsonEncode(payload))),
  );
  final der = await signDer(
    privateKeyFromPem(vectors['intrack_private_pkcs8_pem']),
    Uint8List.fromList(ascii.encode('RZA2.$body')),
  );
  return 'RZA2.$body.${b64u(derSignatureToRaw(der))}';
}

class _Key extends DeviceKey {
  @override
  Future<Uint8List> publicKey() async =>
      base64.decode(vectors['device_public_spki_b64']);
  @override
  Future<Uint8List> sign(Uint8List m) =>
      signDer(privateKeyFromPem(vectors['device_private_pkcs8_pem']), m);
}

void main() {
  final issuer = base64.decode(vectors['intrack_public_spki_b64']);
  final payload = {
    'v': 2,
    'aid': 'a-1',
    'app': 'rozkladka_s',
    'dev': vectors['device_code'],
    'sub': {
      'id': 42,
      'sid': 1001,
      'name': 'Пупкін П.П.',
      'position': 'комірник',
    },
    'dept': {'id': 89, 'name': '4 ТВУЗ'},
    'iat': '2026-11-02T08:00:00.000Z',
    'scan_before': '2026-11-09T08:00:00.000Z',
    'exp': '2026-12-31T21:59:59.000Z',
    'staff': [
      [1000, 'Іваненко І.І.', 'em'],
      [1001, 'Пупкін П.П.', 'k'],
      [1002, 'Петренко П.П.', 'ze'],
    ],
  };

  test('стиснутий QR-код зі списком особового складу', () async {
    final token = await compactToken(payload);
    final a = verifyActivation(
      token,
      issuerSpki: issuer,
      app: 'rozkladka_s',
      deviceCode: vectors['device_code'],
      now: DateTime.utc(2026, 11, 3),
    );
    expect(a.staff, hasLength(3));
    expect(a.self!.name, 'Пупкін П.П.');
    expect(a.self!.mayIssue, isTrue);
    expect(a.memberById(1002)!.isDeputyKeeper, isTrue);
    expect(a.memberById(1000)!.mayIssue, isFalse);
    expect(a.memberById(1000)!.mayBeResponsible, isTrue);
    final p = token.split('.');
    expect(
      () => verifyActivation(
        '${p[0]}.${p[1]}A.${p[2]}',
        issuerSpki: issuer,
        app: 'rozkladka_s',
        deviceCode: vectors['device_code'],
        now: DateTime.utc(2026, 11, 3),
      ),
      throwsA(isA<ActivationException>()),
    );
  });

  test('60 осіб уміщаються в один QR-код', () async {
    final big = {
      ...payload,
      'staff': [
        for (var i = 0; i < 60; i++)
          [1000 + i, 'Прізвищенко-Довге$iо А.Б.', 'em'],
      ],
    };
    final token = await compactToken(big);
    expect(token.length, lessThan(2953));
  });

  test('після дозволу: місяць — лише напрацювання, далі блокування', () async {
    final dir = Directory.systemTemp.createTempSync('limits');
    addTearDown(() => dir.deleteSync(recursive: true));
    var now = DateTime.utc(2026, 11, 3);
    final s = ActivationService(
      app: 'rozkladka_s',
      issuerSpki: issuer,
      key: _Key(),
      store: ActivationStore(dir: () async => dir),
      now: () => now,
      authenticate: () async => true,
    );
    await s.activate(await compactToken(payload));
    s.ensureCanEdit();

    now = DateTime.utc(2027, 1, 10);
    expect(s.isLocked, isTrue);
    expect(s.isBlocked, isFalse);
    expect(s.ensureCanEdit, throwsA(isA<ActivationException>()));
    s.ensureCanEdit(hours: true);

    now = DateTime.utc(2027, 2, 1);
    expect(s.isBlocked, isTrue);
    expect(
      () => s.ensureCanEdit(hours: true),
      throwsA(isA<ActivationException>()),
    );
    await s.seal(Uint8List.fromList([1]));
  });

  test('строки подання бази: нагадування лише за тиждень', () {
    expect(nextSubmissionDeadline(DateTime(2026, 2, 1)), DateTime(2026, 4, 1));
    expect(
      nextSubmissionDeadline(DateTime(2026, 11, 2)),
      DateTime(2026, 12, 20),
    );
    expect(
      nextSubmissionDeadline(DateTime(2026, 12, 21)),
      DateTime(2027, 4, 1),
    );
    expect(submissionReminder(DateTime(2026, 11, 2)), isNull);
    expect(submissionReminder(DateTime(2026, 12, 14)), contains('20.12.2026'));
    expect(submissionReminder(DateTime(2026, 3, 25)), contains('01.04.2026'));
  });
}
