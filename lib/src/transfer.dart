import 'dart:typed_data';

import 'p256.dart';

/// Серія QR-кодів RZQ1 — для довгого QR-коду активації з обліку майна.
/// Передача майна між телефонами — `qr_pack.dart` (RZ2).
const _chunkPrefix = 'RZQ1';

/// Найбільший QR-код — версія 40 (177×177 клітинок), рівень L: 2953 байти
/// тексту. Частина в 2100 байтів у base64url із заголовком займає до ~2830.
const qrMaxChars = 2953;

/// Серія QR-кодів: `RZQ1.<відбиток>.<номер>.<усього>.<частина>`.
List<String> splitForQr(List<int> data, {int chunkBytes = 2100}) {
  final id = b64u(sha256(data).sublist(0, 6));
  final total = (data.length / chunkBytes).ceil().clamp(1, 1 << 30);
  return [
    for (var i = 0; i < total; i++)
      '$_chunkPrefix.$id.$i.$total.'
          '${b64u(data.sublist(i * chunkBytes, (i * chunkBytes + chunkBytes).clamp(0, data.length)))}',
  ];
}

/// Збирає серію QR-кодів у будь-якому порядку.
class QrAssembler {
  final Map<int, List<int>> _parts = {};
  String? _id;
  int _total = 0;

  int get received => _parts.length;
  int get total => _total;

  /// Повертає дані, щойно зібрано всю серію; чужі коди ігнорує.
  Uint8List? add(String text) {
    final p = text.split('.');
    if (p.length != 5 || p[0] != _chunkPrefix) return null;
    final index = int.tryParse(p[2]);
    final total = int.tryParse(p[3]);
    if (index == null || total == null || index >= total) return null;
    if (_id != p[1]) {
      _id = p[1];
      _parts.clear();
    }
    _total = total;
    _parts[index] = fromB64u(p[4]);
    if (_parts.length < total) return null;
    final data = Uint8List.fromList([
      for (var i = 0; i < total; i++) ..._parts[i]!,
    ]);
    return b64u(sha256(data).sublist(0, 6)) == _id ? data : null;
  }
}
