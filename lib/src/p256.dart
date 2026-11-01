import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Криві й формати P-256, спільні з InTrack (`appActivation.js`).
final ECDomainParameters curve = ECCurve_secp256r1();

/// Префікс SubjectPublicKeyInfo DER для ключа P-256 (далі — 04‖X‖Y).
final Uint8List _spkiPrefix = Uint8List.fromList([
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, //
  0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
  0x42, 0x00,
]);

String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List fromB64u(String s) =>
    base64Url.decode(s.padRight((s.length + 3) & ~3, '='));

Uint8List sha256(List<int> data) =>
    SHA256Digest().process(Uint8List.fromList(data));

Uint8List _bigIntBytes(BigInt v, int length) {
  final out = Uint8List(length);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

BigInt _bytesBigInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));

Uint8List encodeSpki(ECPublicKey key) =>
    Uint8List.fromList([..._spkiPrefix, ...key.Q!.getEncoded(false)]);

ECPublicKey decodeSpki(List<int> der) {
  if (der.length != _spkiPrefix.length + 65) {
    throw const FormatException('Ключ не P-256');
  }
  for (var i = 0; i < _spkiPrefix.length; i++) {
    if (der[i] != _spkiPrefix[i]) throw const FormatException('Ключ не P-256');
  }
  return ECPublicKey(
    curve.curve.decodePoint(der.sublist(_spkiPrefix.length)),
    curve,
  );
}

/// Підпис r‖s (64 байти) → перевірка SHA-256/ECDSA.
bool verifyEs256(ECPublicKey key, List<int> message, List<int> rawSig) {
  if (rawSig.length != 64) return false;
  final signer = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter<ECPublicKey>(key));
  return signer.verifySignature(
    Uint8List.fromList(message),
    ECSignature(
      _bytesBigInt(rawSig.sublist(0, 32)),
      _bytesBigInt(rawSig.sublist(32)),
    ),
  );
}

/// Keystore і Secure Enclave повертають підпис у DER (SEQUENCE {r, s}),
/// JWS вимагає r‖s.
Uint8List derSignatureToRaw(List<int> der) {
  var i = 2;
  if (der[1] & 0x80 != 0) i += der[1] & 0x7f;
  BigInt readInt() {
    if (der[i] != 0x02) throw const FormatException('Підпис не DER');
    final len = der[i + 1];
    final v = _bytesBigInt(der.sublist(i + 2, i + 2 + len));
    i += 2 + len;
    return v;
  }

  final r = readInt();
  final s = readInt();
  return Uint8List.fromList([..._bigIntBytes(r, 32), ..._bigIntBytes(s, 32)]);
}

SecureRandom secureRandom() {
  final seed = Random.secure();
  return FortunaRandom()..seed(
    KeyParameter(
      Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256))),
    ),
  );
}

AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateKeyPair() {
  final gen = ECKeyGenerator()
    ..init(
      ParametersWithRandom(ECKeyGeneratorParameters(curve), secureRandom()),
    );
  final pair = gen.generateKeyPair();
  return AsymmetricKeyPair(pair.publicKey, pair.privateKey);
}

/// Спільний секрет ECDH — координата X, 32 байти (як `crypto.diffieHellman`).
Uint8List ecdh(ECPrivateKey own, ECPublicKey other) => _bigIntBytes(
  (ECDHBasicAgreement()..init(own)).calculateAgreement(other),
  32,
);

Uint8List hkdfSha256(List<int> ikm, List<int> salt, List<int> info) {
  final out = Uint8List(32);
  (HKDFKeyDerivator(SHA256Digest())..init(
        HkdfParameters(
          Uint8List.fromList(ikm),
          32,
          Uint8List.fromList(salt),
          Uint8List.fromList(info),
        ),
      ))
      .deriveKey(null, 0, out, 0);
  return out;
}

/// AES-256-GCM: шифротекст і тег (16 байт) окремо, як у заголовку `.rzs`.
({Uint8List body, Uint8List tag}) aesGcmEncrypt(
  List<int> key,
  List<int> iv,
  List<int> aad,
  List<int> plain,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        128,
        Uint8List.fromList(iv),
        Uint8List.fromList(aad),
      ),
    );
  final out = cipher.process(Uint8List.fromList(plain));
  return (
    body: out.sublist(0, out.length - 16),
    tag: out.sublist(out.length - 16),
  );
}

/// Розшифрування AES-256-GCM; кидає виняток, якщо вміст чи тег змінено.
Uint8List aesGcmDecrypt(
  List<int> key,
  List<int> iv,
  List<int> aad,
  List<int> body,
  List<int> tag,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        128,
        Uint8List.fromList(iv),
        Uint8List.fromList(aad),
      ),
    );
  return cipher.process(Uint8List.fromList([...body, ...tag]));
}

Uint8List randomBytes(int length) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
}
