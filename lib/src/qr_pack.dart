import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'activation.dart';
import 'device_key.dart';
import 'p256.dart';

/// Передача майна між телефонами QR-кодами (RZ2) — однаково в усіх
/// застосунках. Приймач показує маленький код зі своїм разовим ключем,
/// передавач — один чи кілька кодів пакета (кожен окремо зашифрований для
/// приймача й підписаний ключем телефона передавача), приймач повертає
/// підписане підтвердження.
///
/// Код — `RZ2:` і двійкові дані в base45: так QR-код пишеться в
/// буквено-цифровому режимі, щільніше за base64 у байтовому.
/// Протокол — `docs/ПЕРЕДАЧА_RZ2.md`.
const packPrefix = 'RZ2:';

/// Найбільше даних в одному коді пакета: QR-код версії 30 (137×137,
/// рівень L, 2520 буквено-цифрових знаків) — надійно читається з екрана.
const packPartBytes = 1680;

/// Межа для одного рядка, що не влазить у версію 30: версія 40.
const _packPartMaxBytes = 2864;

const _kindInvite = 0x49; // I
const _kindPart = 0x54; // T
const _kindConfirm = 0x43; // C

/// Застосунки — номером, щоб не писати назву в кожен код.
const packApps = ['rozkladka', 'rozkladka_s', 'rozkladka_e', 'rozkladka_d'];

// ---- base45 (RFC 9285) ----

const _b45 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

String base45Encode(List<int> b) {
  final out = StringBuffer();
  for (var i = 0; i + 1 < b.length; i += 2) {
    var n = b[i] * 256 + b[i + 1];
    out
      ..write(_b45[n % 45])
      ..write(_b45[(n ~/ 45) % 45])
      ..write(_b45[n ~/ 2025]);
  }
  if (b.length.isOdd) {
    final n = b.last;
    out
      ..write(_b45[n % 45])
      ..write(_b45[n ~/ 45]);
  }
  return out.toString();
}

Uint8List base45Decode(String s) {
  int v(int i) {
    final x = _b45.indexOf(s[i]);
    if (x < 0) throw const FormatException('Не base45');
    return x;
  }

  if (s.length % 3 == 1) throw const FormatException('Не base45');
  final out = BytesBuilder();
  var i = 0;
  for (; i + 2 < s.length; i += 3) {
    final n = v(i) + v(i + 1) * 45 + v(i + 2) * 2025;
    if (n > 0xffff) throw const FormatException('Не base45');
    out.add([n >> 8, n & 0xff]);
  }
  if (i < s.length) {
    final n = v(i) + v(i + 1) * 45;
    if (n > 0xff) throw const FormatException('Не base45');
    out.addByte(n);
  }
  return out.toBytes();
}

// ---- двійкові поля ----

void _varint(BytesBuilder out, int v) {
  do {
    final b = v & 0x7f;
    v >>= 7;
    out.addByte(b | (v > 0 ? 0x80 : 0));
  } while (v > 0);
}

class _Reader {
  final Uint8List b;
  var p = 0;

  _Reader(this.b);

  int byte() {
    if (p >= b.length) throw const FormatException('Код обрізано');
    return b[p++];
  }

  int varint() {
    var v = 0, shift = 0;
    while (true) {
      final x = byte();
      v |= (x & 0x7f) << shift;
      if (x < 0x80) return v;
      shift += 7;
      if (shift > 35) throw const FormatException('Завелике число');
    }
  }

  Uint8List bytes(int n) {
    if (p + n > b.length) throw const FormatException('Код обрізано');
    return b.sublist(p, p += n);
  }

  String text() => utf8.decode(bytes(varint()));
}

Uint8List _compressKey(List<int> spki) =>
    Uint8List.fromList(decodeSpki(spki).Q!.getEncoded(true));

ECPublicKey _keyOf(List<int> compressed) =>
    ECPublicKey(curve.curve.decodePoint(compressed), curve);

