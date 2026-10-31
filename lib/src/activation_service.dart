import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'activation.dart';
import 'activation_store.dart';
import 'device_code.dart' as code;
import 'device_key.dart';
import 'snapshot.dart';

/// Активація застосунку. Сплячий режим: доки QR-код не відкрито жодного
/// разу, застосунок працює як раніше; після — назавжди лише з доступом.
class ActivationService extends ChangeNotifier {
  /// Поточний екземпляр застосунку — для перевірки в шарі бази.
  static ActivationService? current;

  /// `rozkladka` (В) · `rozkladka_s` · `rozkladka_e` · `rozkladka_d`.
  final String app;
  final List<int> issuerSpki;
  final DeviceKey key;
  final ActivationStore _store;
  final DateTime Function() _now;

  /// Підтвердження відбитком або PIN; null — без підтвердження.
  final Future<bool> Function()? _authenticate;

  ActivationService({
    required this.app,
    required this.issuerSpki,
    this.key = const DeviceKey(),
    ActivationStore? store,
    DateTime Function()? now,
    Future<bool> Function()? authenticate,
  }) : _store = store ?? ActivationStore(),
       _now = now ?? DateTime.now,
       _authenticate = authenticate ?? _localAuth;

  static Future<bool> _localAuth() => LocalAuthentication().authenticate(
    localizedReason: 'Підтвердіть збереження знімка',
  );

  Activation? activation;
  int _counter = 0;
  bool _askAuth = false;
  String? _deviceCode;

  bool get isActivated => activation != null;

  /// Доступ закінчився: внесення заблоковане, лишається знімок.
  bool get isLocked => activation?.isExpired(_now()) ?? false;

  /// Відбиток або PIN на кожен знімок — лише якщо людина ввімкнула.
  bool get askAuth => _askAuth;

  Future<void> load() async {
    final data = await _store.read();
    _counter = (data['counter'] as int?) ?? 0;
    _askAuth = (data['askAuth'] as bool?) ?? false;
    final token = data['token'] as String?;
    final dev = data['dev'] as String?;
    if (token != null && dev != null) {
      activation = verifyActivation(
        token,
        issuerSpki: issuerSpki,
        app: app,
        deviceCode: dev,
        now: _now(),
        firstScan: false,
      );
    }
    notifyListeners();
  }

  Future<void> _save() => _store.write({
    if (activation != null) 'token': activation!.token,
    if (activation != null) 'dev': activation!.deviceCode,
    'counter': _counter,
    'askAuth': _askAuth,
  });

  /// Код цього телефона; ключ створюється при першому зверненні.
  Future<String> deviceCode() async =>
      _deviceCode ??= code.deviceCode(await key.publicKey());

  /// Відкриває QR-код або вміст файлу `.rza`. Новий код того самого
  /// телефона замінює попередній (продовження на новий рік).
  Future<Activation> activate(String token) async {
    activation = verifyActivation(
      token,
      issuerSpki: issuerSpki,
      app: app,
      deviceCode: await deviceCode(),
      now: _now(),
    );
    await _save();
    notifyListeners();
    return activation!;
  }

  Future<void> setAskAuth(bool value) async {
    _askAuth = value;
    await _save();
    notifyListeners();
  }

  /// Кидає [ActivationException], якщо вносити зміни не можна.
  void ensureCanEdit() {
    if (isLocked) {
      throw const ActivationException(
        'Доступ закінчився — внесення змін заблоковане. '
        'Потрібен новий QR-код від посадової особи, що веде облік майна.',
      );
    }
  }

  /// Знімок `.rzs` для InTrack. Лічильник зберігається до віддачі файла,
  /// тож номер ніколи не повторюється.
  Future<Uint8List> seal(Uint8List db) async {
    final a = activation;
    if (a == null) {
      throw const ActivationException('Застосунок не активовано');
    }
    if (_askAuth && !await _authenticate!()) {
      throw const ActivationException('Підтвердження не пройдено');
    }
    _counter++;
    await _save();
    return sealSnapshot(
      db: db,
      app: app,
      aid: a.aid,
      counter: _counter,
      devicePublicSpki: await key.publicKey(),
      sign: key.sign,
      issuerSpki: issuerSpki,
      time: _now(),
    );
  }
}
