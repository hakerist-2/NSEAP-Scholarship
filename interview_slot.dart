/// Hard cap on interviews the LGU accepts on a single day.
const int kMaxInterviewsPerDay = 15;

/// Interview half-day sessions. Morning covers times before 12:00 PM while
/// afternoon covers 12:00 PM onwards.
const String kInterviewSessionMorning = 'morning';
const String kInterviewSessionAfternoon = 'afternoon';

/// Returns the half-day session for [time] using its local hour.
String interviewSessionOf(DateTime time) =>
    time.hour < 12 ? kInterviewSessionMorning : kInterviewSessionAfternoon;

/// Morning share of a daily cap, rounded down (15 -> 7).
int interviewMorningLimit(int dayLimit) => dayLimit ~/ 2;

/// Afternoon share of a daily cap, taking the remainder (15 -> 8).
int interviewAfternoonLimit(int dayLimit) => dayLimit - dayLimit ~/ 2;

/// An interview window with capacity derived from active bookings.
class InterviewSlotRecord {
  const InterviewSlotRecord({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.location,
    required this.maximumSlots,
    required this.bookingCount,
    required this.bookingTimes,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String location;
  final int maximumSlots;
  final int? bookingCount;

  /// Start time of every active booking on this slot. Cancelled bookings are
  /// dropped; rescheduled and completed interviews still occupy a seat, so
  /// they stay. Used to attribute bookings to a calendar day.
  final List<DateTime> bookingTimes;

  /// Remaining slots, or `null` when booking data was not selected.
  int? get remainingCapacity {
    final count = bookingCount;
    if (count == null) return null;
    return (maximumSlots - count).clamp(0, maximumSlots);
  }

  /// Whether the slot is available or its capacity is unknown.
  bool get hasCapacity => remainingCapacity == null || remainingCapacity! > 0;

  /// Every day the office stays open for this slot, inclusive of both ends.
  List<DateTime> get coverageDays {
    final first = DateTime(startsAt.year, startsAt.month, startsAt.day);
    final last = DateTime(endsAt.year, endsAt.month, endsAt.day);
    final days = <DateTime>[];
    for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  /// Creates a slot and excludes cancelled bookings from usage. Rescheduled
  /// and completed interviews still occupy a seat, so they are kept.
  factory InterviewSlotRecord.fromJson(Map<String, dynamic> json) {
    final schedules = json['interview_schedules'];
    final bookingTimes = <DateTime>[];
    if (schedules is List) {
      for (final schedule in schedules) {
        if (schedule is! Map) continue;
        if (schedule['status'] == 'cancelled') continue;
        final parsed = schedule['scheduled_at'] is String
            ? DateTime.tryParse(schedule['scheduled_at'] as String)
            : null;
        if (parsed != null) bookingTimes.add(parsed.toLocal());
      }
    }

    return InterviewSlotRecord(
      id: json['id'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      location: json['location'] as String,
      maximumSlots: (json['maximum_slots'] as num).toInt(),
      bookingCount: schedules is List ? bookingTimes.length : null,
      bookingTimes: bookingTimes,
    );
  }
}
