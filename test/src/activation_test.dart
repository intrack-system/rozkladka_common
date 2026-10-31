import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/activation.dart';

import '../vectors.dart';

void main() {
  final intrack = base64.decode(vectors['intrack_public_spki_b64']);
  final token = vectors['activation_token'] as String;
  final payload = vectors['activation_payload'] as Map<String, dynamic>;
  final issued = DateTime.parse(payload['iat']);

  Activation verify({
    String? t,
    String app = 'rozkladka_e',
    String? dev,
    DateTime? now,
    bool firstScan = true,
  }) => verifyActivation(
    t ?? token,
    issuerSpki: intrack,
    app: app,
    deviceCode: dev ?? vectors['device_code'],
    now: now ?? issued.add(const Duration(hours: 1)),
    firstScan: firstScan,
  );

  test('чинний QR-код: особа й підрозділ з InTrack', () {
    final a = verify();
    expect(a.aid, payload['aid']);
    expect(a.personName, 'Пупкін Петро Петрович');
    expect(a.position, 'інженер');
    expect(a.departmentName, '4 ТВУЗ');
    expect(a.isExpired(issued), isFalse);
  });

  test('інший застосунок, інший телефон, змінений вміст — відхиляються', () {
    expect(
      () => verify(app: 'rozkladka_s'),
      throwsA(isA<ActivationException>()),
    );
    expect(
      () => verify(dev: 'XNETZN032Q5T'),
      throwsA(isA<ActivationException>()),
    );
    final parts = token.split('.');
    final forged =
        '${parts[0]}.${parts[1].substring(0, 10)}A${parts[1].substring(11)}.${parts[2]}';
    expect(() => verify(t: forged), throwsA(isA<ActivationException>()));
    expect(() => verify(t: 'не код'), throwsA(isA<ActivationException>()));
  });

  test(
    'прострочений QR-код не сканується, але збережений доступ читається',
    () {
      final late = DateTime.parse(payload['exp']).add(const Duration(days: 1));
      expect(() => verify(now: late), throwsA(isA<ActivationException>()));
      final a = verify(now: late, firstScan: false);
      expect(a.isExpired(late), isTrue);
    },
  );
}
