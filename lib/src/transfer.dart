import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'activation.dart';
import 'device_code.dart';
import 'device_key.dart';
import 'p256.dart';

/// Передача майна між телефонами без мережі. Приймач показує запрошення з
/// разовим ключем, передавач шифрує пакет для цього ключа й підписує своїм
/// ключем телефона, приймач повертає підписане підтвердження.
// ponytail: формат кодування ще не затверджено (перша цифра в позначках), тож
// змінювати його вільно, поки пакетами не користуються.
const _packageMagic = 'RZT1\n';
const _invitePrefix = 'RZI1.';
const _confirmPrefix = 'RZC1.';
const _chunkPrefix = 'RZQ1';

/// Хто по той бік: особа підтверджена, лише якщо її активація чинна й виданий
/// для цього самого телефона.
class TransferParty {
  final String name;
  final bool confirmed;
  final List<int> devicePublicKey;

  const TransferParty(this.name, this.confirmed, this.devicePublicKey);
}

/// Особа з ключа телефона й необов'язкового доступу.
TransferParty _party(
  String name,
  List<int> devicePublicKey,
  String? token,
  String app,
  List<int> issuerSpki,
  DateTime now,
) {
  if (token != null) {
    try {
      final a = verifyActivation(
        token,
        issuerSpki: issuerSpki,
        app: app,
        deviceCode: deviceCode(devicePublicKey),
        now: now,
        firstScan: false,
      );
      if (!a.isExpired(now)) {
        return TransferParty(a.personName, true, devicePublicKey);
      }
    } on ActivationException {
      // Доступ не підтвердився — особа лишається непідтвердженою.
    }
  }
  return TransferParty(name, false, devicePublicKey);
}

/// Запрошення приймача. Закрита частина разового ключа живе лише в пам'яті
/// приймача, поки відкрито екран.
class TransferInvite {
  final ECPrivateKey? privateKey;
  final List<int> key;
  final String name;
  final String app;
  final List<int> devicePublicKey;
  final List<int> signature;
  final String? activationToken;

  const TransferInvite({
    this.privateKey,
    required this.key,
    required this.name,
    required this.app,
    required this.devicePublicKey,
    required this.signature,
    this.activationToken,
  });

  static Future<TransferInvite> create({
    required String name,
    required String app,
    required DeviceKey deviceKey,
    String? activationToken,
  }) async {
    final pair = generateKeyPair();
    final key = encodeSpki(pair.publicKey);
    return TransferInvite(
      privateKey: pair.privateKey,
      key: key,
      name: name,
      app: app,
      devicePublicKey: await deviceKey.publicKey(),
      signature: derSignatureToRaw(
        await deviceKey.sign(Uint8List.fromList(key)),
      ),
      activationToken: activationToken,
    );
  }

  String encode() =>
      _invitePrefix +
      b64u(
        utf8.encode(
          jsonEncode({
            'k': b64u(key),
            'n': name,
            'app': app,
            'pub': b64u(devicePublicKey),
            'sig': b64u(signature),
            'a': ?activationToken,
          }),
        ),
      );

  /// Кидає [ActivationException], якщо це не запрошення або підпис не той.
  factory TransferInvite.decode(String text) {
    const bad = ActivationException('Це не QR-код приймача');
    if (!text.startsWith(_invitePrefix)) throw bad;
    try {
      final m =
          jsonDecode(
                utf8.decode(fromB64u(text.substring(_invitePrefix.length))),
              )
              as Map<String, dynamic>;
      final invite = TransferInvite(
        key: fromB64u(m['k'] as String),
        name: m['n'] as String,
        app: m['app'] as String,
        devicePublicKey: fromB64u(m['pub'] as String),
        signature: fromB64u(m['sig'] as String),
        activationToken: m['a'] as String?,
      );
      if (!verifyEs256(
        decodeSpki(invite.devicePublicKey),
        invite.key,
        invite.signature,
      )) {
        throw bad;
      }
      return invite;
    } on FormatException {
      throw bad;
    }
  }

  TransferParty party(List<int> issuerSpki, DateTime now) =>
      _party(name, devicePublicKey, activationToken, app, issuerSpki, now);
}

