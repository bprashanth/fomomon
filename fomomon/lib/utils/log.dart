import 'package:flutter/foundation.dart';

/// Drop-in replacement for print() that is completely eliminated
/// from release builds. kDebugMode is a compile-time constant.
// ignore: avoid_print
void dLog(String message) {
  if (kDebugMode) print(message);
}
