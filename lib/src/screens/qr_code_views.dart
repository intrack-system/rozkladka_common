import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../transfer.dart';

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
          child: QrImageView(
            data: widget.codes[_index % widget.codes.length],
            size: 300,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
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

  const QrSeriesScanScreen({super.key, required this.title});

  @override
  State<QrSeriesScanScreen> createState() => _QrSeriesScanScreenState();
}

class _QrSeriesScanScreenState extends State<QrSeriesScanScreen> {
  final _assembler = QrAssembler();
  var _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                for (final b in capture.barcodes) {
                  final text = b.rawValue;
                  if (text == null || _done) continue;
                  final data = _assembler.add(text);
                  if (data != null) {
                    _done = true;
                    Navigator.of(context).pop(data);
                    return;
                  }
                }
                setState(() {});
              },
            ),
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
