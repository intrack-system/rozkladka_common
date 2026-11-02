import 'dart:convert';
import 'dart:io';

import 'p256.dart';

/// Помилка з поясненням для людини: показується як є.
class ActivationException implements Exception {
  final String message;
  const ActivationException(this.message);

  @override
  String toString() => message;
}

/// Особа зі списку особового складу підрозділу (з установчого наказу).
/// Номер — чотиризначний, у межах підрозділу; нові отримують наступний.
class StaffMember {
  final int id;

  /// Прізвище з ініціалами.
  final String name;

  /// Позначки функцій: `k` — комірник, `z` — виконує функції комірника на
  /// час його відсутності, `e` — експлуатує обладнання, `m` — може бути
  /// матеріально відповідальною особою.
  final String roles;

  const StaffMember(this.id, this.name, this.roles);

  bool get isKeeper => roles.contains('k');
  bool get isDeputyKeeper => roles.contains('z');
  bool get operates => roles.contains('e');
  bool get mayBeResponsible => roles.contains('m');

  /// Може видавати майно зі складу.
  bool get mayIssue => isKeeper || isDeputyKeeper;
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

  /// Номер цієї особи в списку [staff]; null — QR-код без списку.
  final int? staffId;

  /// Особовий склад підрозділу: кому можна передавати й від кого приймати.
  final List<StaffMember> staff;

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
    this.staffId,
    this.staff = const [],
  });

  StaffMember? get self => staff.where((m) => m.id == staffId).firstOrNull;

  StaffMember? memberById(int id) => staff.where((m) => m.id == id).firstOrNull;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

/// Перевіряє QR-код: підпис ключем InTrack, застосунок і код цього телефона.
/// [firstScan] — ще й строк сканування; при повторному читанні збереженого
/// доступу він не важить.
Activation verifyActivation(
  String token, {
  required List<int> issuerSpki,
  required String app,
  required String deviceCode,
  required DateTime now,
  bool firstScan = true,
}) {
  const fail = ActivationException.new;
  final body = _verifiedBody(token.trim(), issuerSpki);
  if (body['v'] != 1 && body['v'] != 2) {
    throw fail('Невідома версія QR-коду');
  }
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
    staffId: sub['sid'] as int?,
    staff: [
      for (final r in (body['staff'] as List?) ?? const [])
        StaffMember(
          (r as List)[0] as int,
          r[1] as String,
          r.length > 2 ? r[2] as String : '',
        ),
    ],
  );
}

/// Вміст QR-коду після перевірки підпису. Два вигляди:
/// `RZA2.<base64url(raw deflate(JSON))>.<підпис>` — стиснутий, вміщує список
/// особового складу; JWS із `typ: RZA` — перший, без списку.
Map<String, dynamic> _verifiedBody(String token, List<int> issuerSpki) {
  const fail = ActivationException.new;
  final parts = token.split('.');
  if (parts.length != 3) throw fail('Це не QR-код активації');
  final compact = parts[0] == 'RZA2';
  try {
    if (!compact) {
      final head = jsonDecode(utf8.decode(fromB64u(parts[0])));
      if (head['alg'] != 'ES256' || head['typ'] != 'RZA') {
        throw fail('Це не QR-код активації');
      }
    }
    if (!verifyEs256(
      decodeSpki(issuerSpki),
      ascii.encode('${parts[0]}.${parts[1]}'),
      fromB64u(parts[2]),
    )) {
      throw fail(
        'QR-код видано не вашою системою обліку майна або його змінено',
      );
    }
    final raw = fromB64u(parts[1]);
    return jsonDecode(
          utf8.decode(compact ? ZLibCodec(raw: true).decode(raw) : raw),
        )
        as Map<String, dynamic>;
  } on ActivationException {
    rethrow;
  } catch (_) {
    throw fail('Це не QR-код активації');
  }
}