Uint8List _deflate(List<int> b) => Uint8List.fromList(
  ZLibCodec(raw: true, level: ZLibOption.defaultLevel).encode(b),
);

Uint8List _inflate(List<int> b) =>
    Uint8List.fromList(ZLibCodec(raw: true).decode(b));

Uint8List _key(List<int> secret, List<int> receiverKey) =>
    hkdfSha256(secret, ascii.encode('RZ2'), receiverKey);

Future<Uint8List> _sign(DeviceKey key, List<int> message) async =>
    derSignatureToRaw(await key.sign(Uint8List.fromList(message)));

String _code(List<int> bytes) => '$packPrefix${base45Encode(bytes)}';

Uint8List _bytesOf(String code) {
  final t = code.trim();
  if (!t.startsWith(packPrefix)) {
    throw const FormatException('Не код передачі');
  }
  return base45Decode(t.substring(packPrefix.length));
}

// ---- запрошення приймача ----

/// Код приймача: застосунок, номер особи за списком (0 — немає), прізвище,
/// ключ телефона, разовий ключ. Разовий закритий ключ живе лише в пам'яті
/// приймача, поки відкрито екран.
class PackInvite {
  final String app;
  final int person;
  final String name;
  final Uint8List deviceKey; // стиснений P-256, 33 байти
  final Uint8List key; // разовий, стиснений
  final ECPrivateKey? privateKey;

  const PackInvite._(
    this.app,
    this.person,
    this.name,
    this.deviceKey,
    this.key,
    this.privateKey,
  );

  static Future<(PackInvite, String)> create({
    required String app,
    required int person,
    required String name,
    required DeviceKey deviceKey,
  }) async {
    final pair = generateKeyPair();
    final invite = PackInvite._(
      app,
      person,
      name,
      _compressKey(await deviceKey.publicKey()),
      Uint8List.fromList(pair.publicKey.Q!.getEncoded(true)),
      pair.privateKey,
    );
    final out = BytesBuilder()
      ..addByte(_kindInvite)
      ..addByte(packApps.indexOf(app));
    _varint(out, person);
    final n = utf8.encode(name);
    _varint(out, n.length);
    out
      ..add(n)
      ..add(invite.deviceKey)
      ..add(invite.key);
    final body = out.toBytes();
    return (invite, _code([...body, ...await _sign(deviceKey, body)]));
  }

  /// Кидає [ActivationException], якщо це не код приймача чи підпис не той.
  factory PackInvite.decode(String code) {
    const bad = ActivationException('Це не QR-код приймача');
    try {
      final b = _bytesOf(code);
      final r = _Reader(b);
      if (r.byte() != _kindInvite) throw bad;
      final app = packApps[r.byte()];
      final person = r.varint();
      final name = r.text();
      final device = r.bytes(33);
      final key = r.bytes(33);
      final body = b.sublist(0, r.p);
      if (!verifyEs256(_keyOf(device), body, r.bytes(64))) throw bad;
      return PackInvite._(app, person, name, device, key, null);
    } on ActivationException {
      rethrow;
    } catch (_) {
      throw bad;
    }
  }
}

// ---- пакет ----

/// Шапка пакета: хто, кому, підстава і службові дані застосунку.
class PackHeader {
  final int fromPerson;
  final String fromName;
  final int toPerson;
  final String toName;

  /// Підстава: рапорт, наказ, акт… — текстом, як у документі.
  final String basis;

  /// Дані застосунку (напр. реквізити акта) — рядок, зазвичай JSON.
  final String meta;

  const PackHeader({
    required this.fromPerson,
    required this.fromName,
    required this.toPerson,
    required this.toName,
    required this.basis,
    this.meta = '',
  });

  String encode() =>
      jsonEncode([fromPerson, fromName, toPerson, toName, basis, meta]);

  factory PackHeader.decode(String s) {
    final l = jsonDecode(s) as List;
    return PackHeader(
      fromPerson: l[0] as int,
      fromName: l[1] as String,
      toPerson: l[2] as int,
      toName: l[3] as String,
      basis: l[4] as String,
      meta: l[5] as String,
    );
  }
}

