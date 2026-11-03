/// A user-targeted notification and its read state.
class NotificationRecord {
  const NotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.createdBy,
    this.readAt,
    this.fromSharedFeed = false,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final String? createdBy;
  final DateTime? readAt;

  /// True when the row came from the shared `announcements` table (no
  /// per-user read/delete columns; handled with local preferences).
  final bool fromSharedFeed;

  /// Whether the notification has a recorded read timestamp.
  bool get isRead => readAt != null;

  /// Creates a notification from a `notifications` row.
  factory NotificationRecord.fromJson(Map<String, dynamic> json) {
    final readAt = json['read_at'] as String?;
    return NotificationRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: json['category'] as String? ?? 'general',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      createdBy: json['created_by'] as String?,
      readAt: readAt == null ? null : DateTime.parse(readAt).toLocal(),
    );
  }
}
