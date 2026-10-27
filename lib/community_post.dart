import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:share_plus/share_plus.dart';

/// 社区 UGC 数据模型（Mock）。
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.theme,
    required this.themeEn,
    required this.keywords,
    required this.text,
    required this.quote,
    required this.quoteAuthor,
    this.title = '',
    this.authorId = '',
    this.artworkSeed,
    this.aspectRatio = 1.0,
    this.imagePath,
    this.isPrivate = false,
  });

  final String id;

  /// 云端 `inspirations.id`。本地 `vault_` 卡片不是 UUID，不能查互动表。
  bool get isCloudPost {
    final value = id.trim();
    if (value.isEmpty || value.startsWith('vault_')) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
  final String authorId;
  final String author;
  final String theme;
  final String themeEn;
  final List<String> keywords;
  final String text;

  /// 用户写的标题。旧帖没有标题时为空，正文仍在 [text]。
  final String title;
  final String quote;
  final String quoteAuthor;
  final String? imagePath;

  /// 作者标成私密时，不出现在公开馆藏里。
  final bool isPrivate;

  /// 为空表示纯文字卡片；否则用该种子绘制一幅几何配图。
  final int? artworkSeed;

  /// 配图宽高比（宽 / 高）。
  final double aspectRatio;

  CommunityPost copyWith({
    String? title,
    String? text,
    bool? isPrivate,
    String? imagePath,
    List<String>? keywords,
    String? quote,
  }) {
    return CommunityPost(
      id: id,
      author: author,
      authorId: authorId,
      theme: theme,
      themeEn: themeEn,
      keywords: keywords ?? this.keywords,
      title: title ?? this.title,
      text: text ?? this.text,
      quote: quote ?? this.quote,
      quoteAuthor: quoteAuthor,
      artworkSeed: artworkSeed,
      aspectRatio: aspectRatio,
      imagePath: imagePath ?? this.imagePath,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }

  bool get hasArtwork => artworkSeed != null;
  bool get hasFileImage =>
      imagePath != null && imagePath!.isNotEmpty && !hasNetworkImage;
  bool get hasNetworkImage {
    final path = imagePath;
    if (path == null || path.isEmpty) return false;
    return path.startsWith('http://') || path.startsWith('https://');
  }

  static const _themeEn = <String, String>{
    '音乐': 'MUSIC',
    '绘画': 'PAINTING',
    '建筑': 'ARCHITECTURE',
    '机械': 'MECHANICS',
    '文学': 'LITERATURE',
    '摄影': 'PHOTOGRAPHY',
    '电影': 'FILM',
    '戏剧': 'THEATRE',
    '自然': 'NATURE',
    '科学': 'SCIENCE',
    '书法': 'CALLIGRAPHY',
    '雕塑': 'SCULPTURE',
    '舞蹈': 'DANCE',
    '哲学': 'PHILOSOPHY',
    '爱情': 'LOVE',
    '服饰': 'FASHION',
    '神话': 'MYTH',
    '城市': 'CITY',
    '光学': 'OPTICS',
    '饮食': 'FOOD',
    '认知': 'MIND',
    '排版': 'TYPOGRAPHY',
    '交通': 'TRANSIT',
    '器物': 'OBJECT',
    '几何': 'GEOMETRY',
    '逻辑': 'LOGIC',
    '默认': 'DEFAULT',
    '灵感': 'INSPIRATION',
  };

  static String themeLabel(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'INSPIRATION';
    return _themeEn[trimmed] ?? trimmed;
  }

  static Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) return _asMap(raw.first);
    return null;
  }

  /// 标题和正文都写在 `user_text` 里，用这个分隔，避免再加数据库列。
  static const userTextSplit = '\u001e';

  static ({String title, String body}) splitUserText(String raw) {
    final index = raw.indexOf(userTextSplit);
    if (index < 0) return (title: '', body: raw.trim());
    return (
      title: raw.substring(0, index).trim(),
      body: raw.substring(index + userTextSplit.length).trim(),
    );
  }

  static String packUserText(String title, String body) {
    final heading = title.trim();
    final content = body.trim();
    if (heading.isEmpty) return content;
    return '$heading$userTextSplit$content';
  }

  static const _wrappingQuotes = {
    '"',
    "'",
    '“',
    '”',
    '‘',
    '’',
    '「',
    '」',
    '『',
    '』',
    '＂',
  };

  /// 名言原文可能已经带引号。展示时只保留一对。
  static String unwrapQuotes(String raw) {
    var text = raw.trim();
    while (text.length >= 2 &&
        _wrappingQuotes.contains(text[0]) &&
        _wrappingQuotes.contains(text[text.length - 1])) {
      final inner = text.substring(1, text.length - 1).trim();
      if (inner.isEmpty) return '';
      text = inner;
    }
    return text;
  }

  static String quotedText(String raw) {
    final text = unwrapQuotes(raw);
    if (text.isEmpty) return '';
    return '“$text”';
  }

  static List<String> _asStringList(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return [
        for (final part in raw.split(RegExp(r'[,，|]')))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    return const [];
  }

  factory CommunityPost.fromSupabase(Map<String, dynamic> json) {
    final profile = _asMap(json['profiles']);
    final authorId =
        json['author_id']?.toString() ??
        profile?['id']?.toString() ??
        '';
    final author = (profile?['username'] as String?)?.trim().isNotEmpty == true
        ? profile!['username'] as String
        : 'ANON';
    final keywords = _asStringList(json['keywords']);
    final theme = keywords.isNotEmpty
        ? keywords.first
        : ((json['theme'] as String?)?.trim().isNotEmpty == true
              ? json['theme'] as String
              : 'INSPIRATION');
    final image =
        (json['image_url'] as String?)?.trim().isNotEmpty == true
        ? json['image_url'] as String
        : ((json['image_path'] as String?)?.trim().isNotEmpty == true
              ? json['image_path'] as String
              : null);
    final id = json['id']?.toString() ?? '';
    final written = splitUserText(
      (json['user_text'] as String?)?.trim().isNotEmpty == true
          ? json['user_text'] as String
          : ((json['content'] as String?)?.trim().isNotEmpty == true
                ? json['content'] as String
                : ((json['text'] as String?) ?? '')),
    );
    return CommunityPost(
      id: id,
      authorId: authorId,
      author: author,
      theme: theme,
      themeEn:
          (json['theme_en'] as String?)?.trim().isNotEmpty == true
          ? json['theme_en'] as String
          : (_themeEn[theme] ?? 'INSPIRATION'),
      keywords: keywords,
      title: written.title,
      text: written.body,
      quote: (json['quote'] as String?) ?? '',
      quoteAuthor:
          (json['quote_author'] as String?) ??
          (json['quoteAuthor'] as String?) ??
          '',
      imagePath: image,
      isPrivate: json['is_private'] == true,
      artworkSeed: image == null && id.isNotEmpty ? id.hashCode : null,
      aspectRatio: (json['aspect_ratio'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// 模拟的社区数据流。
const List<CommunityPost> mockCommunityPosts = [
  CommunityPost(
    id: 'p01',
    author: '林一',
    theme: '几何',
    themeEn: 'GEOMETRY',
    keywords: ['网格', '负空间', '模数'],
    text: '把一天拆成 24 个正方形，留白的那几格才是真正属于自己的。',
    quote: 'Keep one clear margin, and let a single decision be enough.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 11,
    aspectRatio: 0.8,
  ),
  CommunityPost(
    id: 'p02',
    author: 'Kato',
    theme: '摄影',
    themeEn: 'PHOTOGRAPHY',
    keywords: ['决定性瞬间', '逆光', '颗粒'],
    text: '逆光里的人没有五官，只剩下轮廓。反而更像他本人。',
    quote: 'Move until the frame leaves something out on purpose.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 23,
    aspectRatio: 1.25,
  ),
  CommunityPost(
    id: 'p03',
    author: '陈禹',
    theme: '音乐',
    themeEn: 'MUSIC',
    keywords: ['休止符', '节拍', '共鸣'],
    text:
        '今天练琴，第一次觉得休止符不是“没有声音”，而是声音在等我。'
        '也许生活里的空档也一样，不是浪费，是在等下一拍。',
    quote: 'Count the rests before you add another note.',
    quoteAuthor: 'Original prompt',
  ),
  CommunityPost(
    id: 'p04',
    author: 'Mara',
    theme: '建筑',
    themeEn: 'ARCHITECTURE',
    keywords: ['混凝土', '光井', '尺度'],
    text: '在美术馆里抬头，光从一条窄缝落下来，所有人都不说话了。',
    quote: 'Stand where the light enters and notice what the wall is doing.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 37,
    aspectRatio: 0.7,
  ),
  CommunityPost(
    id: 'p05',
    author: '周野',
    theme: '机械',
    themeEn: 'MECHANICS',
    keywords: ['齿轮', '公差', '传动'],
    text: '拆了一只旧手表。最小的齿轮只有米粒大，却决定了整只表的准与不准。',
    quote: 'Remove one part and see whether the motion still explains itself.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 42,
    aspectRatio: 1.0,
  ),
  CommunityPost(
    id: 'p06',
    author: 'Sol',
    theme: '爱情',
    themeEn: 'LOVE',
    keywords: ['沉默', '平行线', '注视'],
    text: '两条平行线不会相遇，但它们永远朝着同一个方向。',
    quote: 'Write down one thing you would do for them before noon.',
    quoteAuthor: 'Original prompt',
  ),
  CommunityPost(
    id: 'p07',
    author: '何木',
    theme: '文学',
    themeEn: 'LITERATURE',
    keywords: ['留白', '第二人称', '省略号'],
    text: '删掉了开头的三段，故事反而更近了。',
    quote: 'Leave the explanation out, and keep the detail that does the work.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 58,
    aspectRatio: 1.4,
  ),
  CommunityPost(
    id: 'p08',
    author: 'Ilse',
    theme: '色彩',
    themeEn: 'COLOR',
    keywords: ['互补色', '灰度', '边界'],
    text: '把所有颜色去掉，只留黑白，才看清哪一块是主角。',
    quote: 'Set two colors together and write which one arrives first.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 64,
    aspectRatio: 0.9,
  ),
  CommunityPost(
    id: 'p09',
    author: '苏禾',
    theme: '数学',
    themeEn: 'MATHEMATICS',
    keywords: ['对称', '极限', '证明'],
    text: '一个漂亮的证明，像是把一扇门推开，然后发现门外本来就没有墙。',
    quote: 'Write the smallest case that still shows the pattern.',
    quoteAuthor: 'Original prompt',
  ),
  CommunityPost(
    id: 'p10',
    author: 'Ren',
    theme: '舞蹈',
    themeEn: 'DANCE',
    keywords: ['重心', '呼吸', '落地'],
    text: '落地的那一下，如果听得见声音，就说明还没准备好。',
    quote: 'Let the next step start before you name the reason.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 71,
    aspectRatio: 0.75,
  ),
  CommunityPost(
    id: 'p11',
    author: '白桉',
    theme: '哲学',
    themeEn: 'PHILOSOPHY',
    keywords: ['界限', '沉默', '语言'],
    text: '说不清的事情，先别急着说清。有些东西一说出来就变形了。',
    quote: 'If the sentence keeps slipping, describe the situation instead.',
    quoteAuthor: 'Original prompt',
    artworkSeed: 83,
    aspectRatio: 1.1,
  ),
  CommunityPost(
    id: 'p12',
    author: 'Noa',
    theme: '字体',
    themeEn: 'TYPOGRAPHY',
    keywords: ['字距', '基线', '衬线'],
    text: '好的排版是看不见的。你只会觉得——读起来真顺。',
    quote: 'Widen the line until the words are easier to follow.',
    quoteAuthor: 'Original prompt',
  ),
];

/// 用几何图形生成的“配图”：黑白、直角、圆与斜线。
/// 相同 seed 永远得到相同画面，因此可作为稳定的 Mock 图片。
class BauhausArtwork extends StatelessWidget {
  const BauhausArtwork({super.key, required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ArtworkPainter(seed));
  }
}

class _ArtworkPainter extends CustomPainter {
  const _ArtworkPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;
    final ink = Paint()..color = const Color(0xFF111111);
    final line = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // 底层浅灰色块
    final greyCount = 1 + rng.nextInt(2);
    for (var i = 0; i < greyCount; i++) {
      final rw = w * (0.25 + rng.nextDouble() * 0.45);
      final rh = h * (0.2 + rng.nextDouble() * 0.5);
      final x = rng.nextDouble() * (w - rw);
      final y = rng.nextDouble() * (h - rh);
      canvas.drawRect(
        Rect.fromLTWH(x, y, rw, rh),
        Paint()..color = const Color(0xFFE6E6E6),
      );
    }

    // 主圆
    final r = math.min(w, h) * (0.16 + rng.nextDouble() * 0.16);
    final cx = r + rng.nextDouble() * (w - 2 * r);
    final cy = r + rng.nextDouble() * (h - 2 * r);
    if (rng.nextBool()) {
      canvas.drawCircle(Offset(cx, cy), r, ink);
    } else {
      canvas.drawCircle(Offset(cx, cy), r, line);
      canvas.drawCircle(Offset(cx, cy), r * 0.55, ink);
    }

    // 黑色矩形
    final bw = w * (0.08 + rng.nextDouble() * 0.3);
    final bh = h * (0.06 + rng.nextDouble() * 0.35);
    final bx = rng.nextDouble() * (w - bw);
    final by = rng.nextDouble() * (h - bh);
    canvas.drawRect(Rect.fromLTWH(bx, by, bw, bh), ink);

    // 细线
    final lineCount = 2 + rng.nextInt(4);
    for (var i = 0; i < lineCount; i++) {
      switch (rng.nextInt(3)) {
        case 0:
          final y = rng.nextDouble() * h;
          canvas.drawLine(Offset(0, y), Offset(w, y), line);
        case 1:
          final x = rng.nextDouble() * w;
          canvas.drawLine(Offset(x, 0), Offset(x, h), line);
        default:
          canvas.drawLine(
            Offset(rng.nextDouble() * w, 0),
            Offset(rng.nextDouble() * w, h),
            line,
          );
      }
    }

    // 网格角标
    if (rng.nextBool()) {
      final gx = rng.nextBool() ? 0.0 : w * 0.7;
      final gy = rng.nextBool() ? 0.0 : h * 0.7;
      const step = 6.0;
      final gw = w * 0.3;
      final gh = h * 0.3;
      for (var x = gx; x <= gx + gw; x += step) {
        canvas.drawLine(
          Offset(x, gy),
          Offset(x, gy + gh),
          line..strokeWidth = 0.5,
        );
      }
      for (var y = gy; y <= gy + gh; y += step) {
        canvas.drawLine(Offset(gx, y), Offset(gx + gw, y), line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArtworkPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

// ---------------------------------------------------------------------------
// 极细线框图标：点赞 / 收藏 / 评论 / 转发
// ---------------------------------------------------------------------------

enum LineIconKind { like, save, comment, share }

class LineIcon extends StatelessWidget {
  const LineIcon(
    this.kind, {
    super.key,
    this.size = 18,
    this.filled = false,
    this.color = const Color(0xFF111111),
    this.strokeWidth = 1.0,
  });

  final LineIconKind kind;
  final double size;
  final bool filled;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LineIconPainter(
          kind: kind,
          filled: filled,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  const _LineIconPainter({
    required this.kind,
    required this.filled,
    required this.color,
    required this.strokeWidth,
  });

  final LineIconKind kind;
  final bool filled;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;

    switch (kind) {
      case LineIconKind.like:
        // 心形：两段三次贝塞尔
        final path = Path()
          ..moveTo(s * 0.5, s * 0.86)
          ..cubicTo(s * 0.12, s * 0.62, s * 0.06, s * 0.30, s * 0.28, s * 0.20)
          ..cubicTo(s * 0.40, s * 0.14, s * 0.48, s * 0.22, s * 0.5, s * 0.30)
          ..cubicTo(s * 0.52, s * 0.22, s * 0.60, s * 0.14, s * 0.72, s * 0.20)
          ..cubicTo(s * 0.94, s * 0.30, s * 0.88, s * 0.62, s * 0.5, s * 0.86)
          ..close();
        canvas.drawPath(path, filled ? fill : stroke);
      case LineIconKind.save:
        // 书签
        final path = Path()
          ..moveTo(s * 0.26, s * 0.14)
          ..lineTo(s * 0.74, s * 0.14)
          ..lineTo(s * 0.74, s * 0.86)
          ..lineTo(s * 0.5, s * 0.68)
          ..lineTo(s * 0.26, s * 0.86)
          ..close();
        canvas.drawPath(path, filled ? fill : stroke);
      case LineIconKind.comment:
        // 矩形对话框 + 小三角
        final path = Path()
          ..moveTo(s * 0.14, s * 0.18)
          ..lineTo(s * 0.86, s * 0.18)
          ..lineTo(s * 0.86, s * 0.66)
          ..lineTo(s * 0.42, s * 0.66)
          ..lineTo(s * 0.26, s * 0.82)
          ..lineTo(s * 0.26, s * 0.66)
          ..lineTo(s * 0.14, s * 0.66)
          ..close();
        canvas.drawPath(path, stroke);
      case LineIconKind.share:
        // 向右上的折线箭头 + 托盘
        canvas.drawLine(
          Offset(s * 0.30, s * 0.62),
          Offset(s * 0.78, s * 0.20),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.50, s * 0.20),
          Offset(s * 0.78, s * 0.20),
          stroke,
        );
        canvas.drawLine(
          Offset(s * 0.78, s * 0.20),
          Offset(s * 0.78, s * 0.48),
          stroke,
        );
        final tray = Path()
          ..moveTo(s * 0.18, s * 0.50)
          ..lineTo(s * 0.18, s * 0.84)
          ..lineTo(s * 0.82, s * 0.84)
          ..lineTo(s * 0.82, s * 0.66);
        canvas.drawPath(tray, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.filled != filled ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// 四个横向排列的互动按钮：点赞 / 收藏 / 评论 / 转发。
class InteractionBar extends StatefulWidget {
  const InteractionBar({
    super.key,
    required this.post,
    this.onComment,
    this.iconSize = 16,
    this.gap = 14,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 10),
    this.alignment = MainAxisAlignment.start,
  });

  final CommunityPost post;
  final VoidCallback? onComment;
  final double iconSize;
  final double gap;
  final EdgeInsets padding;
  final MainAxisAlignment alignment;

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar> {
  static const _debounce = Duration(milliseconds: 280);

  bool _liked = false;
  bool _saved = false;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _likeBusy = false;
  bool _saveBusy = false;
  DateTime? _lastLikeAt;
  DateTime? _lastSaveAt;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void didUpdateWidget(covariant InteractionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (widget.post.id.isEmpty) return;
    try {
      final status = await SupabaseDBService.instance
          .fetchInteractionStatus(widget.post.id);
      if (!mounted) return;
      setState(() {
        _liked = status.liked;
        _saved = status.saved;
        _likeCount = status.likeCount;
        _commentCount = status.commentCount;
      });
    } catch (_) {}
  }

  bool _tooSoon(DateTime? last) {
    if (last == null) return false;
    return DateTime.now().difference(last) < _debounce;
  }

  Future<void> _toggleLike() async {
    if (_likeBusy || _tooSoon(_lastLikeAt)) return;
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    _lastLikeAt = DateTime.now();
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likeCount = (_likeCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
      _likeBusy = true;
    });
    try {
      await SupabaseDBService.instance.toggleLike(
        widget.post.id,
        AuthService.instance.currentUser?.id ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount = (_likeCount + (wasLiked ? 1 : -1)).clamp(0, 1 << 30);
      });
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Future<void> _toggleSave() async {
    if (_saveBusy || _tooSoon(_lastSaveAt)) return;
    final ok = await AuthScreen.require(context);
    if (!ok || !mounted) return;
    _lastSaveAt = DateTime.now();
    final wasSaved = _saved;
    setState(() {
      _saved = !wasSaved;
      _saveBusy = true;
    });
    try {
      await SupabaseDBService.instance.toggleSave(
        widget.post.id,
        AuthService.instance.currentUser?.id ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = wasSaved);
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  Future<void> _share() async {
    final quote = widget.post.quote.trim();
    final text = widget.post.text.trim();
    final pieces = <String>[
      if (quote.isNotEmpty) quote,
      if (text.isNotEmpty) text,
    ];
    if (pieces.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: pieces.join('\n\n')),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget button({
      required LineIconKind kind,
      required bool filled,
      required VoidCallback? onTap,
      String? count,
    }) {
      return Semantics(
        button: true,
        label: switch (kind) {
          LineIconKind.like => filled ? 'Unlike' : 'Like',
          LineIconKind.save => filled ? 'Unsave' : 'Save',
          LineIconKind.comment => 'Comment',
          LineIconKind.share => 'Share',
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.gap / 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LineIcon(kind, size: widget.iconSize, filled: filled),
                  if (count != null && count.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      count,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Row(
        mainAxisAlignment: widget.alignment,
        children: [
          button(
            kind: LineIconKind.like,
            filled: _liked,
            onTap: _toggleLike,
            count: _likeCount > 0 ? '$_likeCount' : null,
          ),
          button(
            kind: LineIconKind.save,
            filled: _saved,
            onTap: _toggleSave,
          ),
          button(
            kind: LineIconKind.comment,
            filled: false,
            onTap: widget.onComment,
            count: _commentCount > 0 ? '$_commentCount' : null,
          ),
          button(
            kind: LineIconKind.share,
            filled: false,
            onTap: _share,
          ),
        ],
      ),
    );
  }
}
