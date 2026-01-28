import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../screens/site_prefetch_screen.dart';
import '../screens/home_screen.dart';
import '../services/auth_service.dart';
import '../models/login_error.dart';
import '../exceptions/auth_exceptions.dart';
import '../widgets/privacy_policy_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  // Login screen fields
  String? _selectedOrg;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State variables
  bool _isLoadingConfig = false;
  bool _isLoadingLogin = false;
  LoginError? _loginError;
  bool _configFetched = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Set default org and populate fields
    // This is just UX sugar to display an example to the user of what values
    // they should use in the login screen.
    _selectedOrg = 't4gc';
    _updateFieldsFromOrg();
    _fetchConfigInBackground();
  }

  // _updateFieldsFromOrg looks up the onboarded org info from the AppConfig.
  // This org data map is populated offline when a new org is on-boarded.
  // Currently it is compiled into the app, which means for every new org, we
  // need to re-compile the app.
  void _updateFieldsFromOrg() {
    // TODO(prashanth@): move this to a json file so on-boarding orgs is easy.
    if (_selectedOrg != null &&
        AppConfig.organizationData.containsKey(_selectedOrg)) {
      final orgData = AppConfig.organizationData[_selectedOrg]!;
      _nameController.text = orgData['name'] ?? '';
    }
  }

  Future<void> _fetchConfigInBackground() async {
    setState(() {
      _isLoadingConfig = true;
      _loginError = null;
    });

    // Right now we are pre-login, so we only need the location of the
    // auth_config.json. Once the user has finalized the login details
    // including org, we can set that in the AppConfig. This happens in
    // handleSubmit.
    // TODO(prashanth@): Consolidate these AppConfig initializations.
    AppConfig.configure();

    try {
      final authService = AuthService.instance;
      await authService.fetchAuthConfig();

      setState(() {
        _configFetched = true;
        _isLoadingConfig = false;
      });
    } on AuthNetworkException catch (e) {
      print('login_screen: Network error in background config fetch: $e');
      setState(() {
        _isLoadingConfig = false;
        _loginError = LoginError.networkError;
      });
    } on AuthConfigException catch (e) {
      print('login_screen: Config error in background fetch: $e');
      setState(() {
        _isLoadingConfig = false;
        _loginError = LoginError.configFetchFailed;
      });
    } catch (e) {
      print('login_screen: Unexpected error in background config fetch: $e');
      setState(() {
        _isLoadingConfig = false;
        _loginError = LoginError.configFetchFailed;
      });
    }
  }

  void _handleSubmit() async {
    print('login_screen: Handling submit');
    if (!_formKey.currentState!.validate()) return;

    // If config fetch failed in background, retry now
    if (!_configFetched) {
      await _fetchConfigInBackground();
      if (!_configFetched) {
        return; // Still failed, error is already set
      }
    }

    setState(() {
      _isLoadingLogin = true;
      _loginError = null;
    });

    // AppConfig constants are centralized (bucket/region); only org varies per user.
    AppConfig.configure(_selectedOrg!.toLowerCase());

    try {
      final name = _nameController.text.trim().toLowerCase();
      final password = _passwordController.text.trim();
      final org = _selectedOrg!.toLowerCase();

      // Email is just informational at this point. Login is based on user_id.
      final email = AppConfig.organizationData[org]?['email'] ?? '';

      if (name.isNotEmpty &&
          password.isNotEmpty &&
          email.isNotEmpty &&
          org.isNotEmpty) {
        final authService = AuthService.instance;
        print('login_screen: Logging in user: $email');

        await authService.login(name, password);
        final token = await authService.getValidToken();
        if (token == null) {
          setState(() {
            _loginError = LoginError.invalidCredentials;
            _isLoadingLogin = false;
          });
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (_) => SitePrefetchScreen(name: name, email: email, org: org),
          ),
        );
      }
    } on AuthCredentialsException catch (e) {
      print('login_screen: Invalid credentials: $e');
      setState(() {
        _loginError = LoginError.invalidCredentials;
        _isLoadingLogin = false;
      });
    } on AuthNetworkException catch (e) {
      print('login_screen: Network error during login: $e');
      setState(() {
        _loginError = LoginError.networkError;
        _isLoadingLogin = false;
      });
    } on AuthConfigException catch (e) {
      print('login_screen: Config error during login: $e');
      setState(() {
        _loginError = LoginError.configFetchFailed;
        _isLoadingLogin = false;
      });
    } on AuthServiceException catch (e) {
      print('login_screen: Service error during login: $e');
      setState(() {
        _loginError = LoginError.unknown;
        _isLoadingLogin = false;
      });
    } catch (e) {
      print('login_screen: Unexpected error during login: $e');
      setState(() {
        _loginError = LoginError.unknown;
        _isLoadingLogin = false;
      });
    }
  }

  void _handleGuestLogin() async {
    print('login_screen: Handling guest login');

    setState(() {
      _isLoadingLogin = true;
      _loginError = null;
    });

    // Configure guest mode
    AppConfig.configureGuestMode();

    // Navigate directly to home screen, skipping site prefetch
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => HomeScreen(
              name: AppConfig.guestUser,
              email: AppConfig.guestEmail,
              org: AppConfig.guestOrg,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login.png',
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.6),
            colorBlendMode: BlendMode.darken,
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 100), // pushes it down
                        const Text(
                          'Fomo',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildOrgDropdown(),
                        const SizedBox(height: 16),
                        _buildTextInput('Name', _nameController),
                        const SizedBox(height: 16),
                        _buildTextInput(
                          'Password',
                          _passwordController,
                          isPassword: true,
                        ),
                        const SizedBox(height: 24),

                        // Error message
                        if (_loginError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              _loginError!.message,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],

                        // Login button
                        ElevatedButton(
                          onPressed:
                              (_isLoadingLogin || _isLoadingConfig)
                                  ? null
                                  : _handleSubmit,
                          child:
                              _isLoadingLogin
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text('Continue'),
                        ),

                        const SizedBox(height: 16),

                        // Guest login button
                        OutlinedButton(
                          onPressed:
                              (_isLoadingLogin || _isLoadingConfig)
                                  ? null
                                  : _handleGuestLogin,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          child: const Text('Continue as Guest'),
                        ),

                        // Config loading indicator
                        if (_isLoadingConfig) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Loading authentication services..',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],

                        // Privacy Policy Link
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () => showPrivacyPolicy(context),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),

                        const SizedBox(height: 100), // pushes bottom space
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedOrg,
      decoration: const InputDecoration(
        labelText: 'Organization',
        labelStyle: TextStyle(color: Colors.white),
      ),
      dropdownColor: Colors.grey[900],
      style: const TextStyle(color: Colors.white),
      items:
          AppConfig.organizationData.keys.map((org) {
            return DropdownMenuItem(value: org, child: Text(org));
          }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedOrg = newValue;
            _updateFieldsFromOrg();
          });
        }
      },
      validator: (value) => value == null ? 'Select an organization' : null,
    );
  }

  Widget _buildTextInput(
    String label,
    TextEditingController controller, {
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        suffixIcon:
            isPassword
                ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                )
                : null,
      ),
      style: const TextStyle(color: Colors.white),
      obscureText: isPassword && _obscurePassword,
      validator: (val) => val!.isEmpty ? 'Enter $label' : null,
    );
  }
}
