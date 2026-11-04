import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Камера до першого розпізнаного QR-коду; повертає його текст. Код, що
/// прийшов на цей самий телефон (пошта, WhatsApp), читається з фото.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  var _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(BarcodeCapture? capture) {
    final value = capture?.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || _done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  Future<void> _fromImage() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null) return;
    final capture = await _controller.analyzeImage(path);
    if (!mounted) return;
    if (capture == null || capture.barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На зображенні не знайдено QR-коду')),
      );
      return;
    }
    _finish(capture);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-код'),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'З фото чи зображення',
            onPressed: _fromImage,
          ),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _finish),
    );
  }
}
