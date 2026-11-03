import 'package:flutter/material.dart';

/// Carries searches submitted from the admin shell into the applicants page.
final adminApplicantSearchNotifier = ValueNotifier<String>('');

/// Bumps whenever an application status changes outside the applicants page
/// (e.g. interviews), so the cached applicants list reloads fresh data.
final adminApplicationsRefreshNotifier = ValueNotifier<int>(0);

/// Identifies the destinations available in the administrator shell.
enum AdminSection {
  overview('Overview', Icons.dashboard_outlined),
  applicants('Applicants', Icons.people_alt_outlined),
  interviews('Interviews', Icons.calendar_month_outlined),
  scholars('Scholars', Icons.school_outlined),
  requirements('Application Window', Icons.fact_check_outlined),
  announcements('Announcements', Icons.campaign_outlined),
  reports('Report', Icons.assessment_outlined),
  notifications('Notifications', Icons.notifications_none_rounded),
  helpSupport('Help and Support', Icons.support_agent_outlined),
  activityLogs('Activity Logs', Icons.history_rounded),
  settings('Settings', Icons.settings_outlined);

  /// Deprecated alias — use activityLogs.
  @Deprecated('Use activityLogs')
  static AdminSection get auditLogs => activityLogs;

  const AdminSection(this.label, this.icon);

  final String label;
  final IconData icon;
}
