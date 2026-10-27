// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inspiration_museum/chat_message.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/inspiration_comment.dart';
import 'package:inspiration_museum/post_share.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/user_model.dart';
import 'package:inspiration_museum/user_stats_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ids returned by `rank-feed`. Empty or non-list payloads become an empty
/// list so the feed can keep its original order. This does not check that an
/// id exists; [placeRankedFirst] drops ids that are not in the public list.
List<String> rankIdsFromResponse(dynamic data) {
  if (data is! Map) return const [];
  final raw = data['ids'];
  if (raw is! List) return const [];
  return [
    for (final id in raw)
      if (id.toString().trim().isNotEmpty) id.toString().trim(),
  ];
}

/// 云端数据层：社区瀑布流 + 实时私信。
class SupabaseDBService {
  SupabaseDBService._();

  static final SupabaseDBService instance = SupabaseDBService._();

  SupabaseClient get _client => Supabase.instance.client;

  Timer? _interestTimer;

  /// 公开灵感，并一并拉下作者档案。
  Future<List<CommunityPost>> fetchPublicInspirations() async {
    final raw = await _client
        .from('inspirations')
        .select(
          '*, profiles!inspirations_author_id_fkey(id, username, avatar_url)',
        )
        .order('created_at', ascending: false);

    final posts = <CommunityPost>[];
    for (final json in raw) {
      if (json['is_private'] == true) continue;
      if (json['is_public'] == false) continue;
      posts.add(CommunityPost.fromSupabase(json));
    }
    return posts;
  }

  /// 按画像给首页排序。同一天命中缓存时不会再叫模型。失败则让首页保持原顺序。
  Future<List<String>> rankHomeFeed(String feedDate) async {
    final userId = _client.auth.currentUser?.id ?? '';
    if (userId.isEmpty || feedDate.isEmpty) return const [];
    final response = await _client.functions.invoke(
      'rank-feed',
      body: {'feed_date': feedDate},
    );
    return rankIdsFromResponse(response.data);
  }

  StreamController<List<Map<String, dynamic>>>? _messagesCtrl;
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSub;
  List<Map<String, dynamic>> _messagesSnapshot = const [];
  bool _messagesReady = false;
  int _messagesListeners = 0;