/// Готовий пакет передавача: коди й скільки рядків (одиниць) у кожному.
class SealedPack {
  final List<String> codes;
  final List<int> rowsPerCode;

  const SealedPack(this.codes, this.rowsPerCode);

  /// Номер пакета — з першого коду; так незавершену передачу можна
  /// відновити зі збережених кодів після перезапуску.
  String get id => b64u(_bytesOf(codes.first).sublist(2, 8));

  /// Відбиток пакета — що саме підтверджує приймач.
  Uint8List get digest => _digest(codes);

  /// Пакет файлом: коди рядками.
  String toFile() => codes.join('\n');
}

Uint8List _digest(List<String> codes) =>
    sha256(utf8.encode(codes.map((c) => c.trim()).join('\n')));

/// Ділить рядки на коди: у кожен — скільки влізе після стиснення. Рядок,
/// що сам не влазить навіть у найбільший код, — [FormatException]: такий
/// пакет передається лише файлом (`.rzt`).
List<List<String>> _groups(String header, List<String> rows) {
  const overhead = 172; // шапка коду, ключі, iv, тег, підпис
  int size(List<String> g, bool first) =>
      _deflate(utf8.encode([if (first) header, ...g].join('\n'))).length +
      overhead;
  final groups = <List<String>>[];
  var current = <String>[];
  for (final r in rows) {
    final first = groups.isEmpty;
    if (current.isNotEmpty && size([...current, r], first) > packPartBytes) {
      groups.add(current);
      current = [r];
    } else {
      current.add(r);
    }
    if (current.length == 1 &&
        size(current, groups.isEmpty) > _packPartMaxBytes) {
      throw const FormatException('Запис завеликий для QR-коду');
    }
  }
  groups.add(current);
  return groups;
}

/// Пакет для приймача з [invite]: рядки — одиниці у форматі застосунку
/// (без переносів рядка). Кожен код зашифровано разовим ключем приймача й
/// підписано ключем телефона передавача.
Future<SealedPack> sealPack({
  required PackInvite invite,
  required String app,
  required PackHeader header,
  required List<String> rows,
  required DeviceKey deviceKey,
}) async {
  if (rows.any((r) => r.contains('\n'))) {
    throw ArgumentError('Рядок пакета з переносом');
  }
  final head = header.encode();
  final groups = _groups(head, rows);
  final id = randomBytes(6);
  final sender = _compressKey(await deviceKey.publicKey());
  final eph = generateKeyPair();
  final ephKey = eph.publicKey.Q!.getEncoded(true);
  final key = _key(ecdh(eph.privateKey, _keyOf(invite.key)), invite.key);
  final codes = <String>[];
  for (final (i, g) in groups.indexed) {
    final plain = _deflate(utf8.encode([if (i == 0) head, ...g].join('\n')));
    final out = BytesBuilder()
      ..addByte(_kindPart)
      ..addByte(packApps.indexOf(app))
      ..add(id);
    _varint(out, i);
    _varint(out, groups.length);
    final iv = randomBytes(12);
    out
      ..add(sender)
      ..add(ephKey)
      ..add(iv);
    final aad = out.toBytes();
    final sealed = aesGcmEncrypt(key, iv, aad, plain);
    final body = BytesBuilder()
      ..add(aad)
      ..add(sealed.body)
      ..add(sealed.tag);
    final signed = body.toBytes();
    codes.add(_code([...signed, ...await _sign(deviceKey, signed)]));
  }
  return SealedPack(codes, [for (final g in groups) g.length]);
}

/// Прийнятий пакет.
class OpenedPack {
  final String id;
  final String fromApp;
  final PackHeader header;
  final List<String> rows;
  final Uint8List digest;

  const OpenedPack(this.id, this.fromApp, this.header, this.rows, this.digest);
}

