import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/activation.dart';
import 'package:rozkladka_common/src/device_key.dart';
import 'package:rozkladka_common/src/p256.dart';
import 'package:rozkladka_common/src/transfer.dart';

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

void main() {
  final issuer = base64.decode(vectors['intrack_public_spki_b64']);
  final now = DateTime.utc(2026, 11, 1);
  final sender = _Phone();
  final receiver = _Phone();
  final payload = utf8.encode(jsonEncode({'units': List.filled(200, 'майно')}));

  Future<TransferInvite> invite() => TransferInvite.create(
    name: 'Приймач',
    app: 'rozkladka_e',
    deviceKey: receiver,
  );

  test('запрошення → пакет → підтвердження', () async {
    final own = await invite();
    final scanned = TransferInvite.decode(own.encode());
    expect(scanned.party(issuer, now).name, 'Приймач');
    expect(scanned.party(issuer, now).confirmed, isFalse);

    final package = await sealTransfer(
      payload: payload,
      invite: scanned,
      senderName: 'Передавач',
      deviceKey: sender,
    );
    final opened = openTransfer(
      package: package,
      invite: own,
      issuerSpki: issuer,
      now: now,
    );
    expect(opened.payload, payload);
    expect(opened.sender.name, 'Передавач');
    expect(opened.sender.confirmed, isFalse);

    final confirmation = await confirmTransfer(package, receiver);
    expect(
      verifyTransferConfirmation(
        confirmation,
        package,
        await receiver.publicKey(),
      ),
      isTrue,
    );
    expect(
      verifyTransferConfirmation(
        confirmation,
        package,
        await sender.publicKey(),
      ),
      isFalse,
    );
    expect(
      verifyTransferConfirmation(
        confirmation,
        Uint8List(3),
        await receiver.publicKey(),
      ),
      isFalse,
    );
  });

  test('змінений пакет і чужий приймач відхиляються', () async {
    final own = await invite();
    final package = await sealTransfer(
      payload: payload,
      invite: own,
      senderName: 'Передавач',
      deviceKey: sender,
    );
    final forged = Uint8List.fromList(package)..[package.length - 1] ^= 1;
    expect(
      () => openTransfer(
        package: forged,
        invite: own,
        issuerSpki: issuer,
        now: now,
      ),
      throwsA(isA<ActivationException>()),
    );
    expect(
      () => openTransfer(
        package: package,
        invite: TransferInvite(
          privateKey: generateKeyPair().privateKey,
          key: own.key,
          name: '',
          app: '',
          devicePublicKey: own.devicePublicKey,
          signature: own.signature,
        ),
        issuerSpki: issuer,
        now: now,
      ),
      throwsA(isA<ActivationException>()),
    );
  });

  test('запрошення з підміненим ключем не приймається', () async {
    final own = await invite();
    final forged = TransferInvite(
      key: encodeSpki(generateKeyPair().publicKey),
      name: own.name,
      app: own.app,
      devicePublicKey: own.devicePublicKey,
      signature: own.signature,
    );
    expect(
      () => TransferInvite.decode(forged.encode()),
      throwsA(isA<ActivationException>()),
    );
  });

  test('серія QR-кодів збирається в будь-якому порядку', () {
    final data = List.generate(250000, (i) => i % 256);
    final codes = splitForQr(data);
    expect(codes, hasLength(120));
    expect(codes.every((c) => c.length <= qrMaxChars), isTrue);
    final a = QrAssembler();
    Uint8List? result;
    for (final c in codes.reversed) {
      expect(result, isNull);
      result = a.add(c);
      a.add('сторонній код');
    }
    expect(result, data);
  });
}
