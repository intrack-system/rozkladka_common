import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/snapshot.dart';

import '../vectors.dart';

void main() {
  final intrackKey = privateKeyFromPem(vectors['intrack_private_pkcs8_pem']);
  final deviceKey = privateKeyFromPem(vectors['device_private_pkcs8_pem']);
  final plain = base64.decode(vectors['snapshot_plain_b64']);

  test('еталонний знімок InTrack розшифровується', () {
    final opened = openSnapshot(
      base64.decode(vectors['snapshot_rzs_b64']),
      intrackKey,
    );
    expect(opened.db, plain);
  });

  test('власний знімок відкривається так, як у InTrack', () async {
    final file = await sealSnapshot(
      db: plain,
      app: 'rozkladka_e',
      aid: 'cc602d31-fcd8-45f8-b7bd-b478ceaac6b7',
      counter: 7,
      devicePublicSpki: base64.decode(vectors['device_public_spki_b64']),
      sign: (m) => signDer(deviceKey, m),
      issuerSpki: base64.decode(vectors['intrack_public_spki_b64']),
      time: DateTime.utc(2026, 11, 1),
    );
    expect(ascii.decode(file.sublist(0, 5)), 'RZS1\n');
    final opened = openSnapshot(file, intrackKey);
    expect(opened.db, plain);
    expect(opened.header['n'], 7);
    expect(opened.header['app'], 'rozkladka_e');
    expect(opened.header['sha256'], hasLength(64));
    expect(
      () => openSnapshot(
        Uint8List.fromList([...file]..[file.length - 1] ^= 1),
        intrackKey,
      ),
      throwsA(anything),
    );
  });
}
