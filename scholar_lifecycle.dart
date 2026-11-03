/// A user's active or historical scholar identity and lifecycle status.
class ScholarProfile {
  const ScholarProfile({
    required this.id,
    required this.userId,
    required this.applicationId,
    required this.scholarId,
    required this.status,
    required this.startedAt,
    this.graduationDate,
    this.graduationNotes,
  });

  final String id;
  final String userId;
  final String applicationId;

  /// The public scholar reference assigned after application approval.
  final String scholarId;

  /// The lifecycle state stored in `scholar_status`.
  final String status;
  final DateTime startedAt;
  final DateTime? graduationDate;
  final String? graduationNotes;

  /// Creates a scholar profile from a `scholar_profiles` row.
  factory ScholarProfile.fromJson(Map<String, dynamic> json) {
    return ScholarProfile(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      applicationId: json['application_id'] as String,
      scholarId: json['scholar_id'] as String,
      status: json['scholar_status'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      graduationDate: _optionalDate(json['graduation_date']),
      graduationNotes: json['graduation_notes'] as String?,
    );
  }
}

/// An academic term during which scholar submissions are accepted.
class SemesterPeriod {
  const SemesterPeriod({
    required this.id,
    required this.academicYear,
    required this.semester,
    required this.startsAt,
    required this.submissionDeadline,
    required this.endsAt,
    required this.status,
  });

  final String id;
  final String academicYear;
  final String semester;
  final DateTime startsAt;
  final DateTime submissionDeadline;
  final DateTime endsAt;
  final String status;

  /// Creates a semester period from a `semester_periods` row.
  factory SemesterPeriod.fromJson(Map<String, dynamic> json) {
    return SemesterPeriod(
      id: json['id'] as String,
      academicYear: json['academic_year'] as String,
      semester: json['semester'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String),
      submissionDeadline: DateTime.parse(
        json['submission_deadline'] as String,
      ).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String),
      status: json['status'] as String,
    );
  }

  bool get isActiveStatus => status == 'active';

  /// True when the period is active and the submission deadline has not
  /// passed. The stored `status` is the source of truth: an `active` period
  /// is open even when `startsAt` is still in the future, because the admin
  /// Application Window dialog no longer offers an `upcoming` status and
  /// admins can open a window before its nominal start date.
  bool isSubmissionOpen([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (!isActiveStatus) return false;
    return !current.isAfter(submissionDeadline);
  }

  /// True only for rows still stored as `upcoming`; an `active` row is never
  /// upcoming regardless of its start date.
  bool get isUpcoming => status == 'upcoming';

  bool get isClosed =>
      status == 'closed' ||
      (isActiveStatus && DateTime.now().isAfter(submissionDeadline));

  String get displayLabel => '$academicYear · $semester';

  /// Only this period's requirements determine its status. Legacy submissions
  /// without a period ID are matched by both academic year and semester.
  String submissionStatus(Iterable<Map<String, dynamic>> submissions) {
    for (final submission in submissions) {
      final periodId = submission['period_id'];
      final matches = periodId != null
          ? periodId == id
          : submission['academic_year'] == academicYear &&
                submission['semester'] == semester;
      if (matches) return submission['status'] as String? ?? 'not_submitted';
    }
    return 'not_submitted';
  }
}

/// A time-bounded announcement published to a scholar audience.
class ScholarAnnouncement {
  const ScholarAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.publishedAt,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String body;
  final String audience;
  final DateTime publishedAt;
  final DateTime? expiresAt;

  /// Creates an announcement from an `announcements` row.
  factory ScholarAnnouncement.fromJson(Map<String, dynamic> json) {
    return ScholarAnnouncement(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      audience: json['audience'] as String,
      publishedAt: DateTime.parse(json['published_at'] as String).toLocal(),
      expiresAt: _optionalDate(json['expires_at'], toLocal: true),
    );
  }
}

DateTime? _optionalDate(dynamic value, {bool toLocal = false}) {
  if (value is! String) return null;
  final date = DateTime.tryParse(value);
  return toLocal ? date?.toLocal() : date;
}
