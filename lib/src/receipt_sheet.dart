import 'dart:convert';
import 'dart:io';

import 'activation.dart';
import 'p256.dart';

const _prefix = 'RZI1';

/// Рядок майна з таблички надходження.
class ReceiptItem {
  final String uid;
  final String inventoryNumber;
  final String serialNumber;
  final String name;
  final String unit;
  final double quantity;
  final double? cost;
  final int? manufactureYear;
  final String formularNumber;

  const ReceiptItem({
    required this.uid,
    required this.inventoryNumber,
    required this.serialNumber,
    required this.name,
    required this.unit,
    required this.quantity,
    this.cost,
    this.manufactureYear,
    required this.formularNumber,
  });

  /// Колонки за місцем; нові дописуються в кінець, тож зайві не заважають.
  factory ReceiptItem.fromRow(List<dynamic> r) => ReceiptItem(
    uid: r[0] as String,
    inventoryNumber: r[1] as String,
    serialNumber: r[2] as String,
    name: r[3] as String,
    unit: r[4] as String,
    quantity: (r[5] as num).toDouble(),
    cost: (r[6] as num?)?.toDouble(),
    manufactureYear: (r[7] as num?)?.toInt(),
    formularNumber: r[8] as String,
  );
}

/// Табличка надходження, надрукована обліком майна: майно з'являється на
/// складі без повторного внесення. Код підписаний, але не зашифрований.
class ReceiptSheet {
  final int departmentId;
  final String departmentName;
  final String? documentNumber;
  final String? documentDate;

  /// Вид документа-підстави: `transfer_act` — акт приймання-передачі
  /// основних засобів, `invoice` — видаткова накладна, `works_act` — акт
  /// приймання виконаних робіт; null — не вказано (старі таблички).
  final String? documentKind;
  final DateTime issuedAt;
  final List<ReceiptItem> items;

  const ReceiptSheet({
    required this.departmentId,
    required this.departmentName,
    this.documentNumber,
    this.documentDate,
    this.documentKind,
    required this.issuedAt,
    required this.items,
  });

  /// Кидає [ActivationException], якщо код чужий, змінений чи пошкоджений.
  factory ReceiptSheet.decode(String token, List<int> issuerSpki) {
    const bad = ActivationException('Це не QR-код таблички надходження');
    final parts = token.trim().split('.');
    if (parts.length != 3 || parts[0] != _prefix) throw bad;
    try {
      if (!verifyEs256(
        decodeSpki(issuerSpki),
        ascii.encode('$_prefix.${parts[1]}'),
        fromB64u(parts[2]),
      )) {
        throw const ActivationException(
          'Табличку видано не вашою системою обліку майна або її змінено',
        );
      }
      final m =
          jsonDecode(
                utf8.decode(ZLibCodec(raw: true).decode(fromB64u(parts[1]))),
              )
              as Map<String, dynamic>;
      if (m['v'] != 1) {
        throw const ActivationException('Невідома версія таблички');
      }
      final dept = m['dept'] as Map<String, dynamic>;
      final doc = m['doc'] as Map<String, dynamic>;
      return ReceiptSheet(
        departmentId: dept['id'] as int,
        departmentName: dept['name'] as String,
        documentNumber: doc['n'] as String?,
        documentDate: doc['d'] as String?,
        documentKind: doc['k'] as String?,
        issuedAt: DateTime.parse(m['at'] as String),
        items: [
          for (final r in m['it'] as List) ReceiptItem.fromRow(r as List),
        ],
      );
    } on ActivationException {
      rethrow;
    } catch (_) {
      throw bad;
    }
  }
}
