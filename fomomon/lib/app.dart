import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';

class FomomonApp extends StatelessWidget {
  const FomomonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fomomon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const Placeholder(),
      },
    );
  }
}
