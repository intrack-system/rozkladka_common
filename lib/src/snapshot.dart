import 'dart:convert';
import 'dart:typed_data';

import 'p256.dart';

/// Підписує байти ключем телефона; повертає підпис DER (як Keystore).
typedef DerSigner = Future<Uint8List> Function(Uint8List message);

/// Знімок `.rzs`: база зашифрована для InTrack (ECDH → HKDF → AES-256-GCM),
/// заголовок підписаний ключем телефона. Формат — протокол активації.
Future<Uint8List> sealSnapshot({
  required List<int> db,
  required String app,
  required String aid,
  required int counter,
  required List<int> devicePublicSpki,
  required DerSigner sign,
  required List<int> issuerSpki,
  required DateTime time,
}) async {
  final eph = generateKeyPair();
  final key = hkdfSha256(
    ecdh(eph.privateKey, decodeSpki(issuerSpki)),
    ascii.encode('RZS1'),
    utf8.encode(aid),
  );
  final iv = randomBytes(12);
  final sealed = aesGcmEncrypt(key, iv, utf8.encode(aid), db);
  final header = {
    'v': 1,
    'app': app,
    'aid': aid,
    'n': counter,
    't': time.toUtc().toIso8601String(),
    'pub': b64u(devicePublicSpki),
    'epk': b64u(encodeSpki(eph.publicKey)),
    'iv': b64u(iv),
    'tag': b64u(sealed.tag),
    'sha256': sha256(db).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  };
  final input =
      '${b64u(utf8.encode(jsonEncode({'alg': 'ES256', 'typ': 'RZS'})))}.'
      '${b64u(utf8.encode(jsonEncode(header)))}';
  final sig = derSignatureToRaw(await sign(ascii.encode(input)));
  return Uint8List.fromList([
    ...ascii.encode('RZS1\n$input.${b64u(sig)}\n'),
    ...sealed.body,
  ]);
}
