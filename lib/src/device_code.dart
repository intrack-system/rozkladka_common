import 'p256.dart';

/// Код телефона з відкритого ключа (SPKI DER): перші 55 біт SHA-256 →
/// 11 символів Crockford base32 + контрольний символ.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String deviceCode(List<int> spkiDer) {
  final h = sha256(spkiDer);
  final bits = h
      .sublist(0, 7)
      .map((b) => b.toRadixString(2).padLeft(8, '0'))
      .join();
  final data = List.generate(
    11,
    (i) => _alphabet[int.parse(bits.substring(i * 5, i * 5 + 5), radix: 2)],
  ).join();
  return data + _checkChar(data);
}

String _checkChar(String data) {
  var sum = 0;
  for (var i = 0; i < data.length; i++) {
    sum += (i + 1) * _alphabet.indexOf(data[i]);
  }
  return _alphabet[sum % 32];
}

/// `XXXX-XXXX-XXXX` — для показу людині.
String formatDeviceCode(String code) =>
    '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}';
