import 'package:flutter/material.dart';
import 'app.dart';

void main() async {
  // Uncomment for test mode
  // AppConfig.isTestMode = true;
  // AppConfig.setLocalRoot("file:///storage/emulated/0/Download/fomomon_test/");
  // AppConfig.mockLat = 12.9746;
  // AppConfig.mockLng = 77.5937;

  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FomomonApp());
}
