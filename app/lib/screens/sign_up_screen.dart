import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'check_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _password.text,
        data: {'display_name': _name.text.trim()},
      );
      if (!mounted) return;

      // With email confirmation on, Supabase returns a user with no identities
      // (instead of an error) when the email is already registered.
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
        setState(() => _error =
            'An account with this email already exists. Go back and sign in.');
      } else if (res.session != null) {
        // Confirmation disabled: signed in immediately. Drop back to the root,
        // which swaps to the home screen on the auth state change.
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => CheckEmailScreen(email: email)),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !_emailPattern.hasMatch(v.trim()))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: !_showPassword,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) =>
                      v != _password.text ? 'Passwords do not match' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating account...' : 'Create account'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