  void _ensureMessagesPipe() {
    if (_messagesCtrl != null) return;
    late final StreamController<List<Map<String, dynamic>>> controller;
    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        if (_messagesSub != null) return;
        _messagesSub = _client
            .from('messages')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: true)
            .listen(
              (rows) {
                _messagesSnapshot = rows;
                _messagesReady = true;
                if (!controller.isClosed) controller.add(rows);
              },
              onError: (Object error, StackTrace stack) {
                if (!controller.isClosed) controller.addError(error, stack);
              },
            );
      },
      onCancel: () async {
        if (_messagesListeners > 0) return;
        await _messagesSub?.cancel();
        _messagesSub = null;
        _messagesReady = false;
        _messagesSnapshot = const [];
      },
    );
    _messagesCtrl = controller;
  }

  /// 唯一一条官方 Realtime 长连接。每个新订阅者立刻拿到最近一次快照，包括空列表。
  Stream<List<Map<String, dynamic>>> _watchMessages() {
    _ensureMessagesPipe();
    final pipe = _messagesCtrl!;
    return Stream<List<Map<String, dynamic>>>.multi((listener) {
      _messagesListeners += 1;
      if (_messagesReady) {
        listener.add(List<Map<String, dynamic>>.from(_messagesSnapshot));
      }
      final sub = pipe.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = () async {
        await sub.cancel();
        _messagesListeners -= 1;
        if (_messagesListeners > 0) return;
        await _messagesSub?.cancel();
        _messagesSub = null;
        _messagesReady = false;
        _messagesSnapshot = const [];
      };
    });
  }

  /// 两人对话：官方 Realtime Stream，Dart 端过滤。空列表也是一次有效数据。
  Stream<List<Map<String, dynamic>>> getMessagesStream(
    String currentUserId,
    String peerId,
  ) {
    if (currentUserId.isEmpty || peerId.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }
    return _watchMessages().map((rows) {
      final mine = <Map<String, dynamic>>[];
      for (final row in rows) {
        final sender = row['sender_id']?.toString() ?? '';
        final receiver = row['receiver_id']?.toString() ?? '';
        final outgoing = sender == currentUserId && receiver == peerId;
        final incoming = sender == peerId && receiver == currentUserId;
        if (outgoing || incoming) mine.add(row);
      }
      return mine;
    });
  }

  final Map<String, UserModel> _peerCache = {};

  /// 会话列表：同一条官方 Realtime Stream，Dart 端分组。
  Stream<List<ChatSessionModel>> getChatSessionsStream(String currentUserId) {
    if (currentUserId.isEmpty) {
      return Stream<List<ChatSessionModel>>.value(const []);
    }
    return _watchMessages().asyncMap(
      (rows) => _assembleSessions(currentUserId, rows),
    );
  }

  Future<List<ChatSessionModel>> _assembleSessions(
    String currentUserId,
    List<Map<String, dynamic>> rows,
  ) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sender = row['sender_id']?.toString() ?? '';
      final receiver = row['receiver_id']?.toString() ?? '';
      final mine = sender == currentUserId;
      final theirs = receiver == currentUserId;
      if (!mine && !theirs) continue;
      final peerId = mine ? receiver : sender;
      if (peerId.isEmpty || peerId == currentUserId) continue;
      grouped.putIfAbsent(peerId, () => <Map<String, dynamic>>[]).add(row);
    }
    if (grouped.isEmpty) return const [];

    final missing = [
      for (final id in grouped.keys)
        if (!_peerCache.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) {
      try {
        final profiles = await _client
            .from('profiles')
            .select()
            .inFilter('id', missing);
        for (final row in profiles) {
          final user = UserModel.fromJson(row);
          if (user.id.isNotEmpty) _peerCache[user.id] = user;
        }
      } catch (error) {
        print('👉 [DEBUG] session profiles: $error');
      }
    }

    final sessions = <ChatSessionModel>[];
    grouped.forEach((peerId, sessionMessages) {
      // 同一对话里取时间最新的一条；时间相同则保留流里更靠后的那条。
      var latest = ChatMessage.fromSupabase(sessionMessages.first);
      for (final row in sessionMessages.skip(1)) {
        final message = ChatMessage.fromSupabase(row);
        if (!message.timestamp.isBefore(latest.timestamp)) latest = message;
      }
      final last = latest;
      final unreadCount = sessionMessages.where((msg) {
        final isMeReceiver = msg['receiver_id'] == currentUserId;
        final isUnread = msg['is_read'] == false || msg['is_read'] == null;
        return isMeReceiver && isUnread;
      }).length;
      DateTime? lastUnreadAt;
      for (final msg in sessionMessages) {
        final isMeReceiver = msg['receiver_id'] == currentUserId;
        final isUnread = msg['is_read'] == false || msg['is_read'] == null;
        if (!isMeReceiver || !isUnread) continue;
        final time = ChatMessage.fromSupabase(msg).timestamp;
        if (lastUnreadAt == null || time.isAfter(lastUnreadAt)) {
          lastUnreadAt = time;
        }
      }
      sessions.add(
        ChatSessionModel(
          peer:
              _peerCache[peerId] ??
              UserModel(
                id: peerId,
                username: 'ANON',
                avatarUrl: '',
                bio: '',
                followersCount: 0,
                followingCount: 0,
              ),
          lastMessage: PostShareLink.preview(last.text),
          lastAt: last.timestamp,
          unreadCount: unreadCount,
          lastUnreadAt: lastUnreadAt,
        ),
      );
    });
    sessions.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return sessions;
  }

  Future<List<ChatSessionModel>> fetchChatSessions(String currentUserId) {
    return getChatSessionsStream(currentUserId).first;
  }

  Future<void> markMessagesAsRead(String currentUserId, String peerId) async {
    if (currentUserId.isEmpty || peerId.isEmpty) return;
    await _client
        .from('messages')
        .update({'is_read': true})
        .eq('receiver_id', currentUserId)
        .eq('sender_id', peerId);
  }

  Future<void> sendMessage(String senderId, String receiverId, String content) {
    return _client.from('messages').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'is_read': false,
    });
  }

  /// 按 8 位馆员号精确查找，只匹配 `profiles.app_id`，绝不查 `id`。
  Future<UserModel?> searchUserByAppId(String query) async {
    if (query.trim().isEmpty) return null;
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('app_id', query.trim())
          .maybeSingle();
      if (data == null) return null;
      final model = UserModel.fromJson(data);
      if (model.id.isNotEmpty) _peerCache[model.id] = model;
      return model;
    } catch (_) {
      rethrow;
    }
  }

  Future<UserModel?> fetchProfile(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      final model = UserModel.fromJson(data);
      if (model.id.isNotEmpty) _peerCache[model.id] = model;
      return model;
    } catch (_) {
      rethrow;
    }
  }

  /// 用当前登录用户的系统 UUID 查 `profiles.id`，返回含 `app_id` 的完整行。
  /// 每次都打网络，不走启动缓存。查空时等 500ms 再试一次。
  Future<UserModel?> getCurrentUserProfile() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return null;

    Future<Map<String, dynamic>?> lookup() async {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle();
      return data;
    }

    try {
      var data = await lookup();
      if (data == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        data = await lookup();
      }
      if (data == null) return null;
      return UserModel.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> fetchCurrentUserProfile() => getCurrentUserProfile();

  Future<UserModel?> fetchCurrentProfile() => getCurrentUserProfile();

  bool _isConflict(Object error) {
    if (error is PostgrestException) {
      final code = (error.code ?? '').toLowerCase();
      final message = error.message.toLowerCase();
      return code == '23505' ||
          code == '409' ||
          message.contains('duplicate') ||
          message.contains('already exists') ||
          message.contains('unique');
    }
    final text = error.toString().toLowerCase();
    return text.contains('409') ||
        text.contains('duplicate') ||
        text.contains('23505');
  }

  Future<void> followUser(String targetUserId) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null || me.isEmpty || me == targetUserId) return;
    final already = await checkIsFollowing(targetUserId);
    if (already) return;
    try {
      await _client.from('follows').insert({
        'follower_id': me,
        'following_id': targetUserId,
      });
    } catch (error) {
      if (_isConflict(error)) return;
      rethrow;
    }
  }

  Future<void> unfollowUser(String targetUserId) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null || me.isEmpty) return;
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', me)
        .eq('following_id', targetUserId);
  }

  Future<bool> checkIsFollowing(String targetUserId) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null || me.isEmpty || targetUserId.isEmpty) return false;
    final row = await _client
        .from('follows')
        .select()
        .eq('follower_id', me)
        .eq('following_id', targetUserId)
        .maybeSingle();
    return row != null;
  }

  /// 谁关注了 [userId]。只读档案，不提供修改入口。
  Future<List<UserModel>> fetchFollowers(String userId) {
    return _fetchFollowList(
      userId: userId,
      linkColumn: 'follower_id',
      ownerColumn: 'following_id',
    );
  }

  /// [userId] 关注了谁。只读档案，不提供修改入口。
  Future<List<UserModel>> fetchFollowing(String userId) {
    return _fetchFollowList(
      userId: userId,
      linkColumn: 'following_id',
      ownerColumn: 'follower_id',
    );
  }

  Future<List<UserModel>> _fetchFollowList({
    required String userId,
    required String linkColumn,
    required String ownerColumn,
  }) async {
    if (userId.isEmpty) return const [];
    final links = await _client
        .from('follows')
        .select(linkColumn)
        .eq(ownerColumn, userId);
    final ids = <String>[];
    final seen = <String>{};
    for (final row in links) {
      final id = row[linkColumn]?.toString().trim() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return const [];
    final raw = await _client
        .from('profiles')
        .select(
          'id, username, avatar_url, bio, app_id, age, gender, location, school',
        )
        .inFilter('id', ids);
    final byId = <String, UserModel>{
      for (final row in raw)
        if (row['id'] != null) row['id'].toString(): UserModel.fromJson(row),
    };
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 按 id 取一篇公开帖。私密帖只对作者本人返回。
  Future<CommunityPost?> fetchInspiration(String postId) async {
    if (!_isCloudInspirationId(postId)) return null;
    final row = await _client
        .from('inspirations')
        .select()
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return null;
    if (row['is_private'] == true && row['author_id']?.toString() != _uid) {
      return null;
    }
    return CommunityPost.fromSupabase(row);
  }

  /// 只按作者取帖子，不嵌套 profiles。主页上已经有这个人的资料。
  Future<List<CommunityPost>> fetchUserInspirations(String targetUserId) async {
    final userId = targetUserId.trim();
    if (userId.isEmpty || userId.startsWith('vault_')) return const [];
    final raw = await _client
        .from('inspirations')
        .select()
        .eq('author_id', userId)
        .order('created_at', ascending: false);
    final me = _uid;
    return [
      for (final json in raw)
        if (json['is_private'] != true || json['author_id']?.toString() == me)
          CommunityPost.fromSupabase(json),
    ];
  }

  /// 发布到云端 `inspirations`。图片先上传到 `post_images`，文件名用 UUID，避免覆盖。
  /// 参数用 [XFile]，这样 Web 上不必依赖 `dart:io` 的 File。
  Future<void> createPost(
    String authorId,
    String textContent,
    XFile? imageFile, {
    String title = '',
    String quote = '',
    List<String> keywords = const [],
    bool isPrivate = false,
    String? imageUrl,
  }) async {
    final author = authorId.trim();
    final text = CommunityPost.packUserText(title, textContent);
    if (author.isEmpty) {
      throw StateError('Sign in before publishing.');
    }
    if (text.isEmpty &&
        imageFile == null &&
        (imageUrl?.trim().isEmpty ?? true)) {
      throw StateError('There is nothing to publish.');
    }

    var uploadedUrl = imageUrl?.trim() ?? '';
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isNotEmpty) {
        final ext = _fileExtension(imageFile.name);
        final path = '$author/${_randomUuid()}.$ext';
        await _client.storage
            .from('post_images')
            .uploadBinary(
              path,
              Uint8List.fromList(bytes),
              fileOptions: FileOptions(
                upsert: false,
                contentType: _contentType(ext),
              ),
            );
        uploadedUrl = _client.storage.from('post_images').getPublicUrl(path);
      }
    }

    final inserted = await _client
        .from('inspirations')
        .insert({
          'author_id': author,
          'user_text': text,
          'quote': CommunityPost.unwrapQuotes(quote),
          'keywords': keywords,
          'is_private': isPrivate,
          if (uploadedUrl.isNotEmpty) 'image_url': uploadedUrl,
        })
        .select('id')
        .maybeSingle();
    final createdId = inserted?['id']?.toString() ?? '';
    if (createdId.isNotEmpty) {
      unawaited(
        _noteInterest(
          kind: 'reflection',
          sourceId: createdId,
          excerpt: _interestExcerpt(
            text,
            CommunityPost.unwrapQuotes(quote),
            keywords,
          ),
        ),
      );
    }
  }

  Future<int> _exactCount(
    Future<PostgrestResponse<List<Map<String, dynamic>>>> query,
  ) async {
    final response = await query;
    return response.count;
  }

  /// 只按真实列做 exact count，不查 follows / likes 的 id。
  Future<UserStatsModel> fetchUserStats(String userId) async {
    if (userId.isEmpty) return const UserStatsModel();

    Future<int> safe(Future<int> task) async {
      try {
        return await task;
      } catch (error) {
        print('👉 [DEBUG] stats count: $error');
        return 0;
      }
    }

    final followers = await safe(
      _exactCount(
        _client
            .from('follows')
            .select('follower_id')
            .eq('following_id', userId)
            .count(CountOption.exact),
      ),
    );
    final following = await safe(
      _exactCount(
        _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', userId)
            .count(CountOption.exact),
      ),
    );
    final likes = await safe(
      _exactCount(
        _client
            .from('likes')
            .select('inspiration_id')
            .eq('user_id', userId)
            .count(CountOption.exact),
      ),
    );
    final posts = await safe(
      _exactCount(
        _client
            .from('inspirations')
            .select('id')
            .eq('author_id', userId)
            .count(CountOption.exact),
      ),
    );

    return UserStatsModel(
      posts: posts,
      likes: likes,
      followers: followers,
      following: following,
    );
  }

  Future<({int posts, int likes, int followers, int following})>
  fetchProfileStats(String userId) async {
    final stats = await fetchUserStats(userId);
    return (
      posts: stats.posts,
      likes: stats.likes,
      followers: stats.followers,
      following: stats.following,
    );
  }

  /// 关注关系或点赞一变，就重新精确计数。页面只在 initState 里订阅一次。
  Stream<UserStatsModel> watchUserStats(String userId) {
    if (userId.isEmpty) {
      return Stream<UserStatsModel>.value(const UserStatsModel());
    }

    late final StreamController<UserStatsModel> controller;
    StreamSubscription<List<Map<String, dynamic>>>? followsSub;
    StreamSubscription<List<Map<String, dynamic>>>? likesSub;
    Timer? debounce;
    var listeners = 0;

    Future<void> publish() async {
      try {
        final stats = await fetchUserStats(userId);
        if (!controller.isClosed) controller.add(stats);
      } catch (error) {
        print('👉 [DEBUG] watch stats: $error');
      }
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 180), () {
        publish();
      });
    }

    controller = StreamController<UserStatsModel>.broadcast(
      onListen: () {
        listeners += 1;
        if (followsSub != null) {
          publish();
          return;
        }
        publish();
        followsSub = _client
            .from('follows')
            .stream(primaryKey: ['follower_id', 'following_id'])
            .listen(
              (_) => schedule(),
              onError: (Object error, StackTrace _) {
                print('👉 [DEBUG] follows stream: $error');
              },
            );
        likesSub = _client
            .from('likes')
            .stream(primaryKey: ['user_id', 'inspiration_id'])
            .listen(
              (_) => schedule(),
              onError: (Object error, StackTrace _) {
                print('👉 [DEBUG] likes stream: $error');
              },
            );
      },
      onCancel: () async {
        listeners -= 1;
        if (listeners > 0) return;
        debounce?.cancel();
        await followsSub?.cancel();
        await likesSub?.cancel();
        followsSub = null;
        likesSub = null;
      },
    );
    return controller.stream;
  }

  Future<List<CommunityPost>> fetchSavedInspirations(String userId) async {
    if (userId.isEmpty) return const [];
    final saves = await _client
        .from('saves')
        .select('inspiration_id')
        .eq('user_id', userId);
    final ids = <String>[
      for (final row in saves)
        if ((row['inspiration_id']?.toString() ?? '').isNotEmpty)
          row['inspiration_id'].toString(),
    ];
    if (ids.isEmpty) return const [];
    final raw = await _client
        .from('inspirations')
        .select(
          '*, profiles!inspirations_author_id_fkey(id, username, avatar_url)',
        )
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return [for (final json in raw) CommunityPost.fromSupabase(json)];
  }

  static List<String> _parseThemeList(dynamic raw) {
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

  Future<({bool completed, List<String> themes})> fetchOnboardingState(
    String userId,
  ) async {
    if (userId.isEmpty) {
      return (completed: false, themes: const <String>[]);
    }
    final selectedIds = await fetchUserSelectedThemes(userId);
    if (selectedIds.isNotEmpty) {
      return (completed: true, themes: selectedIds);
    }
    final row = await _client
        .from('profiles')
        .select('selected_themes')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      return (completed: false, themes: const <String>[]);
    }
    final themes = _parseThemeList(row['selected_themes']);
    return (completed: themes.isNotEmpty, themes: themes);
  }

  String? get _uid => AuthService.instance.currentUser?.id;

  static final _cloudUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// 本地卡片（`vault_...`）和非法 ID 不能拿去查 UUID 列。
  bool _isCloudInspirationId(String id) {
    final value = id.trim();
    if (value.isEmpty || value.startsWith('vault_')) return false;
    return _cloudUuid.hasMatch(value);
  }

  /// 查 `likes`：已有则删除，没有则插入。断网只记录，不抛到界面。
  Future<void> toggleLike(String postId, String userId) async {
    try {
      final actor = userId.trim();
      if (actor.isEmpty || !_isCloudInspirationId(postId)) return;
      final existing = await _client
          .from('likes')
          .select('user_id')
          .eq('user_id', actor)
          .eq('inspiration_id', postId)
          .maybeSingle();
      if (existing != null) {
        await _client
            .from('likes')
            .delete()
            .eq('user_id', actor)
            .eq('inspiration_id', postId);
        unawaited(_clearInterest('like', postId));
        return;
      }
      await _client.from('likes').insert({
        'user_id': actor,
        'inspiration_id': postId,
      });
      unawaited(_noteInterestFromPost('like', postId));
    } catch (error) {
      if (_isConflict(error)) return;
      print('👉 [DEBUG] toggleLike: $error');
    }
  }

  /// 查 `saves`：已有则删除，没有则插入。断网只记录，不抛到界面。
  Future<void> toggleSave(String postId, String userId) async {
    try {
      final actor = userId.trim();
      if (actor.isEmpty || !_isCloudInspirationId(postId)) return;
      final existing = await _client
          .from('saves')
          .select('user_id')
          .eq('user_id', actor)
          .eq('inspiration_id', postId)
          .maybeSingle();
      if (existing != null) {
        await _client
            .from('saves')
            .delete()
            .eq('user_id', actor)
            .eq('inspiration_id', postId);
        unawaited(_clearInterest('save', postId));
        return;
      }
      await _client.from('saves').insert({
        'user_id': actor,
        'inspiration_id': postId,
      });
      unawaited(_noteInterestFromPost('save', postId));
    } catch (error) {
      if (_isConflict(error)) return;
      print('👉 [DEBUG] toggleSave: $error');
    }
  }

  /// 把这篇灵感作为一条私信发给站内好友。
  Future<bool> sharePostToFriend(
    String postId,
    String currentUserId,
    String receiverId,
  ) async {
    try {
      final sender = currentUserId.trim();
      final receiver = receiverId.trim();
      if (sender.isEmpty ||
          receiver.isEmpty ||
          sender == receiver ||
          !_isCloudInspirationId(postId)) {
        return false;
      }
      await _client.from('messages').insert({
        'sender_id': sender,
        'receiver_id': receiver,
        'content': PostShareLink.encode(postId),
        'is_read': false,
      });
      return true;
    } catch (error) {
      print('👉 [DEBUG] sharePostToFriend: $error');
      return false;
    }
  }

  /// 公开的只读页。不用 text/html，避免存储把页面改成源码。
  Future<String> publishSharePage(String postId, Uint8List page) async {
    final me = _uid ?? '';
    if (me.isEmpty || !_isCloudInspirationId(postId) || page.isEmpty) {
      throw StateError('Sign in before sharing.');
    }
    final path = '$me/share/$postId.xhtml';
    await _client.storage
        .from('post_images')
        .uploadBinary(
          path,
          page,
          fileOptions: const FileOptions(
            upsert: true,
            cacheControl: '60',
            contentType: 'application/xhtml+xml',
          ),
        );
    return _client.storage.from('post_images').getPublicUrl(path);
  }

  /// 外部分享记一次转发。已转发过则保持原记录。
  Future<void> recordRepost(String postId, String userId) async {
    try {
      final actor = userId.trim();
      if (actor.isEmpty || !_isCloudInspirationId(postId)) return;
      await _client.from('reposts').insert({
        'user_id': actor,
        'inspiration_id': postId,
      });
    } catch (error) {
      if (_isConflict(error)) return;
      print('👉 [DEBUG] recordRepost: $error');
    }
  }

  Future<void> toggleRepost(
    String inspirationId,
    bool isCurrentlyReposted,
  ) async {
    final me = _uid;
    if (me == null || me.isEmpty || !_isCloudInspirationId(inspirationId)) {
      return;
    }
    if (isCurrentlyReposted) {
      await _client
          .from('reposts')
          .delete()
          .eq('user_id', me)
          .eq('inspiration_id', inspirationId);
      return;
    }
    try {
      await _client.from('reposts').insert({
        'user_id': me,
        'inspiration_id': inspirationId,
      });
    } catch (error) {
      if (_isConflict(error)) return;
      rethrow;
    }
  }

  final ValueNotifier<int> deletedPosts = ValueNotifier<int>(0);
  final Set<String> _deletedPostIds = {};

  bool isPostDeleted(String postId) => _deletedPostIds.contains(postId);

  /// 删掉作者自己的帖子，并清掉挂在上面的互动，避免外键拦住删除。
  Future<void> deletePost(String postId) async {
    if (!_isCloudInspirationId(postId)) {
      throw StateError('This post cannot be deleted.');
    }
    final me = _uid ?? '';
    if (me.isEmpty) throw StateError('Sign in before deleting.');
    try {
      await _deleteInspiration(postId, me);
    } catch (error) {
      final message = error.toString().toLowerCase();
      final blocked =
          message.contains('foreign key') || message.contains('23503');
      if (!blocked) rethrow;
      await _deletePostRelations(postId);
      await _deleteInspiration(postId, me);
    }
    final check = await _client
        .from('inspirations')
        .select('id')
        .eq('id', postId)
        .maybeSingle();
    if (check != null) throw StateError('The post was not deleted.');
    _deletedPostIds.add(postId);
    _postTextOverrides.remove(postId);
    _postImageOverrides.remove(postId);
    deletedPosts.value++;
  }

  Future<void> _deleteInspiration(String postId, String me) async {
    final rows = await _client
        .from('inspirations')
        .delete()
        .eq('id', postId)
        .eq('author_id', me)
        .select('id');
    if (rows.isEmpty) throw StateError('No permission to delete this post.');
  }

  Future<void> _deletePostRelations(String postId) async {
    try {
      final comments = await _client
          .from('comments')
          .select('id')
          .eq('inspiration_id', postId);
      final ids = [
        for (final row in comments)
          if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(),
      ];
      if (ids.isNotEmpty) {
        await _client
            .from('comment_likes')
            .delete()
            .inFilter('comment_id', ids);
      }
    } catch (error) {
      print('👉 [DEBUG] delete comment_likes: $error');
    }
    for (final table in ['comments', 'likes', 'saves', 'reposts']) {
      try {
        await _client.from(table).delete().eq('inspiration_id', postId);
      } catch (error) {
        print('👉 [DEBUG] delete $table: $error');
      }
    }
  }

  final Map<String, String> _postImageOverrides = {};
  final Map<
    String,
    ({
      String title,
      String body,
      bool isPrivate,
      List<String>? keywords,
      String? quote,
    })
  >
  _postTextOverrides = {};

  /// 这次会话里刚换上、已经确认写进数据库的图片地址。
  String? latestPostImage(String postId) {
    final saved = _postImageOverrides[postId];
    if (saved == null || saved.isEmpty) return null;
    return saved;
  }

  CommunityPost withLocalEdits(CommunityPost post) {
    var next = post;
    final text = _postTextOverrides[post.id];
    if (text != null) {
      next = next.copyWith(
        title: text.title,
        text: text.body,
        isPrivate: text.isPrivate,
        keywords: text.keywords,
        quote: text.quote,
      );
    }
    final image = _postImageOverrides[post.id];
    if (image != null && image.isNotEmpty) {
      next = next.copyWith(imagePath: image);
    }
    return next;
  }

  /// 改标题、正文和是否私密，写回原来的帖子。
  Future<void> updatePostText({
    required String postId,
    required String title,
    required String body,
    required bool isPrivate,
    List<String>? keywords,
    String? quote,
  }) async {
    if (!_isCloudInspirationId(postId)) {
      throw StateError('This post cannot be edited.');
    }
    final me = _uid ?? '';
    if (me.isEmpty) throw StateError('Sign in before editing.');
    final packed = CommunityPost.packUserText(title, body);
    final values = <String, dynamic>{
      'user_text': packed,
      'is_private': isPrivate,
      'keywords': ?keywords,
      if (quote != null) 'quote': CommunityPost.unwrapQuotes(quote),
    };
    final rows = await _client
        .from('inspirations')
        .update(values)
        .eq('id', postId)
        .eq('author_id', me)
        .select('user_text, is_private');
    if (rows.isEmpty) throw StateError('No permission to edit this post.');
    final stored = rows.first['user_text']?.toString() ?? '';
    if (stored != packed) {
      throw StateError('The text was not saved on the post.');
    }
    final check = await _client
        .from('inspirations')
        .select('user_text')
        .eq('id', postId)
        .maybeSingle();
    final readBack = check?['user_text']?.toString() ?? '';
    if (readBack != packed) {
      throw StateError('The text was not saved on the post.');
    }
    _postTextOverrides[postId] = (
      title: title.trim(),
      body: body.trim(),
      isPrivate: isPrivate,
      keywords: keywords,
      quote: quote?.trim(),
    );
  }

  /// 图已经在 `post_images` 里，只把地址写回这篇帖子。
  Future<String> attachUploadedImage(String postId, String imageUrl) async {
    if (!_isCloudInspirationId(postId)) return '';
    final me = _uid ?? '';
    if (me.isEmpty) throw StateError('Sign in before replacing the image.');
    final url = imageUrl.trim();
    if (!url.startsWith('http')) return '';
    final saved = await _persistPostImage(postId, me, url);
    _postImageOverrides[postId] = saved;
    return saved;
  }

  /// 上传到 `post_images/{postId}/...`，再把公开地址写回帖子。
  /// 使用 [XFile]，Web / iOS / Android 都能读字节。
  ///
  /// 只改本地预览不够：Supabase 在没有更新到任何行时也不会报错，
  /// 所以这里写完会再读一次，确认 `image_url` 已经是新地址。
  Future<String> updatePostImage(String postId, XFile imageFile) async {
    if (!_isCloudInspirationId(postId)) return '';
    final me = _uid ?? '';
    if (me.isEmpty) {
      throw StateError('Sign in before replacing the image.');
    }
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) return '';
    final ext = _fileExtension(imageFile.name);
    final path = '$postId/${_randomUuid()}.$ext';
    await _client.storage
        .from('post_images')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            upsert: false,
            contentType: _contentType(ext),
          ),
        );
    final publicUrl = _client.storage.from('post_images').getPublicUrl(path);
    final saved = await _persistPostImage(postId, me, publicUrl);
    _postImageOverrides[postId] = saved;
    return saved;
  }

  Future<String> _persistPostImage(
    String postId,
    String me,
    String publicUrl,
  ) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _updatePostImageColumns(postId, me, {
        'image_url': publicUrl,
        'image_path': publicUrl,
      });
    } catch (error) {
      final message = error.toString();
      if (!message.contains('image_path')) rethrow;
      rows = await _updatePostImageColumns(postId, me, {
        'image_url': publicUrl,
      });
    }
    if (_savedImageUrl(rows).isEmpty) {
      rows = await _updatePostImageColumns(postId, me, {
        'image_url': publicUrl,
      });
    }
    if (_savedImageUrl(rows).isEmpty) {
      throw StateError(
        'The image uploaded, but it was not written onto the post.',
      );
    }
    final check = await _client
        .from('inspirations')
        .select('image_url')
        .eq('id', postId)
        .maybeSingle();
    final stored = check?['image_url']?.toString().trim() ?? '';
    if (stored != publicUrl) {
      throw StateError('The image was not saved on the post.');
    }
    return stored;
  }

  Future<List<Map<String, dynamic>>> _updatePostImageColumns(
    String postId,
    String me,
    Map<String, dynamic> values,
  ) async {
    final mine = await _client
        .from('inspirations')
        .update(values)
        .eq('id', postId)
        .eq('author_id', me)
        .select('image_url');
    if (mine.isNotEmpty) return mine;
    return _client
        .from('inspirations')
        .update(values)
        .eq('id', postId)
        .select('image_url');
  }

  String _savedImageUrl(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    return rows.first['image_url']?.toString().trim() ?? '';
  }

  Stream<Map<String, dynamic>> getPostInteractionsStream(
    String postId,
    String currentUserId,
  ) {
    const empty = <String, dynamic>{
      'likeCount': 0,
      'saveCount': 0,
      'commentCount': 0,
      'repostCount': 0,
      'liked': false,
      'saved': false,
      'reposted': false,
    };
    if (!_isCloudInspirationId(postId)) {
      return Stream<Map<String, dynamic>>.value(empty);
    }

    late final StreamController<Map<String, dynamic>> controller;
    RealtimeChannel? channel;
    Timer? debounce;
    var listeners = 0;

    Future<int> countOf(String table) {
      return _exactCount(
        _client
            .from(table)
            .select('inspiration_id')
            .eq('inspiration_id', postId)
            .count(CountOption.exact),
      );
    }

    Future<bool> mine(String table) async {
      if (currentUserId.isEmpty) return false;
      final row = await _client
          .from(table)
          .select('user_id')
          .eq('user_id', currentUserId)
          .eq('inspiration_id', postId)
          .maybeSingle();
      return row != null;
    }

    Future<void> publish() async {
      try {
        final results = await Future.wait<Object>([
          countOf('likes'),
          countOf('saves'),
          countOf('comments'),
          countOf('reposts'),
          mine('likes'),
          mine('saves'),
          mine('reposts'),
        ]);
        if (controller.isClosed) return;
        controller.add({
          'likeCount': results[0] as int,
          'saveCount': results[1] as int,
          'commentCount': results[2] as int,
          'repostCount': results[3] as int,
          'liked': results[4] as bool,
          'saved': results[5] as bool,
          'reposted': results[6] as bool,
        });
      } catch (error) {
        print('👉 [DEBUG] post interactions: $error');
        if (!controller.isClosed) controller.add(empty);
      }
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 160), publish);
    }

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        listeners += 1;
        publish();
        if (channel != null) return;
        void onChange(PostgresChangePayload _) => schedule();
        final next = _client.channel('post-interactions-$postId');
        for (final table in ['likes', 'saves', 'comments', 'reposts']) {
          next.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'inspiration_id',
              value: postId,
            ),
            callback: onChange,
          );
        }
        channel = next.subscribe();
      },
      onCancel: () async {
        listeners -= 1;
        if (listeners > 0) return;
        debounce?.cancel();
        final current = channel;
        channel = null;
        if (current != null) {
          await _client.removeChannel(current);
        }
      },
    );
    return controller.stream;
  }

  Future<({bool liked, bool saved, int likeCount, int commentCount})>
  fetchInteractionStatus(String inspirationId) async {
    if (!_isCloudInspirationId(inspirationId)) {
      return (liked: false, saved: false, likeCount: 0, commentCount: 0);
    }
    final me = _uid;
    var liked = false;
    var saved = false;
    var likeCount = 0;
    var commentCount = 0;
    try {
      final likes = await _client
          .from('likes')
          .select('user_id')
          .eq('inspiration_id', inspirationId);
      likeCount = likes.length;
      if (me != null) {
        liked = likes.any((row) => row['user_id']?.toString() == me);
      }
    } catch (error) {
      print('👉 [DEBUG] likes status: $error');
    }
    try {
      final comments = await _client
          .from('comments')
          .select()
          .eq('inspiration_id', inspirationId);
      commentCount = comments.length;
    } catch (error) {
      print('👉 [DEBUG] comments status: $error');
    }
    if (me != null && me.isNotEmpty) {
      try {
        final row = await _client
            .from('saves')
            .select()
            .eq('user_id', me)
            .eq('inspiration_id', inspirationId)
            .maybeSingle();
        saved = row != null;
      } catch (error) {
        print('👉 [DEBUG] saves status: $error');
      }
    }
    return (
      liked: liked,
      saved: saved,
      likeCount: likeCount,
      commentCount: commentCount,
    );
  }

  Future<void> addComment(
    String postId,
    String userId,
    String text, {
    String? parentId,
  }) async {
    final author = userId.trim().isNotEmpty ? userId.trim() : (_uid ?? '');
    final body = text.trim();
    if (author.isEmpty || body.isEmpty || !_isCloudInspirationId(postId)) {
      return;
    }
    final parent = parentId?.trim() ?? '';
    await _client.from('comments').insert({
      'user_id': author,
      'inspiration_id': postId,
      'content': body,
      if (parent.isNotEmpty) 'parent_id': parent,
    });
  }

  /// 查 `comment_likes`：已有则删除，没有则插入。
  Future<void> toggleCommentLike(String commentId, String userId) async {
    try {
      final actor = userId.trim();
      final id = commentId.trim();
      if (actor.isEmpty || id.isEmpty) return;
      final existing = await _client
          .from('comment_likes')
          .select('user_id')
          .eq('user_id', actor)
          .eq('comment_id', id)
          .maybeSingle();
      if (existing != null) {
        await _client
            .from('comment_likes')
            .delete()
            .eq('user_id', actor)
            .eq('comment_id', id);
        return;
      }
      await _client.from('comment_likes').insert({
        'user_id': actor,
        'comment_id': id,
      });
    } catch (error) {
      if (_isConflict(error)) return;
      print('👉 [DEBUG] toggleCommentLike: $error');
    }
  }

  /// 评论流。`stream()` 不能联表，所以用 channel 触发全量查询。
  /// `profiles` 必须写明 `comments_user_id_fkey`，否则和 `comment_likes` 的关系冲突。
  Stream<List<Map<String, dynamic>>> getCommentsWithProfilesStream(
    String postId,
  ) {
    if (!_isCloudInspirationId(postId)) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    late final StreamController<List<Map<String, dynamic>>> controller;
    RealtimeChannel? channel;
    Timer? debounce;
    var listeners = 0;

    Future<void> publish() async {
      try {
        final data = await _client
            .from('comments')
            .select(
              '*, profiles!comments_user_id_fkey(id, username, avatar_url), comment_likes(user_id)',
            )
            .eq('inspiration_id', postId)
            .order('created_at', ascending: true);
        if (controller.isClosed) return;
        controller.add([
          for (final row in data) Map<String, dynamic>.from(row),
        ]);
      } catch (error) {
        print('👉 [DEBUG] comments stream: $error');
        if (!controller.isClosed) controller.addError(error);
      }
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 160), publish);
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        listeners += 1;
        publish();
        if (channel != null) return;
        void onChange(PostgresChangePayload _) => schedule();
        final next = _client.channel('comments-$postId');
        next.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'inspiration_id',
            value: postId,
          ),
          callback: onChange,
        );
        next.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comment_likes',
          callback: onChange,
        );
        channel = next.subscribe();
      },
      onCancel: () async {
        listeners -= 1;
        if (listeners > 0) return;
        debounce?.cancel();
        final current = channel;
        channel = null;
        if (current != null) {
          await _client.removeChannel(current);
        }
      },
    );
    return controller.stream;
  }

  Future<List<InspirationComment>> fetchComments(String inspirationId) async {
    if (!_isCloudInspirationId(inspirationId)) return const [];
    final raw = await _client
        .from('comments')
        .select('*, profiles(id, username, avatar_url)')
        .eq('inspiration_id', inspirationId)
        .order('created_at', ascending: true);
    return [for (final json in raw) InspirationComment.fromSupabase(json)];
  }

  Future<void> updateProfile(
    UserModel updatedUser, {
    XFile? newAvatarFile,
  }) async {
    final me = AuthService.instance.currentUser?.id;
    if (me == null || me.isEmpty) return;

    var avatarUrl = updatedUser.avatarUrl.trim();
    if (newAvatarFile != null) {
      final bytes = await newAvatarFile.readAsBytes();
      if (bytes.isNotEmpty) {
        final ext = _fileExtension(newAvatarFile.name);
        final path = '$me/${_uuid()}.$ext';
        await _client.storage
            .from('avatars')
            .uploadBinary(
              path,
              Uint8List.fromList(bytes),
              fileOptions: FileOptions(
                upsert: true,
                contentType: _contentType(ext),
              ),
            );
        avatarUrl = _client.storage.from('avatars').getPublicUrl(path);
      }
    }

    await _client
        .from('profiles')
        .update({
          'username': updatedUser.username.trim(),
          'bio': updatedUser.bio.trim(),
          'avatar_url': avatarUrl,
          'age': updatedUser.age,
          'gender': updatedUser.gender.trim(),
          'location': updatedUser.location.trim(),
          'school': updatedUser.school.trim(),
          'hobbies': updatedUser.hobbies.trim(),
          'personality': updatedUser.personality.trim(),
          'occupation': updatedUser.occupation.trim(),
          'letter_forms': updatedUser.letterForms,
          'breakout_ratio': updatedUser.breakoutRatio.clamp(0, 100),
        })
        .eq('id', me);
    await _refreshUpcomingLetter(me);
  }

  /// 资料变了之后，丢掉还没被打开的明天那封，按新资料重写。今天已经展示的信不动。
  Future<void> refreshUpcomingLetter(String userId) =>
      _refreshUpcomingLetter(userId);

  Future<void> _refreshUpcomingLetter(String userId) async {
    final date = _dateKey(DateTime.now().add(const Duration(days: 1)));
    try {
      await _client
          .from('daily_letters')
          .delete()
          .eq('user_id', userId)
          .eq('letter_date', date);
    } catch (_) {}
    unawaited(prepareUpcomingLetter());
  }

  String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = (now.hashCode ^ identityHashCode(this))
        .toUnsigned(32)
        .toRadixString(16);
    return '$now$rand';
  }

  String _randomUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'jpg';
    final ext = parts.last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (ext == 'jpeg' ||
        ext == 'jpg' ||
        ext == 'png' ||
        ext == 'webp' ||
        ext == 'gif') {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
    return 'jpg';
  }

  String _contentType(String ext) {
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  /// 每个用户每个自然日只取一封信。关掉再打开仍是同一封，直到日期变了才重新抽取。
  /// 这里只读已经写好的信，不等模型。没有准备好时立刻用原来的随机馆藏。
  Future<DailyPush> fetchDailyPush(String userId) async {
    if (userId.isEmpty) return DailyPush.fallback;
    final today = _todayKey();
    final cached = await _readCachedLetter(userId, today);
    final remote = cached == null
        ? await _readRemoteLetter(userId, today)
        : null;
    final prepared = cached == null && remote == null
        ? await _readPreparedLetter(userId, today)
        : null;
    Map<String, dynamic>? randomCatalog;
    var randomUnavailable = false;
    if (cached == null && remote == null && prepared == null) {
      try {
        final response = await _client.rpc(
          'get_random_daily_letter',
          params: {'target_user_id': userId},
        );
        randomCatalog = _asMap(response);
      } catch (_) {
        randomUnavailable = true;
      }
    }
    final choice = resolveDailyLetter(
      cached: cached,
      remote: remote,
      prepared: prepared,
      randomCatalog: randomCatalog,
      randomUnavailable: randomUnavailable,
    );
    if (choice.source == DailyLetterSource.remote) {
      await _writeLocalLetter(userId, today, choice.push);
    } else if (choice.source == DailyLetterSource.prepared ||
        choice.source == DailyLetterSource.catalog) {
      await _writeLocalLetter(userId, today, choice.push);
      await _writeRemoteLetter(today, choice.push);
    }
    return choice.push;
  }

  String _todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// 今天的信已经定了之后，悄悄为本地明天写一封。失败也不影响当前信封。
  /// 行为没变时服务端直接返回已有的信，不会再叫模型。
  Future<void> prepareUpcomingLetter() async {
    final userId = _client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final date = _dateKey(DateTime.now().add(const Duration(days: 1)));
    try {
      final first = await _client.functions.invoke(
        'prepare-letter',
        body: {'letter_date': date},
      );
      if (_letterWasStale(first.data)) {
        await _client.functions.invoke(
          'prepare-letter',
          body: {'letter_date': date},
        );
      }
    } catch (_) {}
  }

  bool _letterWasStale(dynamic data) {
    return data is Map && data['stale'] == true;
  }

  /// 开发时每次都丢掉明天那封并重写。不写入今天的缓存。
  Future<DailyPush?> fetchUpcomingLetterForTest() async {
    final userId = _client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return null;
    final date = _dateKey(DateTime.now().add(const Duration(days: 1)));
    final previous = await _readPreparedLetter(userId, date);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _client
            .from('daily_letters')
            .delete()
            .eq('user_id', userId)
            .eq('letter_date', date);
      } catch (_) {}
      try {
        final response = await _client.functions.invoke(
          'prepare-letter',
          body: {
            'letter_date': date,
            'avoid_keyword': previous?.keyword ?? '',
            'avoid_quote': previous?.quote ?? '',
          },
        );
        final data = response.data;
        final again =
            data is Map && (data['cached'] == true || data['stale'] == true);
        if (!again) break;
      } catch (_) {
        break;
      }
    }
    return _readPreparedLetter(userId, date);
  }

  /// 把今天打开的这封信放进草稿箱。同一天再存一次会覆盖。
  Future<bool> saveLetterDraft(DailyPush push) async {
    final me = _client.auth.currentUser?.id ?? '';
    if (me.isEmpty) return false;
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final date = '${now.year}-$month-$day';
    try {
      await _client.from('letter_drafts').upsert({
        'user_id': me,
        'letter_date': date,
        'letter': push.toLetterJson(),
      }, onConflict: 'user_id,letter_date');
      return true;
    } catch (error) {
      print('👉 [DEBUG] save letter draft: $error');
      return false;
    }
  }

  Future<List<LetterDraft>> fetchLetterDrafts() async {
    final me = _client.auth.currentUser?.id ?? '';
    if (me.isEmpty) return const [];
    try {
      final rows = await _client
          .from('letter_drafts')
          .select('id, letter_date, letter')
          .eq('user_id', me)
          .order('letter_date', ascending: false);
      final drafts = <LetterDraft>[];
      for (final row in rows) {
        final raw = row['letter'];
        if (raw is! Map) continue;
        drafts.add(
          LetterDraft(
            id: row['id']?.toString() ?? '',
            letterDate: row['letter_date']?.toString() ?? '',
            push: DailyPush.fromJson(Map<String, dynamic>.from(raw)),
          ),
        );
      }
      return drafts;
    } catch (error) {
      print('👉 [DEBUG] letter drafts: $error');
      return const [];
    }
  }

  /// 收藏、点赞、写下感悟之后，记下依据，并重写还没拆开的下一封信。
  Future<List<({String kind, String excerpt})>> fetchInterestSignals() async {
    final actor = _uid ?? '';
    if (actor.isEmpty) return const [];
    try {
      final rows = await _client
          .from('interest_signals')
          .select('kind, excerpt')
          .eq('user_id', actor)
          .order('created_at', ascending: false)
          .limit(6);
      return [
        for (final row in rows)
          if ((row['excerpt']?.toString().trim() ?? '').isNotEmpty)
            (
              kind: row['kind']?.toString() ?? '',
              excerpt: row['excerpt'].toString().trim(),
            ),
      ];
    } catch (error) {
      print('👉 [DEBUG] interest signals: $error');
      return const [];
    }
  }

  Future<void> _noteInterestFromPost(String kind, String postId) async {
    try {
      final row = await _client
          .from('inspirations')
          .select('user_text, quote, keywords')
          .eq('id', postId)
          .maybeSingle();
      if (row == null) return;
      final keywords = <String>[];
      final rawKeywords = row['keywords'];
      if (rawKeywords is List) {
        for (final item in rawKeywords) {
          final text = item.toString().trim();
          if (text.isNotEmpty) keywords.add(text);
        }
      }
      await _noteInterest(
        kind: kind,
        sourceId: postId,
        excerpt: _interestExcerpt(
          row['user_text']?.toString() ?? '',
          row['quote']?.toString() ?? '',
          keywords,
        ),
      );
    } catch (error) {
      print('👉 [DEBUG] interest post: $error');
    }
  }

  Future<void> _noteInterest({
    required String kind,
    required String sourceId,
    required String excerpt,
  }) async {
    final actor = _uid ?? '';
    final source = sourceId.trim();
    final line = _clipInterest(excerpt);
    if (actor.isEmpty || source.isEmpty || line.isEmpty) return;
    if (kind != 'reflection' && kind != 'save' && kind != 'like') return;
    try {
      await _client
          .from('interest_signals')
          .delete()
          .eq('user_id', actor)
          .eq('kind', kind)
          .eq('source_id', source);
      await _client.from('interest_signals').insert({
        'user_id': actor,
        'kind': kind,
        'source_id': source,
        'excerpt': line,
      });
      _scheduleLetterFromInterest();
    } catch (error) {
      print('👉 [DEBUG] note interest: $error');
    }
  }

  Future<void> _clearInterest(String kind, String sourceId) async {
    final actor = _uid ?? '';
    final source = sourceId.trim();
    if (actor.isEmpty || source.isEmpty) return;
    try {
      await _client
          .from('interest_signals')
          .delete()
          .eq('user_id', actor)
          .eq('kind', kind)
          .eq('source_id', source);
      _scheduleLetterFromInterest();
    } catch (error) {
      print('👉 [DEBUG] clear interest: $error');
    }
  }

  void _scheduleLetterFromInterest() {
    _interestTimer?.cancel();
    _interestTimer = Timer(const Duration(seconds: 2), () {
      final id = _uid ?? '';
      if (id.isEmpty) return;
      unawaited(refreshUpcomingLetter(id));
    });
  }

  String _interestExcerpt(
    String userText,
    String quote,
    List<String> keywords,
  ) {
    final split = userText.contains('\u001e');
    final parts = userText.split('\u001e');
    final title = split ? parts.first.trim() : '';
    final body = (split ? parts.skip(1).join() : userText).trim();
    final line = [
      title,
      body,
      quote.trim(),
      keywords.join(' '),
    ].where((part) => part.isNotEmpty).join(' / ');
    return _clipInterest(line);
  }

  String _clipInterest(String value) {
    final text = value.trim();
    final chars = text.runes.toList();
    if (chars.length <= 80) return text;
    return String.fromCharCodes(chars.take(80));
  }

  Future<DailyPush?> _readPreparedLetter(String userId, String today) async {
    try {
      final row = await _client
          .from('daily_letters')
          .select(
            'keyword, quote, quote_author, theme_name, sub_theme_name, why_today, music_title, music_artist, image_url, city_name, city_country, building_name, building_city, film_title, film_director, book_title, book_author, letter_date',
          )
          .eq('user_id', userId)
          .eq('letter_date', today)
          .maybeSingle();
      if (row == null) return null;
      return _letterFromMap(row);
    } catch (_) {
      return null;
    }
  }

  String _letterPrefsKey(String userId) => 'daily_push_$userId';

  Future<DailyPush?> _readCachedLetter(String userId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_letterPrefsKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      if (data['date']?.toString() != today) return null;
      return _letterFromMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<DailyPush?> _readRemoteLetter(String userId, String today) async {
    try {
      final response = await _client.auth.getUser();
      final user = response.user;
      if (user == null || user.id != userId) return null;
      final raw = user.userMetadata?['daily_letter'];
      if (raw is! Map) return null;
      final data = Map<String, dynamic>.from(raw);
      if (data['date']?.toString() != today) return null;
      return _letterFromMap(data);
    } catch (_) {
      return null;
    }
  }

  DailyPush? _letterFromMap(Map<String, dynamic> data) {
    final keyword = data['keyword']?.toString().trim() ?? '';
    final quote = data['quote']?.toString().trim() ?? '';
    final music = data['music_title']?.toString().trim() ?? '';
    final image = data['image_url']?.toString().trim() ?? '';
    final city = data['city_name']?.toString().trim() ?? '';
    final building = data['building_name']?.toString().trim() ?? '';
    final film = data['film_title']?.toString().trim() ?? '';
    final book = data['book_title']?.toString().trim() ?? '';
    if (keyword.isEmpty &&
        quote.isEmpty &&
        music.isEmpty &&
        city.isEmpty &&
        building.isEmpty &&
        film.isEmpty &&
        book.isEmpty &&
        !image.startsWith('http')) {
      return null;
    }
    return DailyPush.fromJson(data);
  }

  Future<void> _writeLocalLetter(
    String userId,
    String today,
    DailyPush push,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _letterPrefsKey(userId),
      jsonEncode({
        'date': today,
        'keyword': push.keyword,
        'quote': push.quote,
        'theme_name': push.themeName,
        'sub_theme_name': push.subThemeName,
        'why_today': push.whyToday,
        'quote_author': push.quoteAuthor,
        'music_title': push.musicTitle,
        'music_artist': push.musicArtist,
        'image_url': push.imageUrl,
        'city_name': push.cityName,
        'city_country': push.cityCountry,
        'building_name': push.buildingName,
        'building_city': push.buildingCity,
        'film_title': push.filmTitle,
        'film_director': push.filmDirector,
        'book_title': push.bookTitle,
        'book_author': push.bookAuthor,
      }),
    );
  }

  Future<void> _writeRemoteLetter(String today, DailyPush push) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            'daily_letter': {
              'date': today,
              'keyword': push.keyword,
              'quote': push.quote,
              'theme_name': push.themeName,
              'sub_theme_name': push.subThemeName,
              'why_today': push.whyToday,
              'quote_author': push.quoteAuthor,
              'music_title': push.musicTitle,
              'music_artist': push.musicArtist,
              'image_url': push.imageUrl,
              'city_name': push.cityName,
              'city_country': push.cityCountry,
              'building_name': push.buildingName,
              'building_city': push.buildingCity,
              'film_title': push.filmTitle,
              'film_director': push.filmDirector,
              'book_title': push.bookTitle,
              'book_author': push.bookAuthor,
            },
          },
        ),
      );
    } catch (_) {}
  }

  Future<List<MuseumTheme>> fetchAvailableThemes() async {
    final raw = await _client.from('themes').select('id, name').order('name');
    final themes = <MuseumTheme>[];
    for (final row in raw) {
      final theme = MuseumTheme.fromJson(row);
      if (theme.id.isEmpty || theme.name.isEmpty) continue;
      themes.add(theme);
    }
    return themes;
  }

  Future<List<String>> fetchUserSelectedThemes(String userId) async {
    if (userId.isEmpty) return const [];
    final raw = await _client
        .from('user_theme_preferences')
        .select('theme_id')
        .eq('user_id', userId);
    return [
      for (final row in raw)
        if ((row['theme_id']?.toString() ?? '').isNotEmpty)
          row['theme_id'].toString(),
    ];
  }

  /// [isSubscribed] 为期望状态：true 写入，false 删除。
  Future<void> toggleThemeSubscription(
    String userId,
    String themeId,
    bool isSubscribed,
  ) async {
    if (isSubscribed) {
      await subscribeToTheme(userId, themeId);
      return;
    }
    await unsubscribeFromTheme(userId, themeId);
  }

  Future<void> subscribeToTheme(String userId, String themeId) async {
    if (userId.isEmpty || themeId.isEmpty) return;
    await _client.from('user_theme_preferences').upsert({
      'user_id': userId,
      'theme_id': themeId,
    });
  }

  Future<void> unsubscribeFromTheme(String userId, String themeId) async {
    if (userId.isEmpty || themeId.isEmpty) return;
    await _client
        .from('user_theme_preferences')
        .delete()
        .eq('user_id', userId)
        .eq('theme_id', themeId);
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  Future<void> saveOnboarding(List<String> themes) async {
    final me = AuthService.instance.currentUser;
    if (me == null) return;
    try {
      await _client
          .from('profiles')
          .update({'selected_themes': themes, 'onboarding_completed': true})
          .eq('id', me.id);
    } catch (_) {}
    try {
      final meta = Map<String, dynamic>.from(me.userMetadata ?? {});
      meta['selected_themes'] = themes;
      meta['onboarding_completed'] = true;
      await _client.auth.updateUser(UserAttributes(data: meta));
    } catch (_) {}
  }
}
