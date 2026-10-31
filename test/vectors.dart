import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:rozkladka_common/src/p256.dart';

/// Тестові вектори InTrack (`app-activation-vectors.json`), ключі лише тестові.
final Map<String, dynamic> vectors = jsonDecode(
  File('docs/тестові_вектори.json').readAsStringSync(),
);

/// Закритий ключ P-256 з PKCS#8 PEM (Node): скаляр іде після 02 01 01 04 20.
ECPrivateKey privateKeyFromPem(String pem) {
  final der = base64.decode(
    pem.split('\n').where((l) => !l.startsWith('-----')).join(),
  );
  for (var i = 0; i + 37 <= der.length; i++) {
    if (der[i] == 2 &&
        der[i + 1] == 1 &&
        der[i + 2] == 1 &&
        der[i + 3] == 4 &&
        der[i + 4] == 0x20) {
      final d = der.sublist(i + 5, i + 37);
      return ECPrivateKey(
        d.fold<BigInt>(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b)),
        curve,
      );
    }
  }
  throw const FormatException('Не PKCS#8 P-256');
}

/// Тестовий «телефон»: підписує програмно, повертає DER, як Keystore.
Future<Uint8List> signDer(ECPrivateKey key, Uint8List message) async {
  final sig =
      (ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
                ..init(true, PrivateKeyParameter<ECPrivateKey>(key)))
              .generateSignature(message)
          as ECSignature;
  List<int> integer(BigInt v) {
    var b = v.toRadixString(16);
    if (b.length.isOdd) b = '0$b';
    var bytes = [
      for (var i = 0; i < b.length; i += 2)
        int.parse(b.substring(i, i + 2), radix: 16),
    ];
    if (bytes.first & 0x80 != 0) bytes = [0, ...bytes];
    return [0x02, bytes.length, ...bytes];
  }

  final body = [...integer(sig.r), ...integer(sig.s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

/// Розбір `.rzs` так, як це робить InTrack (`openSnapshot`).
({Map<String, dynamic> header, Uint8List db}) openSnapshot(
  Uint8List file,
  ECPrivateKey intrack,
) {
  final nl = file.indexOf(0x0a, 5);
  final token = ascii.decode(file.sublist(5, nl));
  final parts = token.split('.');
  final header =
      jsonDecode(utf8.decode(fromB64u(parts[1]))) as Map<String, dynamic>;
  if (!verifyEs256(
    decodeSpki(fromB64u(header['pub'])),
    ascii.encode('${parts[0]}.${parts[1]}'),
    fromB64u(parts[2]),
  )) {
    throw StateError('підпис телефона не збігається');
  }
  final key = hkdfSha256(
    ecdh(intrack, decodeSpki(fromB64u(header['epk']))),
    ascii.encode('RZS1'),
    utf8.encode(header['aid']),
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(key),
        128,
        fromB64u(header['iv']),
        Uint8List.fromList(utf8.encode(header['aid'])),
      ),
    );
  final db = cipher.process(
    Uint8List.fromList([...file.sublist(nl + 1), ...fromB64u(header['tag'])]),
  );
  return (header: header, db: db);
}
