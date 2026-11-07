import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../activation.dart';
import '../qr_pack.dart';
import 'qr_code_views.dart';
import 'qr_scan_screen.dart';

/// Шаблон передачі майна (RZ2), однаковий в усіх застосунках: сторінка
/// кодів передавача, сканер приймача, файл замість кодів.

/// Більше кодів — застосунок радить файл.
const packFileAdviceCodes = 5;

/// Пакет файлом `.rzt` (коди рядками) — WhatsApp, пошта.
Future<void> sharePackFile(SealedPack pack, String name) async {
  final dir = await getTemporaryDirectory();
  final file = await File('${dir.path}/$name.rzt').writeAsString(pack.toFile());
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
}

/// Текст файлу (`.rzt`, `.rzi`, `.rzc`) з телефона.
Future<String?> pickPackFile() async {
  final picked = await FilePicker.platform.pickFiles(withData: true);
  final f = picked?.files.single;
  if (f == null) return null;
  final bytes = f.bytes ?? await File(f.path!).readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

/// Один код великим, на всю ширину екрана.
class PackQr extends StatelessWidget {
  final String code;

  const PackQr(this.code, {super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: QrImageView.withQr(
      qr: qrCodeOf(code),
      size: (MediaQuery.sizeOf(context).width - 48).clamp(200, 480),
    ),
  );
}

/// Сторінка кодів передавача: угорі хто, кому, скільки; далі картка на
/// кожен код із переліком того, що в ньому; знизу закріплено підставу й
/// дії. [labels] — підписи одиниць по порядку рядків пакета.
class PackSendPage extends StatefulWidget {
  final String title;
  final String from;
  final String to;
  final String basis;
  final SealedPack pack;
  final List<String> labels;

  /// Підтвердження приймача (код чи файл) — застосунок перевіряє й
  /// завершує передачу; повертає текст помилки або null.
  final Future<String?> Function(String confirmation) onConfirmation;
  final VoidCallback? onCancel;

  const PackSendPage({
    super.key,
    required this.title,
    required this.from,
    required this.to,
    required this.basis,
    required this.pack,
    required this.labels,
    required this.onConfirmation,
    this.onCancel,
  });

  @override
  State<PackSendPage> createState() => _PackSendPageState();
}

class _PackSendPageState extends State<PackSendPage> {
  final _open = <int>{};

  Future<void> _confirm(String? text) async {
    if (text == null) return;
    final error = await widget.onConfirmation(text.trim());
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _scan() async => _confirm(
    await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    ),
  );

  Widget _card(int i, int start) {
    final codes = widget.pack.codes;
    final count = widget.pack.rowsPerCode[i];
    final items = widget.labels.sublist(start, start + count);
    final shown = _open.contains(i) ? items : items.take(3).toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Код ${i + 1} з ${codes.length} · $count',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Center(child: PackQr(codes[i])),
            const SizedBox(height: 8),
            for (final (k, l) in shown.indexed) Text('${start + k + 1}. $l'),
            if (items.length > 3)
              TextButton(
                onPressed: () => setState(
                  () => _open.contains(i) ? _open.remove(i) : _open.add(i),
                ),
                child: Text(
                  _open.contains(i) ? 'Згорнути' : 'Ще ${items.length - 3}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pack;
    final cards = <Widget>[];
    var start = 0;
    for (var i = 0; i < p.codes.length; i++) {
      cards.add(_card(i, start));
      start += p.rowsPerCode[i];
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Від: ${widget.from}'),
                  Text('Кому: ${widget.to}'),
                  Text(
                    '${widget.labels.length} · кодів: ${p.codes.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Text('Приймач сканує коди в будь-якому порядку.'),
                  if (p.codes.length > packFileAdviceCodes)
                    Text(
                      'Кодів багато — зручніше надіслати файлом.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          ...cards,
          if (widget.onCancel != null)
            Center(
              child: TextButton(
                onPressed: widget.onCancel,
                child: const Text('Скасувати передачу'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Підстава: ${widget.basis}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => sharePackFile(p, 'Передача_майна'),
                        child: const Text('Надіслати файлом'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _scan,
                        child: const Text('Підтвердження'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () async => _confirm(await pickPackFile()),
                  child: const Text('Відкрити файл підтвердження'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Приймач: камера, фото чи файл — збирає коди пакета, показує, скільки
/// зібрано, і повертає пакет.
class PackScanScreen extends StatefulWidget {
  final PackAssembler assembler;

  const PackScanScreen({super.key, required this.assembler});

  @override
  State<PackScanScreen> createState() => _PackScanScreenState();
}

class _PackScanScreenState extends State<PackScanScreen> {
  final _controller = MobileScannerController();
  var _done = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(OpenedPack? pack) {
    if (pack == null || _done) return;
    _done = true;
    Navigator.of(context).pop(pack);
  }

  void _add(BarcodeCapture? capture) {
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final text = b.rawValue;
      if (text == null || _done) continue;
      try {
        _finish(widget.assembler.add(text));
        _error = null;
      } on ActivationException catch (e) {
        _error = e.message;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _fromImages() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    for (final f in picked?.files ?? const <PlatformFile>[]) {
      if (f.path != null && !_done) {
        _add(await _controller.analyzeImage(f.path!));
      }
    }
  }

  Future<void> _fromFile() async {
    final text = await pickPackFile();
    if (text == null) return;
    try {
      _finish(widget.assembler.addFile(text));
    } on ActivationException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assembler;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пакет передачі'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'З фото чи зображень',
            onPressed: _fromImages,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Файл пакета',
            onPressed: _fromFile,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(controller: _controller, onDetect: _add),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  a.total == 0
                      ? 'Наведіть камеру на код передавача'
                      : 'Зібрано ${a.received} з ${a.total}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
