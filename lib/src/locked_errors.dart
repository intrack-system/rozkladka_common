import 'dart:ui';

import 'package:flutter/material.dart';

import 'activation.dart';
import 'activation_service.dart';

/// Ключ `ScaffoldMessenger` застосунку — для повідомлення про заблоковане
/// внесення з будь-якого екрана.
final activationMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Відмова шару бази після строку дії ([ActivationException]) не губиться:
/// показується повідомленням, хоч би з якої кнопки прийшла. Решта помилок
/// іде далі, як і раніше.
void showActivationErrors() {
  final previous = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    // Застосунок може замкнути базу на рівні SQLite (`PRAGMA query_only`):
    // тоді відмова приходить як помилка запису в базу лише для читання.
    final readOnly =
        (ActivationService.current?.isLocked ?? false) &&
        error.toString().contains('readonly');
    if (error is ActivationException || readOnly) {
      activationMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(lockedMessage)),
      );
      return true;
    }
    return previous?.call(error, stack) ?? false;
  };
}
