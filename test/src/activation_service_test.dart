import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/activation.dart';
import 'package:rozkladka_common/src/activation_service.dart';
import 'package:rozkladka_common/src/activation_store.dart';
import 'package:rozkladka_common/src/device_key.dart';

import '../vectors.dart';

class _FakeKey extends DeviceKey {
  final key = privateKeyFromPem(vectors['device_private_pkcs8_pem']);

  @override
  Future<Uint8List> publicKey() async =>
      base64.decode(vectors['device_public_spki_b64']);

  @override
  Future<Uint8List> sign(Uint8List message) => signDer(key, message);
}

void main() {
  final issued = DateTime.parse(vectors['activation_payload']['iat']);
  final exp = DateTime.parse(vectors['activation_payload']['exp']);
  final intrackKey = privateKeyFromPem(vectors['intrack_private_pkcs8_pem']);
  late Directory dir;
  late DateTime now;
  var authCalls = 0;

  ActivationService service() => ActivationService(
    app: 'rozkladka_e',
    issuerSpki: base64.decode(vectors['intrack_public_spki_b64']),
    key: _FakeKey(),
    store: ActivationStore(dir: () async => dir),
    now: () => now,
    authenticate: () async {
      authCalls++;
      return true;
    },
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('activation');
    now = issued.add(const Duration(hours: 1));
    authCalls = 0;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'сплячий режим: без QR-коду не активовано і нічого не заблоковано',
    () async {
      final s = service();
      await s.load();
      expect(s.isActivated, isFalse);
      expect(s.isLocked, isFalse);
      s.ensureCanEdit();
      expect(() => s.seal(Uint8List(1)), throwsA(isA<ActivationException>()));
    },
  );

  test('активація зберігається, лічильник знімків лише зростає', () async {
    final s = service();
    await s.activate(vectors['activation_token']);
    final first = openSnapshot(
      await s.seal(Uint8List.fromList([1, 2])),
      intrackKey,
    );
    final again = service();
    await again.load();
    expect(again.activation!.personName, 'Пупкін Петро Петрович');
    final second = openSnapshot(
      await again.seal(Uint8List.fromList([3])),
      intrackKey,
    );
    expect(first.header['n'], 1);
    expect(second.header['n'], 2);
    expect(second.db, [3]);
  });

  test('після строку дії — лише знімок, внесення заблоковане', () async {
    final s = service();
    await s.activate(vectors['activation_token']);
    now = exp.add(const Duration(minutes: 1));
    expect(s.isLocked, isTrue);
    expect(s.ensureCanEdit, throwsA(isA<ActivationException>()));
    await s.seal(Uint8List(1));
  });

  test('відбиток або PIN — лише коли ввімкнено', () async {
    final s = service();
    await s.activate(vectors['activation_token']);
    await s.seal(Uint8List(1));
    expect(authCalls, 0);
    await s.setAskAuth(true);
    await s.seal(Uint8List(1));
    expect(authCalls, 1);
  });
}
