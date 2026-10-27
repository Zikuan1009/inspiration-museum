/// 灵感评论。作者信息来自 `comments` 联表 `profiles`。
class InspirationComment {
  const InspirationComment({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String username;
  final String content;
  final DateTime createdAt;

  factory InspirationComment.fromSupabase(Map<String, dynamic> json) {
    Map<String, dynamic>? profile;
    final raw = json['profiles'];
    if (raw is Map<String, dynamic>) {
      profile = raw;
    } else if (raw is Map) {
      profile = Map<String, dynamic>.from(raw);
    }
    final name = profile?['username']?.toString().trim() ?? '';
    return InspirationComment(
      id: json['id']?.toString() ?? '',
      userId:
          profile?['id']?.toString() ?? json['user_id']?.toString() ?? '',
      username: name.isEmpty ? 'ANON' : name,
      content: json['content']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
