import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../screens/site_prefetch_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _appName = 'FOMOMON';

  // Login screen fields
  final TextEditingController _orgController = TextEditingController(
    text: "t4gc",
  );
  final TextEditingController _nameController = TextEditingController(
    text: "Prashanth",
  );
  final TextEditingController _emailController = TextEditingController(
    text: "prashanth@fomomon.com",
  );

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // Simulate user lookup and login
    // await Future.delayed(const Duration(seconds: 1));

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final org = _orgController.text.trim();

    if (name.isNotEmpty || email.isNotEmpty && org.isNotEmpty) {
      AppConfig.configure(bucketName: _appName.toLowerCase(), org: org);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (_) => SitePrefetchScreen(name: name, email: email, org: org),
        ),
      );
    }
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
                        _buildTextInput('Org Code', _orgController),
                        const SizedBox(height: 16),
                        _buildTextInput('Name', _nameController),
                        const SizedBox(height: 16),
                        _buildTextInput('Email', _emailController),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _handleSubmit,
                          child: const Text('Continue'),
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

  Widget _buildTextInput(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      style: const TextStyle(color: Colors.white),
      validator: (value) => value!.isEmpty ? 'Enter $label' : null,
    );
  }
}
