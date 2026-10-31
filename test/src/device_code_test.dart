import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/src/device_code.dart';
import 'package:rozkladka_common/src/p256.dart';

import '../vectors.dart';

void main() {
  test('код телефона збігається з InTrack', () {
    final code = deviceCode(
      fromB64u(
        vectors['device_public_spki_b64']
            .replaceAll('+', '-')
            .replaceAll('/', '_'),
      ),
    );
    expect(code, vectors['device_code']);
    expect(formatDeviceCode(code), vectors['device_code_display']);
  });
}
