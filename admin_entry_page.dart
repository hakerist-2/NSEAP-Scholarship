import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_forgot_password_page.dart';
import 'admin_registration_page.dart';
import 'admin_security.dart';
import 'admin_shell.dart';
import 'data/admin_repository.dart';
import 'models/admin_models.dart';
import 'widgets/admin_widgets.dart';

/// Gates the administrator portal behind setup, authentication, and recovery.
class AdminEntryPage extends StatefulWidget {
  const AdminEntryPage({super.key, this.repository, this.preferLogin = false});

  final AdminRepository? repository;
  final bool preferLogin;

  @override
  State<AdminEntryPage> createState() => _AdminEntryPageState();
}

class _AdminEntryPageState extends State<AdminEntryPage> {
  late final AdminRepository _repository =
      widget.repository ?? AdminRepository();
  late Future<AdminProfile?> _authorization;
  late Future<bool> _setupComplete;
  StreamSubscription<AuthState>? _authSubscription;
  late bool _preferLogin;
  String? _loginMessage;
  bool _recovering =
      Uri.base.queryParameters['type'] == 'recovery' ||
      Uri.base.fragment.contains('type=recovery');

  @override
  void initState() {
    super.initState();
    _preferLogin = widget.preferLogin;
    _authorization = _checkAuthorization();
    _setupComplete = _repository.isSetupComplete();
    // Recovery links can establish a session after this widget is initialized.
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recovering = true);
      } else if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.tokenRefreshed) {
        // OTP recovery set _recovering=true under the pushed page; clear it on next
        // authenticated session so login with new password doesn't loop to Create Password.
        if (_recovering) setState(() => _recovering = false);
      } else if (state.event == AuthChangeEvent.signedOut) {
        setState(() {
          _recovering = false;
          _authorization = Future.value(null);
        });
      }
    });
  }

  Future<AdminProfile?> _checkAuthorization() async {
    if (_repository.currentSession == null) return null;
    final profile = await _repository.getCurrentAdmin();
    // Never retain a valid Supabase session for an unauthorized admin profile.
    if (profile != null && !profile.isAuthorized) {
      await _repository.signOut();
    }
    return profile;
  }

  void _retry() => setState(() {
    _authorization = _checkAuthorization();
  });

  void _retrySetup() =>
      setState(() => _setupComplete = _repository.isSetupComplete());

  void _registrationCreated() => setState(() {
    _setupComplete = Future.value(true);
    _preferLogin = true;
    _loginMessage = 'Administrator account created. You can now sign in.';
  });

  void _showSetup() => setState(() {
    _preferLogin = false;
    _loginMessage = null;
    _setupComplete = _repository.isSetupComplete();
  });

  void _showLogin() => setState(() {
    _recovering = false;
    _authorization = Future.value(null);
    _setupComplete = _repository.isSetupComplete();
    _preferLogin = true;
  });

  void _signedIn(AdminProfile profile) => setState(() {
    _recovering = false;
    _setupComplete = Future.value(true);
    _authorization = Future.value(profile);
  });

  Future<void> _finishPasswordChange() async {
    await _repository.signOut();
    if (mounted) _showLogin();
  }

  Widget _unauthenticatedView({required bool unauthorized}) {
    return FutureBuilder<bool>(
      future: _setupComplete,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: NseapColors.background,
            body: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: NseapColors.background,
            body: AdminStatePanel.error(
              message: 'Unable to check administrator setup status.',
              onRetry: _retrySetup,
            ),
          );
        }
        final setupComplete = snapshot.data == true;
        if (!setupComplete && !_preferLogin) {
          return AdminRegistrationPage(
            repository: _repository,
            onCreated: _registrationCreated,
            onSignIn: () => setState(() => _preferLogin = true),
          );
        }
        return _AdminLogin(
          repository: _repository,
          unauthorized: unauthorized,
          setupAvailable: !setupComplete,
          successMessage: _loginMessage,
          onSetup: _showSetup,
          onSignedIn: _signedIn,
          onRecoveryComplete: () => setState(() => _recovering = false),
        );
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _adminTheme(context),
      child: _recovering && _repository.currentSession != null
          ? AdminPasswordChangePage(
              repository: _repository,
              recovery: true,
              onCompleted: _finishPasswordChange,
            )
          : FutureBuilder<AdminProfile?>(
              future: _authorization,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    backgroundColor: NseapColors.background,
                    body: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Scaffold(
                    backgroundColor: NseapColors.background,
                    body: AdminStatePanel.error(
                      message: readableAdminError(snapshot.error),
                      onRetry: _retry,
                    ),
                  );
                }
                final profile = snapshot.data;
                if (profile?.isAuthorized == true) {
                  if (profile!.mustChangePassword) {
                    return AdminPasswordChangePage(
                      repository: _repository,
                      onCompleted: _finishPasswordChange,
                    );
                  }
                  return AdminShell(
                    repository: _repository,
                    profile: profile,
                    onProfileChanged: (profile) => setState(() {
                      _authorization = Future.value(profile);
                    }),
                    onSignedOut: _showLogin,
                  );
                }
                return _unauthenticatedView(unauthorized: profile != null);
              },
            ),
    );
  }
}

