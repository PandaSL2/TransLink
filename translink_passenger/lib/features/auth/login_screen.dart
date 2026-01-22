import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_localizations.dart';
import '../../core/utils/error_handler.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.translate('enter_email_pass'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      if (_isSignUp) {
        final name = _nameController.text.trim();
        if (name.isEmpty) {
          setState(() => _error = l10n.translate('enter_username'));
          return;
        }
        await Supabase.instance.client.auth.signUp(
          email: email, password: password, data: {'full_name': name},
        );
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      }
      widget.onLoggedIn();
    } on AuthException catch (e) {
      setState(() => _error = ErrorHandler.getFriendlyMessage(e, context));
    } catch (e) {
      setState(() => _error = ErrorHandler.getFriendlyMessage(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.flutter://login-callback/',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorHandler.getFriendlyMessage(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, const Color(0xFF1D4ED8)]),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), blurRadius: 20)],
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 32),
              Text(
                _isSignUp ? 'Create Account' : 'Welcome Back',
                style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _isSignUp ? 'Join the TransLink premium network.' : 'Sign in to access your wallet and journeys.',
                style: GoogleFonts.inter(fontSize: 16, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 40),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_error!, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.error, fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 24),
              ],
              
              if (_isSignUp) ...[
                _buildField(_nameController, 'Full Name', Icons.person_outline_rounded),
                const SizedBox(height: 16),
              ],
              _buildField(_emailController, 'Email Address', Icons.alternate_email_rounded, keyboard: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _buildField(_passwordController, 'Password', Icons.lock_outline_rounded, obscure: !_showPassword, 
                suffix: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                )
              ),
              
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: _loading 
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text(_isSignUp ? 'REGISTER NOW' : 'SIGN IN', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _continueWithGoogle,
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: Text('Continue with Google', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() { _isSignUp = !_isSignUp; _error = null; }),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14),
                      children: [
                        TextSpan(text: _isSignUp ? 'Already have an account? ' : 'New to TransLink? '),
                        TextSpan(
                          text: _isSignUp ? 'Sign In' : 'Sign Up',
                          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, {bool obscure = false, Widget? suffix, TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
    );
  }
}
