import 'package:flutter/foundation.dart';
import 'package:inspiration_museum/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 鉴权单例：封装 [Supabase.instance.client.auth]。
///
/// 游客（匿名）登录后若再登记邮箱，会走账号升级（[updateUser]），
/// 从而保留游客期内以 user id 绑定的本地 / 云端数据。
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Session? get currentSession => _auth.currentSession;

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentSession != null && currentUser != null;

  bool get isAnonymous => currentUser?.isAnonymous ?? false;

  /// 全局登录态。含 `initialSession`、登录、退出、token 刷新。
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  SupabaseClient get _client => Supabase.instance.client;

  Future<UserModel?>? _ensureInFlight;

  /// 游客模式。需在 Supabase 控制台开启 Anonymous Sign-ins。
  Future<AuthResponse> signInAnonymously() async {
    final response = await _auth.signInAnonymously();
    await ensureProfile();
    return response;
  }

  /// 标准邮箱登录。
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    await ensureProfile();
    return response;
  }

  /// 邮箱注册。若当前是匿名会话，则把同一 user id 升级为正式账号，
  /// 而不是再开一个新用户（避免游客期数据丢失）。
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final current = currentUser;
    if (current != null && current.isAnonymous) {
      final updated = await _auth.updateUser(
        UserAttributes(email: email, password: password),
      );
      await ensureProfile();
      return AuthResponse(
        session: _auth.currentSession,
        user: updated.user ?? currentUser ?? current,
      );
    }

    final created = await _auth.signUp(email: email, password: password);
    await ensureProfile();
    return created;
  }

  /// 只读取云端档案，不从客户端写入 `profiles`。
  Future<UserModel?> ensureProfile() {
    final user = currentUser;
    if (user == null) {
      _ensureInFlight = null;
      return Future<UserModel?>.value(null);
    }
    return _ensureInFlight ??= _ensureProfileInner(user).whenComplete(() {
      _ensureInFlight = null;
    });
  }

  Future<UserModel?> _ensureProfileInner(User user) async {
    final existing = await _readProfile(user.id);

    if (existing == null) {
      return UserModel(
        id: user.id,
        username: _usernameFor(user),
        avatarUrl: '',
        bio: user.isAnonymous ? 'Visiting as a guest.' : 'The empty squares are the ones that belong to you.',
        followersCount: 0,
        followingCount: 0,
      );
    }

    return UserModel.fromJson(existing);
  }

  Future<Map<String, dynamic>?> _readProfile(String userId) async {
    try {
      return await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
    } catch (error) {
      debugPrint('profiles select failed: $error');
      return null;
    }
  }

  static String _usernameFor(User user) {
    final mail = user.email?.trim() ?? '';
    if (mail.isNotEmpty) return mail.split('@').first;
    return user.isAnonymous ? 'GUEST' : 'USER';
  }

  Future<void> signOut() async {
    _ensureInFlight = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _auth.signOut();
  }

  /// 登录失败是否表示「这个邮箱还没有账号」。
  static bool isUnknownUser(AuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    if (code == 'user_not_found' || code == 'user_not_exist') return true;
    if (message.contains('user not found') ||
        message.contains('user does not exist') ||
        message.contains('no user found')) {
      return true;
    }
    if (code == 'invalid_credentials') return true;
    if (message.contains('invalid login credentials') ||
        message.contains('invalid_credentials')) {
      return true;
    }
    return false;
  }

  static bool isAlreadyRegistered(AuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code == 'email_exists' ||
        code == 'user_already_exists' ||
        message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('user already');
  }
}
