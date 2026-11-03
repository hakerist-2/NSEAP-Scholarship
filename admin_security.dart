import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import 'data/admin_repository.dart';
import 'models/admin_models.dart';
import 'widgets/admin_widgets.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9_.]{4,30}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _uppercasePattern = RegExp(r'[A-Z]');
final _lowercasePattern = RegExp(r'[a-z]');
final _numberPattern = RegExp(r'[0-9]');
final _specialPattern = RegExp(r'[^A-Za-z0-9]');

/// Requires an administrator to set a new password before continuing.
class AdminPasswordChangePage extends StatelessWidget {
  const AdminPasswordChangePage({
    required this.repository,
    required this.onCompleted,
    this.recovery = false,
    super.key,
  });

  final AdminRepository repository;
  final VoidCallback onCompleted;
  final bool recovery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NseapColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.security_update_good_outlined,
                        size: 48,
                        color: NseapColors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        recovery ? 'Create New Password' : 'Change Password',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: NseapColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recovery
                            ? 'Set a secure password to recover the administrator account.'
                            : 'Your password must be updated before accessing the dashboard.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NseapColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      _PasswordForm(
                        repository: repository,
                        recovery: recovery,
                        submitLabel: 'Change Password',
                        onCompleted: onCompleted,
                      ),
                    ],
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

/// Prompts for a new username and verifies the administrator's password.
Future<AdminProfile?> showAdminUsernameDialog(
  BuildContext context, {
  required AdminRepository repository,
  required AdminProfile profile,
}) => showDialog<AdminProfile>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _UsernameDialog(repository: repository, profile: profile),
);

/// Prompts for a new email address and verifies the administrator's password.
Future<AdminProfile?> showAdminEmailDialog(
  BuildContext context, {
  required AdminRepository repository,
  required AdminProfile profile,
}) => showDialog<AdminProfile>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _EmailDialog(repository: repository, profile: profile),
);

/// Prompts the signed-in administrator to replace their password.
Future<bool> showAdminPasswordDialog(
  BuildContext context, {
  required AdminRepository repository,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Password'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: _PasswordForm(
              repository: repository,
              submitLabel: 'Update Password',
              onCompleted: () => Navigator.pop(dialogContext, true),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ) ??
    false;

class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.repository, required this.profile});

  final AdminRepository repository;
  final AdminProfile profile;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.profile.username);
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.changeUsername(
        newUsername: _username.text,
        currentPassword: _password.text,
      );
      if (mounted) Navigator.pop(context, profile);
    } catch (error) {
      if (mounted) setState(() => _error = readableAdminError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Username'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Current username: ${widget.profile.username}'),
              const SizedBox(height: 18),
              TextFormField(
                controller: _username,
                enabled: !_submitting,
                autofillHints: const [AutofillHints.newUsername],
                decoration: const InputDecoration(labelText: 'New Username'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter a username.';
                  if (!_usernamePattern.hasMatch(text)) {
                    return 'Use 4-30 letters, numbers, underscores, or periods.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                enabled: !_submitting,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value?.isEmpty ?? true)
                    ? 'Enter your current password.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Updating...' : 'Update Username'),
        ),
      ],
    );
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog({required this.repository, required this.profile});

  final AdminRepository repository;
  final AdminProfile profile;

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.changeEmail(
        newEmail: _email.text,
        currentPassword: _password.text,
      );
      if (mounted) Navigator.pop(context, profile);
    } catch (error) {
      if (mounted) setState(() => _error = readableAdminError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Email Address'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Current email: ${widget.profile.email}'),
              const SizedBox(height: 18),
              TextFormField(
                controller: _email,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'New Email'),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!_emailPattern.hasMatch(email)) {
                    return 'Enter a valid email address.';
                  }
                  if (email.toLowerCase() ==
                      widget.profile.email.toLowerCase()) {
                    return 'Enter a different email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                enabled: !_submitting,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value?.isEmpty ?? true)
                    ? 'Enter your current password.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Updating...' : 'Update Email'),
        ),
      ],
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({
    required this.repository,
    required this.submitLabel,
    required this.onCompleted,
    this.recovery = false,
  });

  final AdminRepository repository;
  final String submitLabel;
  final VoidCallback onCompleted;
  final bool recovery;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Use at least 8 characters.';
    if (!_uppercasePattern.hasMatch(password) ||
        !_lowercasePattern.hasMatch(password) ||
        !_numberPattern.hasMatch(password) ||
        !_specialPattern.hasMatch(password)) {
      return 'Include uppercase, lowercase, number, and special characters.';
    }
    if (!widget.recovery && password == _current.text) {
      return 'The new password must differ from the current password.';
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
      if (widget.recovery) {
        await widget.repository.completeRecoveredPassword(_next.text);
      } else {
        await widget.repository.changePassword(
          currentPassword: _current.text,
          newPassword: _next.text,
        );
      }
      widget.onCompleted();
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
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_submitting,
    obscureText: obscure,
    autofillHints: const [AutofillHints.password],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.recovery) ...[
            _passwordField(
              controller: _current,
              label: 'Current Password',
              obscure: _obscureCurrent,
              toggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (value) => (value?.isEmpty ?? true)
                  ? 'Enter your current password.'
                  : null,
            ),
            const SizedBox(height: 14),
          ],
          _passwordField(
            controller: _next,
            label: 'New Password',
            obscure: _obscureNext,
            toggle: () => setState(() => _obscureNext = !_obscureNext),
            validator: _validateNewPassword,
          ),
          const SizedBox(height: 14),
          _passwordField(
            controller: _confirm,
            label: 'Confirm New Password',
            obscure: _obscureConfirm,
            toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: (value) =>
                value != _next.text ? 'The new passwords do not match.' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Updating...' : widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

