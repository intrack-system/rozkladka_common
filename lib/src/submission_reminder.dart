import 'package:flutter/material.dart';

/// Строки подання бази для обліку майна: до 1 квітня, 1 липня, 1 жовтня, за
/// IV квартал — до 20 грудня.
DateTime nextSubmissionDeadline(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (final d in [
    DateTime(now.year, 4, 1),
    DateTime(now.year, 7, 1),
    DateTime(now.year, 10, 1),
    DateTime(now.year, 12, 20),
  ]) {
    if (!d.isBefore(today)) return d;
  }
  return DateTime(now.year + 1, 4, 1);
}

/// За скільки днів до строку з'являється нагадування.
const submissionReminderDays = 7;

/// Нагадування, якщо до строку подання тиждень або менше; інакше null.
String? submissionReminder(DateTime now) {
  final d = nextSubmissionDeadline(now);
  final today = DateTime(now.year, now.month, now.day);
  if (d.difference(today).inDays > submissionReminderDays) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Подати знімок бази для обліку майна до ${two(d.day)}.${two(d.month)}.${d.year}';
}

/// Смуга нагадування на головній; нічого, якщо строк ще далеко.
class SubmissionReminderBanner extends StatelessWidget {
  final DateTime? now;

  const SubmissionReminderBanner({super.key, this.now});

  @override
  Widget build(BuildContext context) {
    final text = submissionReminder(now ?? DateTime.now());
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer)),
    );
  }
}
