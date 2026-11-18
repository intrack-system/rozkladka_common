import 'package:flutter_test/flutter_test.dart';
import 'package:rozkladka_common/rozkladka_common.dart';

void main() {
  test('техніка зв\'язку — лише опалюваний склад', () {
    final c = StorageCategory.of('comms');
    expect(c.fits(StorageClass.light), isTrue);
    expect(c.fits(StorageClass.medium), isFalse);
    expect(c.fits(StorageClass.veryHard), isFalse);
    expect(c.fits(null), isTrue);
  });

  test('автомобілі — жорсткий чи дуже жорсткий', () {
    final c = StorageCategory.vehicles;
    expect(c.fits(StorageClass.light), isFalse);
    expect(c.fits(StorageClass.hard), isTrue);
    expect(c.fits(StorageClass.veryHard), isTrue);
  });

  test('невідома категорія — інше майно, будь-де', () {
    expect(StorageCategory.of(null), StorageCategory.other);
    expect(StorageCategory.of('xyz').fits(StorageClass.veryHard), isTrue);
    expect(StorageCategory.other.allowedText, 'будь-який склад');
  });

  test('рядок таблички: категорія — десята колонка, у старих її немає', () {
    final old = ReceiptItem.fromRow([
      'u',
      '1',
      '',
      'Р',
      'шт.',
      1,
      null,
      null,
      '',
    ]);
    expect(old.storageCategory, isNull);
    final row = ReceiptItem.fromRow([
      'u',
      '1',
      '',
      'Р',
      'шт.',
      1,
      null,
      null,
      '',
      'comms',
    ]);
    expect(row.storageCategory, 'comms');
  });
}
