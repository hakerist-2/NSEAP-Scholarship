/// A time-bounded intake window for new scholarship applicants.
class ApplicationPeriod {
  const ApplicationPeriod({
    required this.id,
    required this.academicYear,
    required this.startsAt,
    required this.deadline,
    required this.status,
  });

  final String id;
  final String academicYear;
  final DateTime startsAt;
  final DateTime deadline;
  final String status;

  factory ApplicationPeriod.fromJson(Map<String, dynamic> json) =>
      ApplicationPeriod(
        id: json['id'] as String,
        academicYear: json['academic_year'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        deadline: DateTime.parse(
          json['application_deadline'] as String,
        ).toLocal(),
        status: json['status'] as String,
      );

  bool isOpen([DateTime? now]) {
    final current = now ?? DateTime.now();
    final currentDate = DateTime(current.year, current.month, current.day);
    final startDate = DateTime(startsAt.year, startsAt.month, startsAt.day);
    return status == 'active' &&
        !currentDate.isBefore(startDate) &&
        !current.isAfter(deadline);
  }

  bool isUpcoming([DateTime? now]) {
    final current = now ?? DateTime.now();
    final currentDate = DateTime(current.year, current.month, current.day);
    final startDate = DateTime(startsAt.year, startsAt.month, startsAt.day);
    return status == 'upcoming' ||
        (status == 'active' && currentDate.isBefore(startDate));
  }

  bool isClosed([DateTime? now]) {
    final current = now ?? DateTime.now();
    return status == 'closed' ||
        status == 'archived' ||
        (status == 'active' && current.isAfter(deadline));
  }
}
