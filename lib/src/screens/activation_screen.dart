import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../activation.dart';
import '../activation_service.dart';
import '../device_code.dart';
import 'qr_scan_screen.dart';

String _date(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year}';
}

/// «Застосунок не активовано» з кодом телефона або картка чинного доступу.
class ActivationScreen extends StatefulWidget {
  final ActivationService service;

  const ActivationScreen({super.key, required this.service});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  late final Future<String> _code = widget.service.deviceCode();
  String? _error;

  Future<void> _apply(String? token) async {
    if (token == null) return;
    try {
      await widget.service.activate(token);
      setState(() => _error = null);
    } on ActivationException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _scan() async => _apply(
    await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen())),
  );

  Future<void> _openFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    await _apply(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Активація застосунку')),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.service.activation case final a?)
              _ActivationCard(service: widget.service, activation: a)
            else
              _NotActivated(code: _code),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Сканувати QR-код'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Відкрити файл активації'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotActivated extends StatelessWidget {
  final Future<String> code;

  const _NotActivated({required this.code});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Застосунок не активовано', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Передайте код телефона посадовій особі, що веде облік майна. '
          'Вона видасть QR-код активації (або файл), який відкривається тут.',
        ),
        const SizedBox(height: 16),
        FutureBuilder(
          future: code,
          builder: (context, snap) => SelectableText(
            snap.hasData ? formatDeviceCode(snap.data!) : '…',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivationCard extends StatelessWidget {
  final ActivationService service;
  final Activation activation;

  const _ActivationCard({required this.service, required this.activation});

  @override
  Widget build(BuildContext context) {
    final a = activation;
    Widget row(String label, String value) =>
        ListTile(dense: true, title: Text(label), subtitle: Text(value));
    return Card(
      child: Column(
        children: [
          if (service.isLocked) const ActivationLockedBanner(),
          row('Особа', a.personName),
          if (a.position.isNotEmpty) row('Посада', a.position),
          row('Підрозділ', a.departmentName),
          if (a.self case final me?) row('Номер у списку', '${me.id}'),
          if (a.staff.isNotEmpty)
            row('Особовий склад у списку', '${a.staff.length}'),
          row('Дозвіл діє до', _date(a.expiresAt)),
          row('Код телефона', formatDeviceCode(a.deviceCode)),
          SwitchListTile(
            title: const Text('Відбиток або PIN на знімок'),
            value: service.askAuth,
            onChanged: service.setAskAuth,
          ),
        ],
      ),
    );
  }
}

/// Показується, коли доступ закінчився.
class ActivationLockedBanner extends StatelessWidget {
  const ActivationLockedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(
        'Дозвіл закінчився: місяць можна переглядати й зберігати знімок, '
        'вносити зміни не можна (крім напрацювання). Потрібен новий QR-код '
        'від посадової особи, що веде облік майна.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
