import 'package:flutter/material.dart';

/// Coordinates the selected main tab between WidgetTree and NavbarWidget.
ValueNotifier<int> selectPageNotifier = ValueNotifier(0);

/// Exposes whether the signed-in user should receive scholar-specific UI.
final ValueNotifier<bool> isScholarNotifier = ValueNotifier<bool>(false);

/// Shares the active user's avatar URL with profile-aware widgets.
final ValueNotifier<String?> avatarUrlNotifier = ValueNotifier<String?>(null);

/// Tracks whether the current application has locally saved draft data.
final ValueNotifier<bool> hasApplicationDraftNotifier = ValueNotifier<bool>(
  false,
);

/// Tracks whether the user has successfully submitted an application.
final ValueNotifier<bool> hasSubmittedApplicationNotifier = ValueNotifier<bool>(
  false,
);

/// Tracks the number of unread notifications for the current user.
/// Used to show a badge on the notification icon (mobile).
final ValueNotifier<int> unreadNotificationCountNotifier = ValueNotifier<int>(
  0,
);
