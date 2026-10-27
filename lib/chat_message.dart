import 'package:inspiration_museum/user_model.dart';

/// 一条点对点消息。后续可直接写入 Firebase `messages/{id}`。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.timestamp,
    required this.isRead,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime timestamp;
  final bool isRead;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? text,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      receiverId: json['receiverId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  factory ChatMessage.fromSupabase(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString() ?? '',
      text: (json['content'] as String?) ?? (json['text'] as String?) ?? '',
      timestamp: _parseTime(json['created_at'] ?? json['timestamp']),
      isRead: _asRead(json['is_read'] ?? json['isRead']),
    );
  }

  static bool _asRead(dynamic raw) {
    if (raw == false || raw == 0 || raw == 'false' || raw == 'f') return false;
    return true;
  }

  static DateTime _parseTime(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// 会话列表行：对端用户 + 最后一条消息（云端组装）。
class ChatSessionModel {
  const ChatSessionModel({
    required this.peer,
    required this.lastMessage,
    required this.lastAt,
    this.unreadCount = 0,
    this.lastUnreadAt,
  });

  final UserModel peer;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;
  final DateTime? lastUnreadAt;
}

/// 会话列表行：对端用户 + 最后一条消息。
class ChatThread {
  const ChatThread({
    required this.peer,
    required this.lastMessage,
    this.unreadCount = 0,
  });

  final UserModel peer;
  final ChatMessage lastMessage;
  final int unreadCount;
}
