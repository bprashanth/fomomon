import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'config/app_config.dart';

class FomomonApp extends StatefulWidget {
  const FomomonApp({super.key});

  @override
  State<FomomonApp> createState() => _FomomonAppState();
}

class _FomomonAppState extends State<FomomonApp> {
  Widget? _initialWidget;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStoredSession();
  }

  /// On app start, check for persisted session.
  /// If token exists, user can work offline using cached sites/images.
  Future<void> _checkStoredSession() async {
    try {
      final userInfo = await AuthService.instance.restoreSessionOffline();
      if (userInfo != null) {
        // restoreSessionOffline() guarantees both 'username' and 'org' are non-null if it returns non-null
        final org = userInfo['org']!;
        final username = userInfo['username']!;

        // App configuration is usually done in login screen.
        AppConfig.configure(org);

        // Get email and name from organization data
        // Note: email/org are NOT used to load sessions (getUserId() only uses name).
        // They're just passed to HomeScreen for display/other purposes.
        final orgData = AppConfig.organizationData[org];
        final String email;
        final String name;
        if (orgData == null) {
          // Org exists in storage but not in compiled app - this is a programming error
          // Use stored username as fallback for name, empty email
          print(
            'app: Warning: Org "$org" not found in organizationData, using stored username',
          );
          email = '';
          name = username;
        } else {
          // Normal case: org exists in organizationData
          email = orgData['email'] ?? '';
          // Use org's name if available, otherwise fall back to stored username
          name = orgData['name'] ?? username;
        }

        setState(() {
          _initialWidget = HomeScreen(name: name, email: email, org: org);
          _isLoading = false;
        });
      } else {
        setState(() {
          _initialWidget = const LoginScreen();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('app: Error checking stored session: $e');
      setState(() {
        _initialWidget = const LoginScreen();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        title: 'Fomomon',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'Fomomon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _initialWidget ?? const LoginScreen(),
    );
  }
}