/// Applies the shared theme with denser buttons suited to admin data views.
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
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    iconButtonTheme: IconButtonThemeData(
      style: (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size.square(36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
    ),
  );
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin({
    required this.repository,
    required this.unauthorized,
    required this.setupAvailable,
    required this.onSetup,
    required this.onSignedIn,
    this.successMessage,
    this.onRecoveryComplete,
  });

  final AdminRepository repository;
  final bool unauthorized;
  final bool setupAvailable;
  final VoidCallback onSetup;
  final ValueChanged<AdminProfile> onSignedIn;
  final String? successMessage;
  final VoidCallback? onRecoveryComplete;

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
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
      final profile = await widget.repository.signIn(
        _username.text,
        _password.text,
      );
      widget.onSignedIn(profile);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = readableAdminError(error));
    } catch (error) {
      if (mounted) setState(() => _error = readableAdminError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final hintEmail = _username.text.contains('@')
        ? _username.text.trim()
        : null;
    final reset = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminForgotPasswordPage(
          repository: widget.repository,
          initialEmail: hintEmail,
        ),
      ),
    );
    if (!mounted) return;
    if (reset == true) {
      widget.onRecoveryComplete?.call();
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset successfully. Sign in with your new password.',
          ),
          backgroundColor: NseapColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NseapColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 64).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(child: _buildFormSurface()),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormSurface() {
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AdminBrandMark(),
                SizedBox(width: 12),
                Text(
                  'NSEAP ADMIN',
                  style: TextStyle(
                    color: NseapColors.primaryActive,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 28,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Sign in with your authorized administrator account to continue.',
              style: TextStyle(
                color: NseapColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (widget.successMessage != null) ...[
              const SizedBox(height: 22),
              _LoginNotice(
                message: widget.successMessage!,
                icon: Icons.check_circle_outline,
                background: AppColors.primaryLight,
                foreground: NseapColors.primaryActive,
              ),
            ],
            if (widget.unauthorized || _error != null) ...[
              const SizedBox(height: 22),
              _LoginNotice(
                message: _error ?? 'Access denied.',
                icon: Icons.error_outline,
                background: AppColors.errorSoft,
                foreground: AppColors.error,
              ),
            ],
            const SizedBox(height: 28),
            const Text(
              'Username or email',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _username,
              enabled: !_submitting,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Enter your username or email',
                prefixIcon: Icon(Icons.person_outline),
                fillColor: Color(0xFFF8FAFC),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter your username or email.';
                final valid = text.contains('@')
                    ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                    : RegExp(r'^[A-Za-z0-9_.]{4,30}$').hasMatch(text);
                return valid ? null : 'Enter a valid username or email.';
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                fillColor: const Color(0xFFF8FAFC),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) =>
                  (value?.isEmpty ?? true) ? 'Enter your password.' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: AppSizes.buttonHeight,
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(
                    AppSizes.buttonMinWidth,
                    AppSizes.buttonHeight,
                  ),
                  padding: AppPadding.button,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  textStyle: AppTextStyles.button,
                ),
                child: _submitting
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Signing in...'),
                        ],
                      )
                    : const Text('Sign in'),
              ),
            ),
            if (widget.setupAvailable) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'First time here?',
                    style: TextStyle(
                      color: NseapColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting ? null : widget.onSetup,
                    child: const Text('Create account'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14101828),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: form,
    );
  }
}

class _AdminBrandMark extends StatelessWidget {
  const _AdminBrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _LoginNotice extends StatelessWidget {
  const _LoginNotice({
    required this.message,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
