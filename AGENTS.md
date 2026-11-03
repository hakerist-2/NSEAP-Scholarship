# Repository Guide

## Toolchain and Checks

- This is one Flutter package (`nseapscholarship`), not a workspace. `pubspec.lock` requires Flutter >=3.44.0 and Dart >=3.12.0; install dependencies with `flutter pub get`.
- Format only Dart files you intentionally change: `dart format <paths>`. The current tree is not globally formatted, so formatting `.` creates unrelated churn.
- Run `dart analyze` for static verification. For a focused test use `flutter test test/<file>_test.dart`; add `--plain-name "<test name>"` to select one case.
- The only checked-in test, `test/widget_test.dart`, is the stale Flutter counter template. `flutter test` currently fails its counter assertions and reports an onboarding overflow at the default test viewport; do not present the suite as passing without fixing both issues.

## Runtime Wiring

- `lib/main.dart` is the executable entrypoint. It initializes a hard-coded Supabase URL/publishable key with a five-second timeout, then runs `MyApp`; initialization failure runs `NoConnectionApp`. There is no `.env` or other runtime config loader.
- `MyApp` currently opens `OnboardingPage` directly. `SplashscreenPage` contains session-based routing to `WidgetTree` or onboarding but is not wired into `MyApp`; changing splash logic alone does not change startup.
- Navigation uses imperative `Navigator`/`MaterialPageRoute`, not a router package. Successful login enters `lib/views/widget_tree.dart`.
- Main-tab state is the global `selectPageNotifier` in `lib/data/notifier.dart`. Tab indices are duplicated between the `pages` list in `widget_tree.dart` and `NavbarWidget`; keep both in the order Home, Application, QR Code, History, Profile.
- Most screens call `Supabase.instance.client` directly. `lib/repositories/auth_repository.dart` and `user_repository.dart` exist but have no callers, so repository-only edits do not currently affect UI behavior.
- Scholarship application document selection and submission in `application_page.dart` are UI-only; no form data or files are persisted yet. Do not assume the `users` table repository covers scholarship applications.

## Supabase Auth

- Email/password auth, Google OAuth, password reset, profile display, and sign-out are implemented in individual pages as well as the unused repositories; search all Supabase call sites before changing auth behavior.
- Callback configuration is not uniform: `AuthRepository.signUp` uses `io.supabase.flutter://login-callback`, its Google OAuth method uses `io.supabase.flutter://callback`, Android registers only the `login-callback` host, and iOS has no matching URL scheme entry. Keep Dart redirects, Supabase allowed redirects, and each target platform configuration aligned when working on callbacks.
- `UserRepository` expects a Supabase `users` table keyed by `id` and maps snake_case columns through `UserModel`; authentication screens primarily read Supabase auth user metadata instead.