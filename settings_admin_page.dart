import 'package:flutter/material.dart';
import 'package:nseapscholarship/theme/nseap_theme.dart';

import '../../admin_security.dart';
import '../../data/admin_repository.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

/// Lets the current administrator manage credentials and end their session.
/// Logic is preserved verbatim — only the presentation is refreshed to a
/// modern, clean card layout consistent with Notifications / Activity Logs.
class SettingsAdminPage extends StatelessWidget {
  const SettingsAdminPage({
    required this.repository,
    required this.profile,
    required this.onProfileChanged,
    required this.onSignedOut,
    super.key,
  });
  final AdminRepository repository;
  final AdminProfile profile;
  final ValueChanged<AdminProfile> onProfileChanged;
  final VoidCallback onSignedOut;

  Future<void> _changeUsername(BuildContext context) async {
    final updated = await showAdminUsernameDialog(
      context,
      repository: repository,
      profile: profile,
    );
    if (updated == null || !context.mounted) return;
    onProfileChanged(updated);
    showAdminMessage(
      context,
      'Username changed successfully. Use your new username the next time you sign in.',
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showAdminPasswordDialog(
      context,
      repository: repository,
    );
    if (!changed || !context.mounted) return;
    showAdminMessage(context, 'Password changed successfully.');
    // Revoke all sessions after a password change instead of reusing old tokens.
    await repository.signOut();
    if (context.mounted) onSignedOut();
  }

  Future<void> _changeEmail(BuildContext context) async {
    final updated = await showAdminEmailDialog(
      context,
      repository: repository,
      profile: profile,
    );
    if (updated == null || !context.mounted) return;
    onProfileChanged(updated);
    showAdminMessage(context, 'Email address changed successfully.');
  }

  Future<void> _logout(BuildContext context) async {
    await repository.signOut();
    if (context.mounted) onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.trim().isEmpty ? 'A' : profile.name.trim()[0].toUpperCase();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const AdminPageHeader(
              title: 'Settings',
              subtitle: 'Manage your administrator account and session',
            ),
            const SizedBox(height: 18),

            // ── Hero profile ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: AppElevation.shadowXs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.24), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.email,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.8,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Account ──
            _SettingsCard(
              title: 'Account',
              subtitle: 'Your sign-in identity',
              icon: Icons.person_rounded,
              children: [
                _ActionTile(
                  icon: Icons.alternate_email_rounded,
                  label: 'Username',
                  value: profile.username.isEmpty ? '—' : '@${profile.username}',
                  actionLabel: 'Change',
                  onPressed: () => _changeUsername(context),
                ),
                const Divider(height: 1, color: AppColors.borderLight),
                _ActionTile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email address',
                  value: profile.email,
                  actionLabel: 'Change',
                  onPressed: () => _changeEmail(context),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Security ──
            _SettingsCard(
              title: 'Security',
              subtitle: 'Keep your sign-in protected',
              icon: Icons.lock_rounded,
              children: [
                _ActionTile(
                  icon: Icons.password_rounded,
                  label: 'Password',
                  value: '••••••••••••',
                  hint: 'Last changed — sign-in secret',
                  actionLabel: 'Change Password',
                  primary: true,
                  onPressed: () => _changePassword(context),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Session ──
            _SettingsCard(
              title: 'Session',
              subtitle: 'You are signed in on this device',
              icon: Icons.logout_rounded,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: SizedBox(
                    width: 120, 
                    height: 40, 
                    child: OutlinedButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Log out'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.22)),
                        backgroundColor: AppColors.errorLight.withValues(alpha: 0.55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppElevation.shadowXs,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textTertiary,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          ...children,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Icon(icon, size: 16, color: iconColor ?? AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onPressed,
    this.hint,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary ? AppColors.primaryLight : AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary ? AppColors.primary.withValues(alpha: 0.14) : AppColors.borderLight),
            ),
            child: Icon(icon, size: 16, color: primary ? AppColors.primary : AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.3,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: AppColors.textTertiary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 34,
            child: primary
                ? FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    child: Text(actionLabel),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      foregroundColor: AppColors.textPrimary,
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    child: Text(actionLabel),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color, required this.bg});
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: color, height: 1),
          ),
        ],
      ),
    );
  }
}
