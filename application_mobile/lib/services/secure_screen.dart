import 'package:flutter/services.dart';

class SecureScreen {
  static const _ch = MethodChannel('optiPark/secure_screen');

  static Future<void> enable() async {
    try {
      await _ch.invokeMethod('enable');
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await _ch.invokeMethod('disable');
    } catch (_) {}
  }
}
