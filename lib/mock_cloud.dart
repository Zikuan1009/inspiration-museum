import 'package:inspiration_museum/auth_session.dart';
import 'package:inspiration_museum/chat_message.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/user_model.dart';

/// 演示用云端数据。接入 Firebase 后，这些列表由仓库层替换。
abstract final class MockCloud {
  static const selfId = AuthSession.demoUserId;

  static const self = UserModel(
    id: selfId,
    username: 'Zikuan',
    avatarUrl: '',
    bio: '把一天拆成网格，留白的那几格才是自己的。',
    followersCount: 128,
    followingCount: 36,
  );

  static const users = <UserModel>[
    UserModel(
      id: 'u_linyi',
      username: '林一',
      avatarUrl: '',
      bio: '负空间练习者。',
      followersCount: 420,
      followingCount: 18,
    ),
    UserModel(
      id: 'u_kato',
      username: 'Kato',
      avatarUrl: '',
      bio: '只拍逆光。',
      followersCount: 880,
      followingCount: 41,
    ),
    UserModel(
      id: 'u_chenyu',
      username: '陈禹',
      avatarUrl: '',
      bio: '休止符也是音符。',
      followersCount: 215,
      followingCount: 64,
    ),
    UserModel(
      id: 'u_mara',
      username: 'Mara',
      avatarUrl: '',
      bio: '量过每一道光井。',
      followersCount: 1024,
      followingCount: 9,
    ),
    UserModel(
      id: 'u_zhouye',
      username: '周野',
      avatarUrl: '',
      bio: '公差之内。',
      followersCount: 156,
      followingCount: 22,
    ),
  ];

  static UserModel userById(String id) {
    if (id == selfId) return self;
    return users.firstWhere((u) => u.id == id, orElse: () => self);
  }

  /// 当前用户自己发出的帖子（个人主页 POSTS）。
  static const ownPosts = <CommunityPost>[
    CommunityPost(
      id: 'mine_01',
      authorId: selfId,
      author: 'Zikuan',
      theme: '几何',
      themeEn: 'GEOMETRY',
      keywords: ['尺子', '网格', '清空'],
      text: '把桌面清空，只留一把尺子。剩下的空间突然开始说话。',
      quote: 'Keep one clear margin, and let a single decision be enough.',
      quoteAuthor: 'Original prompt',
      artworkSeed: 101,
      aspectRatio: 0.85,
    ),
    CommunityPost(
      id: 'mine_02',
      authorId: selfId,
      author: 'Zikuan',
      theme: '字体',
      themeEn: 'TYPOGRAPHY',
      keywords: ['字距', '基线', '信'],
      text: '今天把信件的字距拉开了 20。读起来反而更像在呼吸。',
      quote: 'Widen the line until the words are easier to follow.',
      quoteAuthor: 'Original prompt',
      artworkSeed: 118,
      aspectRatio: 1.15,
    ),
    CommunityPost(
      id: 'mine_03',
      authorId: selfId,
      author: 'Zikuan',
      theme: '建筑',
      themeEn: 'ARCHITECTURE',
      keywords: ['走廊', '门', '尺度'],
      text: '走廊尽头那扇门一直关着。关着，本身就是一句完整的话。',
      quote: 'Stand where the light enters and notice what the wall is doing.',
      quoteAuthor: 'Original prompt',
    ),
    CommunityPost(
      id: 'mine_04',
      authorId: selfId,
      author: 'Zikuan',
      theme: '哲学',
      themeEn: 'PHILOSOPHY',
      keywords: ['界限', '沉默', '命名'],
      text: '有些东西一说出来就变形了。先放在展厅里，让它自己站着。',
      quote: 'If the sentence keeps slipping, describe the situation instead.',
      quoteAuthor: 'Original prompt',
      artworkSeed: 133,
      aspectRatio: 0.72,
    ),
  ];

  /// 当前用户收藏的社区帖。
  static List<CommunityPost> get savedPosts => mockCommunityPosts
      .where((p) => const {'p01', 'p04', 'p07', 'p11'}.contains(p.id))
      .toList(growable: false);

  static const likesReceived = 142;

  static DateTime get _now => DateTime(2026, 9, 22, 13, 40);

  static List<ChatMessage> messagesWith(String peerId) {
    final mine = selfId;
    DateTime t(int minutesAgo) => _now.subtract(Duration(minutes: minutesAgo));

    switch (peerId) {
      case 'u_linyi':
        return [
          ChatMessage(
            id: 'm_l1',
            senderId: peerId,
            receiverId: mine,
            text: '你说的那种留白，我今天在地铁站看到了。',
            timestamp: t(180),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_l2',
            senderId: mine,
            receiverId: peerId,
            text: '哪一面墙？',
            timestamp: t(172),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_l3',
            senderId: peerId,
            receiverId: mine,
            text: '广告拆掉以后，露出一块没刷完的白。',
            timestamp: t(165),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_l4',
            senderId: mine,
            receiverId: peerId,
            text: '那一块比任何海报都完整。',
            timestamp: t(40),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_l5',
            senderId: peerId,
            receiverId: mine,
            text: '我拍了，但决定先不发。',
            timestamp: t(8),
            isRead: false,
          ),
        ];
      case 'u_kato':
        return [
          ChatMessage(
            id: 'm_k1',
            senderId: mine,
            receiverId: peerId,
            text: '逆光那张颗粒够了。',
            timestamp: t(1500),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_k2',
            senderId: peerId,
            receiverId: mine,
            text: '我重新冲了一版，更粗。人只剩下轮廓。',
            timestamp: t(1488),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_k3',
            senderId: mine,
            receiverId: peerId,
            text: '轮廓比五官更像他。',
            timestamp: t(1470),
            isRead: true,
          ),
        ];
      case 'u_chenyu':
        return [
          ChatMessage(
            id: 'm_c1',
            senderId: peerId,
            receiverId: mine,
            text: '休止符那条我转给老师看了。',
            timestamp: t(4200),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_c2',
            senderId: mine,
            receiverId: peerId,
            text: '老师怎么说？',
            timestamp: t(4188),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_c3',
            senderId: peerId,
            receiverId: mine,
            text: '他说：你终于听见没有声音的地方了。',
            timestamp: t(4100),
            isRead: true,
          ),
        ];
      case 'u_mara':
        return [
          ChatMessage(
            id: 'm_r1',
            senderId: peerId,
            receiverId: mine,
            text: '光井的尺寸我量了，只有 40 厘米。',
            timestamp: t(9000),
            isRead: true,
          ),
          ChatMessage(
            id: 'm_r2',
            senderId: mine,
            receiverId: peerId,
            text: '40 厘米已经足够让人闭嘴。',
            timestamp: t(8980),
            isRead: true,
          ),
        ];
      default:
        return const [];
    }
  }

  static List<ChatThread> threads() {
    const order = ['u_linyi', 'u_kato', 'u_chenyu', 'u_mara'];
    return [
      for (final id in order)
        ChatThread(
          peer: userById(id),
          lastMessage: messagesWith(id).last,
          unreadCount: messagesWith(id).where((m) => !m.isRead && m.senderId == id).length,
        ),
    ];
  }
}
