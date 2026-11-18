/// Умови зберігання майна: клас складу і категорія майна. Спільний перелік —
/// облік майна вказує категорію в табличці надходження, склад за нею
/// обирає, куди майно стає.
library;

/// Клас складу за умовами зберігання.
enum StorageClass {
  light('l', 'Легкий', 'опалюване приміщення'),
  medium('m', 'Середній', 'неопалюване приміщення'),
  hard('h', 'Жорсткий', 'під навісом, охоронювана стоянка'),
  veryHard('vh', 'Дуже жорсткий', 'відкритий огороджений майданчик');

  final String code;
  final String title;
  final String place;

  const StorageClass(this.code, this.title, this.place);

  static StorageClass? of(String? code) =>
      values.where((c) => c.code == code).firstOrNull;
}

/// Категорія майна для зберігання. Перші сім — лише на опалюваному складі;
/// автомобільна техніка — на жорсткому чи дуже жорсткому; інше — будь-де.
enum StorageCategory {
  comms('comms', 'Техніка зв\'язку'),
  electro('electro', 'Технічні засоби з елементами електротехніки'),
  sensitive('sensitive', 'Електровакуумні й високочутливі прилади'),
  spares('spares', 'Запасні інструменти та приладдя до техніки зв\'язку'),
  batteries('batteries', 'Акумулятори, введені в дію (залиті й заряджені)'),
  measuring('measuring', 'Точний вимірювальний інструмент'),
  medical('medical', 'Медичне майно'),
  vehicles('vehicles', 'Автомобільна техніка'),
  other('other', 'Інше майно');

  final String code;
  final String title;

  const StorageCategory(this.code, this.title);

  /// Невідомий чи порожній код — «інше майно»: без обмежень.
  static StorageCategory of(String? code) =>
      values.where((c) => c.code == code).firstOrNull ?? other;

  /// Класи складів, де цю категорію можна зберігати.
  List<StorageClass> get allowed => switch (this) {
    vehicles => const [StorageClass.hard, StorageClass.veryHard],
    other => StorageClass.values,
    _ => const [StorageClass.light],
  };

  /// Склад без визначеного класу приймає все — клас ще не налаштовано.
  bool fits(StorageClass? warehouse) =>
      warehouse == null || allowed.contains(warehouse);

  /// «легкий (опалюване приміщення)» або перелік через «чи».
  String get allowedText => allowed.length == StorageClass.values.length
      ? 'будь-який склад'
      : allowed
            .map((c) => '${c.title.toLowerCase()} (${c.place})')
            .join(' чи ');
}
