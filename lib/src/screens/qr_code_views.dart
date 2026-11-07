import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart' as qr;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../transfer.dart';

const _alnum = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

/// QR-код найменшої версії: буквено-цифровий режим, якщо текст його
/// дозволяє (коди передачі `RZ2:`), інакше байтовий.
QrCode qrCodeOf(String data) {
  final alnum = data.split('').every(_alnum.contains);
  for (var v = 1; v <= 40; v++) {
    final code = QrCode(v, QrErrorCorrectLevel.L);
    if (alnum) {
      code.addAlphaNumeric(data);
    } else {
      code.addData(data);
    }
    try {
      qr.QrImage(code);
      return code;
    } on qr.InputTooLongException {
      continue;
    }
  }
  throw const FormatException('Завеликий для QR-коду');
}

/// Надсилає QR-коди зображеннями PNG (пошта, WhatsApp): по файлу на код,
/// `<назва>_1.png`, `<назва>_2.png`… Біла рамка — щоб камера й аналіз фото
/// знаходили код.
Future<void> shareQrCodes(
  List<String> codes,
  String name, {
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (var i = 0; i < codes.length; i++) {
    final painter = QrPainter.withQr(qr: qrCodeOf(codes[i]), gapless: true);
    const size = 1000.0, border = 80.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, size + 2 * border, size + 2 * border),
        Paint()..color = Colors.white,
      )
      ..translate(border, border);
    painter.paint(canvas, const Size.square(size));
    final image = await recorder.endRecording().toImage(
      (size + 2 * border).toInt(),
      (size + 2 * border).toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final suffix = codes.length > 1 ? '_${i + 1}' : '';
    final file = File('${dir.path}/$name$suffix.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    files.add(XFile(file.path, mimeType: 'image/png'));
  }
  await SharePlus.instance.share(ShareParams(files: files, text: text));
}

/// QR-код або серія, що змінюється сама: приймач збирає коди в будь-якому
/// порядку.
class QrSeriesView extends StatefulWidget {
  final List<String> codes;

  const QrSeriesView({super.key, required this.codes});

  @override
  State<QrSeriesView> createState() => _QrSeriesViewState();
}

class _QrSeriesViewState extends State<QrSeriesView> {
  Timer? _timer;
  var _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.codes.length > 1) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => setState(() => _index = (_index + 1) % widget.codes.length),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ColoredBox(
          color: Colors.white,
          child: QrImageView.withQr(
            qr: qrCodeOf(widget.codes[_index % widget.codes.length]),
            // Код версії 40 має 177 клітинок: на всю ширину екрана, до 480.
            size: (MediaQuery.sizeOf(context).width - 32).clamp(200, 480),
          ),
        ),
        if (widget.codes.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Код ${_index + 1} з ${widget.codes.length}'),
          ),
      ],
    );
  }
}

/// Камера: збирає серію QR-кодів і повертає дані; показує, скільки зібрано.
class QrSeriesScanScreen extends StatefulWidget {
  final String title;

  /// Приймати й одиночний код поза серією (повертається його текст у UTF-8).
  final bool acceptSingle;

  const QrSeriesScanScreen({
    super.key,
    required this.title,
    this.acceptSingle = false,
  });

  @override
  State<QrSeriesScanScreen> createState() => _QrSeriesScanScreenState();
}

class _QrSeriesScanScreenState extends State<QrSeriesScanScreen> {
  final _controller = MobileScannerController();
  final _assembler = QrAssembler();
  var _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(BarcodeCapture? capture) {
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final text = b.rawValue;
      if (text == null || _done) continue;
      final data =
          _assembler.add(text) ??
          (widget.acceptSingle && !text.startsWith('RZQ1.')
              ? utf8.encode(text)
              : null);
      if (data != null) {
        _done = true;
        Navigator.of(context).pop(data);
        return;
      }
    }
    if (mounted) setState(() {});
  }

  /// Коди, надіслані на цей телефон зображеннями: можна обрати всі разом.
  Future<void> _fromImages() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    for (final f in picked?.files ?? const <PlatformFile>[]) {
      if (f.path == null || _done) continue;
      _add(await _controller.analyzeImage(f.path!));
    }
    if (!_done && mounted && (picked?.files.isNotEmpty ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _assembler.total == 0
                ? 'На зображеннях не знайдено потрібного QR-коду'
                : 'Зібрано ${_assembler.received} з ${_assembler.total} — '
                      'додайте решту',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'З фото чи зображень',
            onPressed: _fromImages,
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
            child: Text(
              _assembler.total == 0
                  ? 'Наведіть камеру на QR-код'
                  : 'Зібрано ${_assembler.received} з ${_assembler.total}',
            ),
          ),
        ],
      ),
    );
  }
}
