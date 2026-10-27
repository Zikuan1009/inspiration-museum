class InspirationRecord {
  const InspirationRecord({
    required this.id,
    required this.keywords,
    required this.quote,
    required this.userText,
    required this.isPrivate,
    required this.timestamp,
    this.imagePath,
    this.authorId = '',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.savesCount = 0,
  });

  final String id;
  final List<String> keywords;
  final String quote;
  final String userText;
  final String? imagePath;
  final bool isPrivate;
  final DateTime timestamp;

  /// 发帖人。空字符串表示本地尚未绑定账户的旧存档。
  final String authorId;

  final int likesCount;
  final int commentsCount;
  final int savesCount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'keywords': keywords,
      'quote': quote,
      'userText': userText,
      'imagePath': imagePath,
      'isPrivate': isPrivate,
      'timestamp': timestamp.toIso8601String(),
      'authorId': authorId,
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'savesCount': savesCount,
    };
  }

  factory InspirationRecord.fromJson(Map<String, dynamic> json) {
    final rawKeywords = json['keywords'];
    return InspirationRecord(
      id: json['id'] as String? ?? '',
      keywords: rawKeywords is List
          ? rawKeywords.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      quote: json['quote'] as String? ?? '',
      userText: json['userText'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
      isPrivate: json['isPrivate'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      authorId: json['authorId'] as String? ?? '',
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      commentsCount: (json['commentsCount'] as num?)?.toInt() ?? 0,
      savesCount: (json['savesCount'] as num?)?.toInt() ?? 0,
    );
  }
}
