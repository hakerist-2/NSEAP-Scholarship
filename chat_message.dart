/// Persisted chat message model backed by `public.chat_messages`.
class ChatMessage {
  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    this.model,
    this.createdAt,
  });

  final String? id;

  /// One of `user`, `assistant`, `system`.
  final String role;
  final String content;
  final String? model;
  final DateTime? createdAt;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);

  factory ChatMessage.assistant(String content, {String? model}) =>
      ChatMessage(role: 'assistant', content: content, model: model);

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String?,
    role: (json['role'] as String?) ?? 'user',
    content: (json['content'] as String?) ?? '',
    model: json['model'] as String?,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.tryParse(json['created_at'].toString()),
  );

  Map<String, dynamic> toOpenRouterJson() => {'role': role, 'content': content};
}
