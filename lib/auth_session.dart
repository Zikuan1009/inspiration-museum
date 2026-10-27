import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 把 [AuthService] 的会话投影成界面用的 [UserModel]，供 Profile / 编辑器读取。
class AuthSession extends ChangeNotifier {
  AuthSession() {
    _sub = AuthService.instance.authStateChanges.listen((_) {
      unawaited(_syncProfile());
    });
    unawaited(_syncProfile());
  }

  StreamSubscription<dynamic>? _sub;
  UserModel? _profile;

  static const demoUserId = 'u_self';

  UserModel? get user {
    final raw = AuthService.instance.currentUser;
    if (raw == null) return null;
    return _profile ?? _fallback(raw);
  }

  bool get isSignedIn => AuthService.instance.isSignedIn;

  Future<void> signOut() => AuthService.instance.signOut();

  Future<void> _syncProfile() async {
    final raw = AuthService.instance.currentUser;
    if (raw == null) {
      _profile = null;
      notifyListeners();
      return;
    }
    try {
      await AuthService.instance.ensureProfile();
      _profile = await SupabaseDBService.instance.getCurrentUserProfile();
    } catch (_) {
      _profile = _fallback(raw);
    }
    notifyListeners();
  }

  UserModel _fallback(User raw) {
    final anonymous = raw.isAnonymous;
    final mail = raw.email?.trim() ?? '';
    final name = mail.isNotEmpty
        ? mail.split('@').first
        : (anonymous ? 'GUEST' : 'USER');
    return UserModel(
      id: raw.id,
      username: name,
      avatarUrl: '',
      bio: anonymous ? 'Visiting as a guest.' : 'The empty squares are the ones that belong to you.',
      followersCount: anonymous ? 0 : 128,
      followingCount: anonymous ? 0 : 36,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class AuthScope extends InheritedNotifier<AuthSession> {
  const AuthScope({
    super.key,
    required AuthSession session,
    required super.child,
  }) : super(notifier: session);

  static AuthSession of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found');
    return scope!.notifier!;
  }

  static AuthSession? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
  }
}
