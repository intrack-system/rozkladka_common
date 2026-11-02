import 'package:flutter/material.dart';

import '../activation_service.dart';

/// Повне блокування через місяць після кінця дозволу: лише зашифрований
/// знімок і новий QR-код.
class ActivationBlockedScreen extends StatelessWidget {
  final Future<void> Function(BuildContext context) onSnapshot;
  final VoidCallback onActivate;

  const ActivationBlockedScreen({
    super.key,
    required this.onSnapshot,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Застосунок заблоковано')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(blockedMessage),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => onSnapshot(context),
            icon: const Icon(Icons.ios_share),
            label: const Text('Зберегти зашифрований знімок'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onActivate,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Новий QR-код'),
          ),
        ],
      ),
    );
  }
}
