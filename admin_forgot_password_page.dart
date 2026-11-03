import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/admin_repository.dart';
import 'widgets/admin_widgets.dart';

enum _ResetStep { email, otp, password }

/// OTP-based forgot password for administrators.
///
/// Flow: enter email → verify 6-digit OTP → set new password + confirm → login.
class AdminForgotPasswordPage extends StatefulWidget {
  const AdminForgotPasswordPage({
    super.key,
    this.repository,
    this.initialEmail,
  });

  final AdminRepository? repository;
  final String? initialEmail;

  @override
  State<AdminForgotPasswordPage> createState() =>
      _AdminForgotPasswordPageState();
}

class _AdminForgotPasswordPageState extends State<AdminForgotPasswordPage> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Timer? _timer;
  int _cooldown = 0;

  // Password strength live checks
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecial = false;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _startCooldown({int seconds = 60}) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  void _updatePasswordChecks(String value) {
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
      _hasLowercase = RegExp(r'[a-z]').hasMatch(value);
      _hasDigit = RegExp(r'[0-9]').hasMatch(value);
      _hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
    });
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Z]').hasMatch(v) ||
        !RegExp(r'[a-z]').hasMatch(v) ||
        !RegExp(r'[0-9]').hasMatch(v) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(v)) {
      return 'Include uppercase, lowercase, number, and special character.';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await _repository.requestAdminRecoveryOtp(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _step = _ResetStep.otp;
        _otpController.clear();
      });
      _startCooldown(seconds: 60);
      showAdminMessage(
        context,
        'A 6-digit verification code was sent to ${_emailController.text.trim()}.',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_cooldown > 0 || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await _repository.requestAdminRecoveryOtp(_emailController.text.trim());
      if (!mounted) return;
      _otpController.clear();
      _startCooldown(seconds: 60);
      showAdminMessage(context, 'A new verification code was sent.');
    } on AuthException catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _otpController.text.trim();
    if (code.length != 6) {
      showAdminMessage(
        context,
        'Enter the 6-digit verification code.',
        error: true,
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _repository.verifyAdminRecoveryOtp(
        email: _emailController.text.trim(),
        token: code,
      );
      if (!mounted) return;
      setState(() => _step = _ResetStep.password);
      showAdminMessage(context, 'Code verified. Create your new password.');
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      String friendly = readableAdminError(e);
      if (msg.contains('expired')) {
        friendly = 'The code has expired. Please request a new code.';
      } else if (msg.contains('invalid') ||
          msg.contains('incorrect') ||
          msg.contains('token') ||
          msg.contains('otp')) {
        friendly = 'The verification code is incorrect.';
      }
      showAdminMessage(context, friendly, error: true);
    } catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNewPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final pwd = _passwordController.text;
    if (pwd != _confirmController.text) {
      showAdminMessage(context, 'Passwords do not match.', error: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _repository.setAdminRecoveredPassword(pwd);
      if (!mounted) return;
      // Success: pop with true so login can show confirmation
      Navigator.pop(context, true);
      // Use parent context after pop would be disposed, so show via root scaffold
      // The caller will show the success message; also show here as fallback
      // if still mounted (when popped, this widget is unmounted, so skip).
    } on AuthException catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _step = _ResetStep.email;
      _cooldown = 0;
      _otpController.clear();
    });
  }

  ThemeData _adminTheme(BuildContext context) {
    final base = NseapTheme.light;
    const radius = BorderRadius.all(Radius.circular(10));
    ButtonStyle dense(ButtonStyle? style) =>
        (style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(64, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
        );
    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: dense(base.filledButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: dense(base.elevatedButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: dense(base.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: dense(base.textButtonTheme.style),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _adminTheme(context),
      child: Scaffold(
        backgroundColor: NseapColors.background,
        appBar: AppBar(
          backgroundColor: NseapColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_step == _ResetStep.otp) {
                _changeEmail();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: const Text(
            'Admin Password Recovery',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProgress(),
                      const SizedBox(height: 26),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: switch (_step) {
                          _ResetStep.email => _buildEmailStep(),
                          _ResetStep.otp => _buildOtpStep(),
                          _ResetStep.password => _buildPasswordStep(),
                        },
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

  Widget _buildProgress() {
    const labels = ['Email', 'Verify', 'New Password'];
    final current = _step.index;
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index <= current;
        final done = index < current;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: active
                          ? AppColors.primary
                          : const Color(0xFFDCE4E0),
                      child: done
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: active ? Colors.white : Colors.black45,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[index],
                      style: TextStyle(
                        color: active ? AppColors.primary : Colors.black45,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 22),
                    color: index < current
                        ? AppColors.primary
                        : const Color(0xFFDCE4E0),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _stepCard({
    required Key key,
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A101828),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primaryLight,
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    return _stepCard(
      key: const ValueKey(_ResetStep.email),
      icon: Icons.mark_email_read_outlined,
      title: 'Find your admin account',
      description:
          'Enter your administrator email address to receive a verification code.',
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          onFieldSubmitted: (_) => _isLoading ? null : _sendOtp(),
          decoration: const InputDecoration(
            labelText: 'Admin email address',
            hintText: 'admin@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded),
            filled: true,
            fillColor: Color(0xFFF8FAFC),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Email is required';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid email address';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        _primaryButton(label: 'Send Verification Code', onPressed: _sendOtp),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return _stepCard(
      key: const ValueKey(_ResetStep.otp),
      icon: Icons.password_rounded,
      title: 'Verify your email',
      description:
          'Enter the 6-digit code sent to ${_emailController.text.trim()}. It expires shortly.',
      children: [
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onFieldSubmitted: (_) => _isLoading ? null : _verifyOtp(),
          decoration: const InputDecoration(
            labelText: 'Verification code',
            hintText: '• • • • • •',
            hintStyle: TextStyle(letterSpacing: 8, color: AppColors.textHint),
            prefixIcon: Icon(Icons.pin_outlined),
            filled: true,
            fillColor: Color(0xFFF8FAFC),
          ),
          validator: (value) {
            final v = value?.trim() ?? '';
            if (v.isEmpty) return 'Verification code is required';
            if (v.length != 6) return 'Enter the 6-digit code';
            if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Code must be 6 digits';
            return null;
          },
        ),
        const SizedBox(height: 18),
        _primaryButton(label: 'Verify Code', onPressed: _verifyOtp),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            if (_cooldown > 0)
              Text(
                'Resend in ${_cooldown}s',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              )
            else
              TextButton(
                onPressed: _isLoading ? null : _resendOtp,
                child: const Text('Resend code'),
              ),
            const Text(
              'or',
              style: TextStyle(color: Colors.black45, fontSize: 13),
            ),
            TextButton(
              onPressed: _isLoading ? null : _changeEmail,
              child: const Text('Change email'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return _stepCard(
      key: const ValueKey(_ResetStep.password),
      icon: Icons.lock_reset_rounded,
      title: 'Create new password',
      description:
          'Use at least 8 characters with uppercase, lowercase, number, and special character.',
      children: [
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enabled: !_isLoading,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          onChanged: _updatePasswordChecks,
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          validator: _validatePassword,
        ),
        const SizedBox(height: 10),
        _buildRequirementRows(),
        const SizedBox(height: 14),
        TextFormField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          enabled: !_isLoading,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _isLoading ? null : _saveNewPassword(),
          decoration: InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Confirm your new password';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        _primaryButton(label: 'Reset Password', onPressed: _saveNewPassword),
      ],
    );
  }

  Widget _buildRequirementRows() {
    return Column(
      children: [
        _reqRow('At least 8 characters', _hasMinLength),
        _reqRow('One uppercase letter', _hasUppercase),
        _reqRow('One lowercase letter', _hasLowercase),
        _reqRow('One number', _hasDigit),
        _reqRow('One special character', _hasSpecial),
      ],
    );
  }

  Widget _reqRow(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: met ? AppColors.primary : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: met ? AppColors.primary : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}
