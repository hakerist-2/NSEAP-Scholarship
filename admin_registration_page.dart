import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import 'data/admin_repository.dart';
import 'widgets/admin_widgets.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9_.]{4,30}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _uppercasePattern = RegExp(r'[A-Z]');
final _lowercasePattern = RegExp(r'[a-z]');
final _numberPattern = RegExp(r'[0-9]');
final _specialPattern = RegExp(r'[^A-Za-z0-9]');

/// Creates the first administrator when the portal has not been configured.
class AdminRegistrationPage extends StatefulWidget {
  const AdminRegistrationPage({
    required this.repository,
    required this.onCreated,
    required this.onSignIn,
    super.key,
  });

  final AdminRepository repository;
  final VoidCallback onCreated;
  final VoidCallback onSignIn;

  @override
  State<AdminRegistrationPage> createState() => _AdminRegistrationPageState();
}

class _AdminRegistrationPageState extends State<AdminRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Use at least 8 characters.';
    if (!_uppercasePattern.hasMatch(password) ||
        !_lowercasePattern.hasMatch(password) ||
        !_numberPattern.hasMatch(password) ||
        !_specialPattern.hasMatch(password)) {
      return 'Include uppercase, lowercase, number, and special characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.createInitialAdmin(
        fullName: _fullName.text,
        username: _username.text,
        email: _email.text,
        password: _password.text,
      );
      widget.onCreated();
    } catch (error) {
      if (mounted) setState(() => _error = readableAdminError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_submitting,
    obscureText: obscure,
    autofillHints: const [AutofillHints.newPassword],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        onPressed: onToggle,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NseapColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.account_balance_outlined,
                          size: 52,
                          color: NseapColors.primary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'NSEAP',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: NseapColors.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'ADMINISTRATOR ACCOUNT SETUP',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NseapColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _fullName,
                          enabled: !_submitting,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) => (value?.trim().length ?? 0) < 2
                              ? 'Enter the administrator full name.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _username,
                          enabled: !_submitting,
                          autofillHints: const [AutofillHints.newUsername],
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            final username = value?.trim() ?? '';
                            return _usernamePattern.hasMatch(username)
                                ? null
                                : 'Use 4-30 letters, numbers, underscores, or periods.';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          enabled: !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              _emailPattern.hasMatch(value?.trim() ?? '')
                              ? null
                              : 'Enter a valid email address.',
                        ),
                        const SizedBox(height: 14),
                        _passwordField(
                          controller: _password,
                          label: 'Password',
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 14),
                        _passwordField(
                          controller: _confirmPassword,
                          label: 'Confirm Password',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                          validator: (value) => value != _password.text
                              ? 'The passwords do not match.'
                              : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1_outlined),
                          label: Text(
                            _submitting
                                ? 'Creating account...'
                                : 'Create Administrator Account',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Already have an account?'),
                            TextButton(
                              onPressed: _submitting ? null : widget.onSignIn,
                              child: const Text('Sign In'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

