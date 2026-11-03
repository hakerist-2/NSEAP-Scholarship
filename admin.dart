// Put here anything that assumes an authenticated admin session or the
// desktop-oriented admin chrome (`AdminShell`, `AdminSidebar`):
//   - admin pages under `lib/admin/pages/`
//   - admin repository & models (`lib/admin/data/`, `lib/admin/models/`)
//   - admin-only widgets (`lib/admin/widgets/`)
// `package:nseapscholarship/shared/shared.dart` instead.

// ── Shell / entry ───────────────────────────────────────────────────────────
export 'admin_entry_page.dart';
export 'admin_forgot_password_page.dart';
export 'admin_navigation.dart';
export 'admin_registration_page.dart';
export 'admin_security.dart';
export 'admin_shell.dart';

// ── Data ────────────────────────────────────────────────────────────────────
export 'data/admin_repository.dart';

// ── Domain models ───────────────────────────────────────────────────────────
export 'models/admin_models.dart';

// ── Shared admin page utilities ─────────────────────────────────────────────
export 'pages/admin_pages.dart';
export 'pages/shared/admin_page_support.dart';

// ── Widgets ─────────────────────────────────────────────────────────────────
export 'widgets/admin_widgets.dart';
