import 'package:flutter/services.dart';

/// Ключ телефона ECDSA P-256 у Keystore / Secure Enclave. Закрита частина
/// телефона не покидає; створюється при першому зверненні.
class DeviceKey {
  static const _channel = MethodChannel('rozkladka_common/device_key');

  const DeviceKey();

  /// Відкритий ключ, SubjectPublicKeyInfo DER.
  Future<Uint8List> publicKey() async =>
      (await _channel.invokeMethod<Uint8List>('publicKey'))!;

  /// Підпис SHA-256/ECDSA у DER.
  Future<Uint8List> sign(Uint8List message) async =>
      (await _channel.invokeMethod<Uint8List>('sign', message))!;
}
