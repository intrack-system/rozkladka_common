import 'dart:convert';

import 'p256.dart';

/// Помилка з поясненням для людини: показується як є.
class ActivationException implements Exception {
  final String message;
  const ActivationException(this.message);

  @override
  String toString() => message;
}

/// Доступ, виданий InTrack (QR-код або файл `.rza`).
class Activation {
  /// JWS як є — зберігається й перевіряється заново при кожному запуску.
  final String token;
  final String aid;
  final String app;
  final String deviceCode;
  final int personId;
  final String personName;
  final String position;
  final int departmentId;
  final String departmentName;
  final DateTime issuedAt;

  /// До коли телефон працює (кінець року); після — лише знімок.
  final DateTime expiresAt;

  /// До коли QR-код можна відсканувати (тиждень від видачі). Якщо InTrack
  /// його не дає — те саме, що [expiresAt].
  final DateTime scanBefore;
  final String issuedBy;

  const Activation({
    required this.token,
    required this.aid,
    required this.app,
    required this.deviceCode,
    required this.personId,
    required this.personName,
    required this.position,
    required this.departmentId,
    required this.departmentName,
    required this.issuedAt,
    required this.expiresAt,
    required this.scanBefore,
    required this.issuedBy,
  });

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

/// Перевіряє QR-код: підпис ключем InTrack, застосунок і код цього телефона.
/// [firstScan] — ще й строк сканування; при повторному читанні збереженого
/// доступу він не важить.
Activation verifyActivation(
  String token, {
  required List<int> intrackSpki,
  required String app,
  required String deviceCode,
  required DateTime now,
  bool firstScan = true,
}) {
  const fail = ActivationException.new;
  final parts = token.trim().split('.');
  if (parts.length != 3) throw fail('Це не QR-код активації');
  final Map<String, dynamic> head;
  final Map<String, dynamic> body;
  try {
    head = jsonDecode(utf8.decode(fromB64u(parts[0])));
    body = jsonDecode(utf8.decode(fromB64u(parts[1])));
  } on FormatException {
    throw fail('Це не QR-код активації');
  }
  if (head['alg'] != 'ES256' || head['typ'] != 'RZA') {
    throw fail('Це не QR-код активації');
  }
  final signed = verifyEs256(
    decodeSpki(intrackSpki),
    ascii.encode('${parts[0]}.${parts[1]}'),
    fromB64u(parts[2]),
  );
  if (!signed) {
    throw fail('QR-код видано не цим InTrack або його змінено');
  }
  if (body['v'] != 1) throw fail('Невідома версія QR-коду');
  if (body['app'] != app) throw fail('QR-код видано для іншого застосунку');
  if (body['dev'] != deviceCode) {
    throw fail('QR-код видано для іншого телефона');
  }
  final sub = body['sub'] as Map<String, dynamic>;
  final dept = body['dept'] as Map<String, dynamic>;
  final expiresAt = DateTime.parse(body['exp'] as String);
  final scanBefore = body['scan_before'] == null
      ? expiresAt
      : DateTime.parse(body['scan_before'] as String);
  if (firstScan && !now.isBefore(scanBefore)) {
    throw fail('Строк дії QR-коду минув — потрібен новий');
  }
  return Activation(
    token: token.trim(),
    aid: body['aid'] as String,
    app: app,
    deviceCode: deviceCode,
    personId: sub['id'] as int,
    personName: sub['name'] as String,
    position: (sub['position'] as String?) ?? '',
    departmentId: dept['id'] as int,
    departmentName: dept['name'] as String,
    issuedAt: DateTime.parse(body['iat'] as String),
    expiresAt: expiresAt,
    scanBefore: scanBefore,
    issuedBy: (body['by'] as String?) ?? '',
  );
}
