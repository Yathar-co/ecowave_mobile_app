import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    
    // Show a snackbar if it takes too long (Render cold start)
    final coldStartTimer = Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _loading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Starting server... This might take up to 60s on first load.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    });

    try {
      await context.read<AuthProvider>().login(
            _emailCtrl.text.trim(),
            _nameCtrl.text.trim(),
          );
      if (mounted) {
        final user = context.read<AuthProvider>().user;
        if (user?.email == 'admin@ecowave.com') {
          context.go('/admin');
        } else {
          context.go('/marketplace');
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        // If it's a Dio error, try to extract more specific info
        if (errorMsg.contains('connection timeout')) {
          errorMsg = 'Server is taking too long to wake up (Render Cold Start). Please wait 30s and try again.';
        } else if (errorMsg.contains('connection error')) {
          errorMsg = 'Cannot reach server. Please check your internet or VPN.';
        } else if (errorMsg.contains('401')) {
          errorMsg = 'Invalid credentials. Please check your email/name.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMsg'),
            backgroundColor: ecoError,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Technical Details'),
                    content: SingleChildScrollView(child: Text(e.toString())),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ecoDark,
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(gradient: ecoHeaderGradient),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🌊', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 8),
                      const Text(
                        'EcoWave',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text('Sign in to continue',
                          style: TextStyle(color: ecoMuted, fontSize: 14)),
                      const SizedBox(height: 36),

                      // Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: ecoSurface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: ecoBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Login',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            _EcoField(
                              controller: _nameCtrl,
                              label: 'Your Name',
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 16),
                            _EcoField(
                              controller: _emailCtrl,
                              label: 'Email Address',
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => !v!.contains('@')
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: _loading
                                      ? LinearGradient(colors: [
                                          ecoGreen.withValues(alpha: 0.5),
                                          ecoLeaf.withValues(alpha: 0.5),
                                        ])
                                      : ecoGreenGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: TextButton(
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _GoogleSignInButton(
                              isLoading: _loading,
                              onPressed: () async {
                                setState(() => _loading = true);
                                
                                // Show a snackbar if it takes too long (Render cold start)
                                final coldStartTimer = Future.delayed(const Duration(seconds: 5), () {
                                  if (mounted && _loading) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Connecting to Google and Server... Please wait.'),
                                        duration: Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                });

                                try {
                                  await context.read<AuthProvider>().loginWithGoogle();
                                  if (!context.mounted) return;
                                  if (context.read<AuthProvider>().isLoggedIn) {
                                    final user = context.read<AuthProvider>().user;
                                    if (user?.email == 'admin@ecowave.com') {
                                      context.go('/admin');
                                    } else {
                                      context.go('/marketplace');
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Google Sign-In Error: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _loading = false);
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account? ",
                              style: TextStyle(color: ecoMuted)),
                          TextButton(
                            onPressed: () => context.push('/register'),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Register',
                                style: TextStyle(
                                    color: ecoGreenLight,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Register ─────────────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    
    // Show a snackbar if it takes too long (Render cold start)
    final coldStartTimer = Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _loading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Starting server... This might take up to 60s on first load.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    });

    try {
      await context.read<AuthProvider>().login(
            _emailCtrl.text.trim(),
            _nameCtrl.text.trim(),
          );
      if (mounted) {
        final user = context.read<AuthProvider>().user;
        if (user?.email == 'admin@ecowave.com') {
          context.go('/admin');
        } else {
          context.go('/marketplace');
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        // If it's a Dio error, try to extract more specific info
        if (errorMsg.contains('connection timeout')) {
          errorMsg = 'Server is taking too long to wake up (Render Cold Start). Please wait 30s and try again.';
        } else if (errorMsg.contains('connection error')) {
          errorMsg = 'Cannot reach server. Please check your internet or VPN.';
        } else if (errorMsg.contains('401')) {
          errorMsg = 'Invalid credentials. Please check your email/name.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMsg'),
            backgroundColor: ecoError,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Technical Details'),
                    content: SingleChildScrollView(child: Text(e.toString())),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ecoDark,
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ecoLeaf.withValues(alpha: 0.25), ecoDark],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text('🌿', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 8),
                      const Text(
                        'Join EcoWave',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      ),
                      Text('Create your account',
                          style: TextStyle(color: ecoMuted, fontSize: 14)),
                      const SizedBox(height: 36),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: ecoSurface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: ecoBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Create Account',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            _EcoField(
                              controller: _nameCtrl,
                              label: 'Full Name',
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 16),
                            _EcoField(
                              controller: _emailCtrl,
                              label: 'Email Address',
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => !v!.contains('@')
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: _loading
                                      ? LinearGradient(colors: [
                                          ecoGreen.withValues(alpha: 0.5),
                                          ecoLeaf.withValues(alpha: 0.5)
                                        ])
                                      : ecoGreenGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: TextButton(
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Text('Create Account',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _GoogleSignInButton(
                              isLoading: _loading,
                              onPressed: () async {
                                setState(() => _loading = true);
                                
                                // Show a snackbar if it takes too long (Render cold start)
                                final coldStartTimer = Future.delayed(const Duration(seconds: 5), () {
                                  if (mounted && _loading) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Connecting to Google and Server... Please wait.'),
                                        duration: Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                });

                                try {
                                  await context.read<AuthProvider>().loginWithGoogle();
                                  if (!context.mounted) return;
                                  if (context.read<AuthProvider>().isLoggedIn) {
                                    final user = context.read<AuthProvider>().user;
                                    if (user?.email == 'admin@ecowave.com') {
                                      context.go('/admin');
                                    } else {
                                      context.go('/marketplace');
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Google Sign-In Error: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _loading = false);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ',
                              style: TextStyle(color: ecoMuted)),
                          TextButton(
                            onPressed: () => context.push('/login'),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Login',
                                style: TextStyle(
                                    color: ecoGreenLight,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared field widget ───────────────────────────────────────────────────────

class _EcoField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _EcoField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: ecoCard,
        labelStyle: TextStyle(color: ecoMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ecoBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ecoBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ecoGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ecoError),
        ),
      ),
    );
  }
}

// ── Google Sign In Button ───────────────────────────────────────────────────

class _GoogleSignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _GoogleSignInButton({
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: ecoBorder),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'G',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