/// Приймач збирає коди пакета в будь-якому порядку — з камери, фото чи
/// файлу. Кожен код перевіряється й розшифровується одразу.
class PackAssembler {
  final PackInvite invite;
  final _parts = <int, String>{};
  final _plain = <int, Uint8List>{};
  String? _id;
  Uint8List? _sender;
  String? _app;
  int _total = 0;

  PackAssembler(this.invite);

  int get received => _parts.length;
  int get total => _total;

  /// Додає код; повертає пакет, щойно зібрано всі. Чужий чи пошкоджений
  /// код — [ActivationException]; той самий код удруге — без змін.
  OpenedPack? add(String code) {
    const bad = ActivationException(
      'Код пошкоджено або він призначений не для цього приймача',
    );
    final Uint8List b;
    try {
      b = _bytesOf(code);
    } on FormatException {
      return null; // сторонній QR-код у кадрі
    }
    try {
      final r = _Reader(b);
      if (r.byte() != _kindPart) throw bad;
      final app = packApps[r.byte()];
      final id = b64u(r.bytes(6));
      final i = r.varint();
      final n = r.varint();
      final sender = r.bytes(33);
      final eph = r.bytes(33);
      final iv = r.bytes(12);
      final aad = b.sublist(0, r.p);
      if (b.length < r.p + 16 + 64) throw bad;
      final signedEnd = b.length - 64;
      if (!verifyEs256(
        _keyOf(sender),
        b.sublist(0, signedEnd),
        b.sublist(signedEnd),
      )) {
        throw bad;
      }
      if (_id != null && (_id != id || !_same(_sender!, sender))) {
        throw const ActivationException('Це код іншого пакета');
      }
      final key = _key(ecdh(invite.privateKey!, _keyOf(eph)), invite.key);
      final plain = aesGcmDecrypt(
        key,
        iv,
        aad,
        b.sublist(r.p, signedEnd - 16),
        b.sublist(signedEnd - 16, signedEnd),
      );
      if (i >= n) throw bad;
      _id = id;
      _sender = sender;
      _app = app;
      _total = n;
      _parts[i] = code.trim();
      _plain[i] = plain;
    } on ActivationException {
      rethrow;
    } catch (_) {
      throw bad;
    }
    if (_parts.length < _total) return null;
    final lines = <String>[];
    for (var i = 0; i < _total; i++) {
      lines.addAll(utf8.decode(_inflate(_plain[i]!)).split('\n'));
    }
    return OpenedPack(
      _id!,
      _app!,
      PackHeader.decode(lines.first),
      lines.sublist(1),
      _digest([for (var i = 0; i < _total; i++) _parts[i]!]),
    );
  }

  /// Файл пакета — коди рядками.
  OpenedPack? addFile(String text) {
    OpenedPack? done;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isNotEmpty) done = add(line) ?? done;
    }
    return done;
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---- підтвердження ----

/// Підтвердження приймача: номер пакета й підпис його відбитка ключем
/// телефона приймача.
Future<String> confirmPack(OpenedPack pack, DeviceKey deviceKey) async {
  final body = [_kindConfirm, ...fromB64u(pack.id)];
  return _code([
    ...body,
    ...await _sign(deviceKey, [...body, ...pack.digest]),
  ]);
}

/// Чи це підтвердження саме цього пакета від телефона приймача
/// ([receiverDeviceKey] — `PackInvite.deviceKey`, стиснений).
bool verifyPackConfirmation(
  String code,
  SealedPack pack,
  List<int> receiverDeviceKey,
) {
  try {
    final b = _bytesOf(code);
    if (b.length != 1 + 6 + 64 || b[0] != _kindConfirm) return false;
    if (b64u(b.sublist(1, 7)) != pack.id) return false;
    return verifyEs256(_keyOf(receiverDeviceKey), [
      ...b.sublist(0, 7),
      ...pack.digest,
    ], b.sublist(7));
  } on FormatException {
    return false;
  }
}
