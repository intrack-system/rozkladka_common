import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Камера до першого розпізнаного QR-коду; повертає його текст.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  var _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-код активації')),
      body: MobileScanner(
        onDetect: (capture) {
          final value = capture.barcodes
              .map((b) => b.rawValue)
              .whereType<String>()
              .firstOrNull;
          if (value == null || _done) return;
          _done = true;
          Navigator.of(context).pop(value);
        },
      ),
    );
  }
}
