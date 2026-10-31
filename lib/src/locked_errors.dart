import 'dart:ui';

import 'package:flutter/material.dart';

import 'activation.dart';

/// Ключ `ScaffoldMessenger` застосунку — для повідомлення про заблоковане
/// внесення з будь-якого екрана.
final activationMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Відмова шару бази після строку дії ([ActivationException]) не губиться:
/// показується повідомленням, хоч би з якої кнопки прийшла. Решта помилок
/// іде далі, як і раніше.
void showActivationErrors() {
  final previous = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is ActivationException) {
      activationMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return true;
    }
    return previous?.call(error, stack) ?? false;
  };
}
