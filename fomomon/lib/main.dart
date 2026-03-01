import 'package:flutter/material.dart';
import 'app.dart';
import 'services/local_image_storage.dart';

void main() async {
  // Uncomment for test mode
  // AppConfig.isTestMode = true;
  // AppConfig.setLocalRoot("file:///storage/emulated/0/Download/fomomon_test/");
  // AppConfig.mockLat = 12.9746;
  // AppConfig.mockLng = 77.5937;

  WidgetsFlutterBinding.ensureInitialized();

  // On web: opens IndexedDB and pre-loads stored image bytes into the
  // in-memory cache so readBytes() stays synchronous. No-op on native.
  await LocalImageStorage.initStorage();

  runApp(const FomomonApp());
}