/// Пакет для приймача: стиснутий, зашифрований для його разового ключа,
/// підписаний ключем телефона передавача.
Future<Uint8List> sealTransfer({
  required List<int> payload,
  required TransferInvite invite,
  required String senderName,
  required DeviceKey deviceKey,
  String? activationToken,
}) async {
  final eph = generateKeyPair();
  final plain = gzip.encode(payload);
  final key = hkdfSha256(
    ecdh(eph.privateKey, decodeSpki(invite.key)),
    ascii.encode('RZT1'),
    invite.key,
  );
  final iv = randomBytes(12);
  final sealed = aesGcmEncrypt(key, iv, invite.key, plain);
  final header = b64u(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'app': invite.app,
        'n': senderName,
        'pub': b64u(await deviceKey.publicKey()),
        'epk': b64u(encodeSpki(eph.publicKey)),
        'iv': b64u(iv),
        'tag': b64u(sealed.tag),
        'sha256': b64u(sha256(sealed.body)),
        'a': ?activationToken,
      }),
    ),
  );
  final sig = derSignatureToRaw(
    await deviceKey.sign(Uint8List.fromList(ascii.encode(header))),
  );
  return Uint8List.fromList([
    ...ascii.encode('$_packageMagic$header.${b64u(sig)}\n'),
    ...sealed.body,
  ]);
}

/// Кидає [ActivationException], якщо пакет пошкоджено, підроблено чи він не
/// для цього приймача.
({Uint8List payload, TransferParty sender}) openTransfer({
  required List<int> package,
  required TransferInvite invite,
  required List<int> issuerSpki,
  required DateTime now,
}) {
  const bad = ActivationException(
    'Пакет пошкоджено або він призначений не для цього приймача',
  );
  final magic = ascii.encode(_packageMagic);
  if (package.length < magic.length ||
      ascii.decode(package.sublist(0, magic.length), allowInvalid: true) !=
          _packageMagic) {
    throw bad;
  }
  final nl = package.indexOf(0x0a, magic.length);
  if (nl < 0) throw bad;
  try {
    final parts = ascii.decode(package.sublist(magic.length, nl)).split('.');
    final m =
        jsonDecode(utf8.decode(fromB64u(parts[0]))) as Map<String, dynamic>;
    final senderPub = fromB64u(m['pub'] as String);
    if (!verifyEs256(
      decodeSpki(senderPub),
      ascii.encode(parts[0]),
      fromB64u(parts[1]),
    )) {
      throw bad;
    }
    final body = package.sublist(nl + 1);
    final key = hkdfSha256(
      ecdh(invite.privateKey!, decodeSpki(fromB64u(m['epk'] as String))),
      ascii.encode('RZT1'),
      invite.key,
    );
    final plain = aesGcmDecrypt(
      key,
      fromB64u(m['iv'] as String),
      invite.key,
      body,
      fromB64u(m['tag'] as String),
    );
    return (
      payload: Uint8List.fromList(gzip.decode(plain)),
      sender: _party(
        m['n'] as String,
        senderPub,
        m['a'] as String?,
        m['app'] as String,
        issuerSpki,
        now,
      ),
    );
  } on ActivationException {
    rethrow;
  } catch (_) {
    throw bad;
  }
}

/// Підтвердження приймача: підпис відбитка пакета його ключем телефона.
Future<String> confirmTransfer(List<int> package, DeviceKey deviceKey) async {
  final digest = sha256(package);
  final sig = derSignatureToRaw(await deviceKey.sign(digest));
  return '$_confirmPrefix${b64u(digest)}.${b64u(sig)}';
}

/// Чи це підтвердження саме цього пакета від телефона з запрошення.
bool verifyTransferConfirmation(
  String text,
  List<int> package,
  List<int> receiverDevicePublicKey,
) {
  if (!text.startsWith(_confirmPrefix)) return false;
  final parts = text.substring(_confirmPrefix.length).split('.');
  if (parts.length != 2) return false;
  try {
    final digest = fromB64u(parts[0]);
    final own = sha256(package);
    if (digest.length != own.length) return false;
    for (var i = 0; i < own.length; i++) {
      if (digest[i] != own[i]) return false;
    }
    return verifyEs256(
      decodeSpki(receiverDevicePublicKey),
      digest,
      fromB64u(parts[1]),
    );
  } on FormatException {
    return false;
  }
}

/// Серія QR-кодів: `RZQ1.<відбиток>.<номер>.<усього>.<частина>`.
List<String> splitForQr(List<int> data, {int chunkBytes = 600}) {
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
