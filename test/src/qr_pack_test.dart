import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:rozkladka_common/src/activation.dart';
import 'package:rozkladka_common/src/device_key.dart';
import 'package:rozkladka_common/src/p256.dart';
import 'package:rozkladka_common/src/qr_pack.dart';

import '../vectors.dart';

/// Телефон із програмним ключем.
class _Phone extends DeviceKey {
  final _pair = generateKeyPair();

  @override
  Future<Uint8List> publicKey() async => encodeSpki(_pair.publicKey);

  @override
  Future<Uint8List> sign(Uint8List message) =>
      signDer(_pair.privateKey, message);
}

/// Версія QR-коду, якою його покаже застосунок (буквено-цифровий режим).
int _version(String code) {
  for (var v = 1; v <= 40; v++) {
    try {
      QrImage(QrCode(v, QrErrorCorrectLevel.L)..addAlphaNumeric(code));
      return v;
    } on InputTooLongException {
      continue;
    }
  }
  return 99;
}

void main() {
  final sender = _Phone();
  final receiver = _Phone();
  const header = PackHeader(
    fromPerson: 1000,
    fromName: 'Фальфушинський Я.І.',
    toPerson: 1001,
    toName: 'Фальфушинський Л.І.',
    basis: 'рапорт № 12/26 від 06.11.2026',
    meta: '{"act":"41"}',
  );
  // Паспорти, як у звіті: номер, найменування, інв., зав., дати, особа.
  final rows = [
    for (var i = 0; i < 137; i++)
      '${50000 + i},${i % 60},${11130000 + i * 37}/${i % 99},'
          '${160000000000 + i * 7919},${8000 + i},${8100 + i},1000,2',
  ];

  test('base45 туди й назад', () {
    for (final b in [
      <int>[],
      [0],
      [255, 0, 1],
      List.generate(300, (i) => i * 7 % 256),
    ]) {
      expect(base45Decode(base45Encode(b)), b);
    }
    expect(base45Encode('AB'.codeUnits), 'BB8');
  });

  test('запрошення → пакет 137 одиниць → підтвердження', () async {
    final (own, inviteCode) = await PackInvite.create(
      app: 'rozkladka_e',
      person: 1001,
      name: 'Фальфушинський Л.І.',
      deviceKey: receiver,
    );
    expect(_version(inviteCode), lessThanOrEqualTo(10));
    final scanned = PackInvite.decode(inviteCode);
    expect(scanned.person, 1001);
    expect(scanned.app, 'rozkladka_e');

    final pack = await sealPack(
      invite: scanned,
      app: 'rozkladka_s',
      header: header,
      rows: rows,
      deviceKey: sender,
    );
    expect(pack.codes.length, lessThanOrEqualTo(3));
    expect(pack.rowsPerCode.fold(0, (a, b) => a + b), 137);
    for (final c in pack.codes) {
      expect(_version(c), lessThanOrEqualTo(30));
    }

    final a = PackAssembler(own);
    OpenedPack? opened;
    for (final c in pack.codes.reversed) {
      expect(opened, isNull);
      a.add('сторонній код');
      opened = a.add(c);
      a.add(c); // повтор нічого не ламає
    }
    expect(opened!.rows, rows);
    expect(opened.header.basis, header.basis);
    expect(opened.header.toPerson, 1001);
    expect(opened.fromApp, 'rozkladka_s');

    final confirmation = await confirmPack(opened, receiver);
    expect(
      verifyPackConfirmation(confirmation, pack, scanned.deviceKey),
      isTrue,
    );
    final restored = SealedPack(pack.codes, pack.rowsPerCode);
    expect(
      verifyPackConfirmation(confirmation, restored, scanned.deviceKey),
      isTrue,
    );
  });

  test('чужий приймач, підробка й файл', () async {
    final (own, inviteCode) = await PackInvite.create(
      app: 'rozkladka_e',
      person: 1001,
      name: 'Л',
      deviceKey: receiver,
    );
    final (other, _) = await PackInvite.create(
      app: 'rozkladka_e',
      person: 1002,
      name: 'Інший',
      deviceKey: _Phone(),
    );
    final pack = await sealPack(
      invite: PackInvite.decode(inviteCode),
      app: 'rozkladka_e',
      header: header,
      rows: rows.take(5).toList(),
      deviceKey: sender,
    );
    expect(
      () => PackAssembler(other).add(pack.codes.single),
      throwsA(isA<ActivationException>()),
    );
    final c = pack.codes.single;
    final forged =
        '${c.substring(0, 40)}${c[40] == 'A' ? 'B' : 'A'}'
        '${c.substring(41)}';
    expect(
      () => PackAssembler(own).add(forged),
      throwsA(isA<ActivationException>()),
    );
    expect(PackAssembler(own).addFile(pack.toFile())!.rows.length, 5);
    expect(
      () => PackInvite.decode('RZ2:${inviteCode.substring(5)}'),
      throwsA(isA<ActivationException>()),
    );
  });
}
