class SupportConversation {
  SupportConversation.fromJson(Map<String, dynamic> row)
    : userId = row['user_id'] as String,
      name = (row['sender_name'] as String?)?.trim().isEmpty == true
          ? 'Scholarship applicant'
          : (row['sender_name'] as String? ?? 'Scholarship applicant'),
      userType = row['user_type'] as String? ?? 'New Applicant',
      status = row['status'] as String? ?? 'pending',
      preview = row['preview'] as String? ?? '',
      unread = switch (row['unread_count']) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v) ?? 0,
        _ => 0,
      },
      createdAt = DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt = row['updated_at'] == null
          ? DateTime.parse(row['created_at'] as String).toLocal()
          : DateTime.parse(row['updated_at'] as String).toLocal();

  final String userId;
  final String name;
  final String userType;
  final String status;
  final String preview;
  final int unread;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == 'pending';
}

class SupportMessage {
  SupportMessage.fromJson(Map<String, dynamic> row)
    : seq = switch (row['seq']) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v) ?? 0,
        _ => 0,
      },
      senderId = row['sender_id'] as String,
      isAdmin = row['sender_role'] == 'admin',
      body = row['body'] as String? ?? '',
      createdAt = DateTime.parse(row['created_at'] as String).toLocal();

  final int seq;
  final String senderId;
  final bool isAdmin;
  final String body;
  final DateTime createdAt;
}
