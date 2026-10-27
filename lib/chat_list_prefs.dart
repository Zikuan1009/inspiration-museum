import 'dart:convert';

import 'package:inspiration_museum/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天列表的置顶和隐藏。隐藏只收起对话框，不删消息。
abstract final class ChatListPrefs {
  static String? get _userId {
    final id = AuthService.instance.currentUser?.id ?? '';
    return id.isEmpty ? null : id;
  }

  static Future<Set<String>> pins() async {
    final id = _userId;
    if (id == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_pins_$id');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final item in decoded)
          if (item.toString().isNotEmpty) item.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> setPinned(String peerId, bool pinned) async {
    final id = _userId;
    if (id == null || peerId.isEmpty) return;
    final next = await pins();
    if (pinned) {
      next.add(peerId);
    } else {
      next.remove(peerId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_pins_$id', jsonEncode(next.toList()));
  }

  /// 隐藏到这条消息为止。更新的消息会让对话框重新出现。
  static Future<Map<String, int>> hidden() async {
    final id = _userId;
    if (id == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_hidden_$id');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final marks = <String, int>{};
      for (final entry in decoded.entries) {
        final stamp = int.tryParse(entry.value.toString());
        if (entry.key.toString().isEmpty || stamp == null) continue;
        marks[entry.key.toString()] = stamp;
      }
      return marks;
    } catch (_) {
      return {};
    }
  }

  static Future<void> hide(String peerId, DateTime lastAt) async {
    final id = _userId;
    if (id == null || peerId.isEmpty) return;
    final next = await hidden();
    next[peerId] = lastAt.microsecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_hidden_$id', jsonEncode(next));
  }
}
