import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _signInWithPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        if (response.user != null) {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          // Background Aesthetic Glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.05),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Premium Logo HUD
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Image.asset('assets/logo.png', width: 80, height: 80),
                      ),
                    ),
                    const SizedBox(height: 48),
                    const Text(
                      'SHOONYA',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SECURE ACCESS TERMINAL',
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 64),
                    // Glassmorphism Inputs
                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'CORPORATE EMAIL',
                        labelStyle: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
                        prefixIcon: const Icon(Icons.mail_outline, color: Color(0xFF10B981), size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.02),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Color(0xFF10B981)),
                        ),
                      ),
                      validator: (value) => 
                          value == null || !value.contains('@') ? 'Invalid access email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'ACCESS TOKEN',
                        labelStyle: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF10B981), size: 18),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.02),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Color(0xFF10B981)),
                        ),
                      ),
                      validator: (value) => 
                          value == null || value.isEmpty ? 'Token required' : null,
                    ),
                    const SizedBox(height: 48),
                    _isLoading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                        : Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _signInWithPassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'AUTHORIZE SESSION',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                            ),
                          ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("NEED ACCESS?", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => context.go('/signup'),
                          child: const Text('REQUEST ENTRY', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
