import 'dart:convert';

import 'package:inspiration_museum/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只给当前用户看的对方备注，按登录用户分开存放。
abstract final class PeerRemarks {
  static const _prefix = 'peer_remarks';

  static Future<Map<String, String>> load([String? userId]) async {
    final id = userId ?? AuthService.instance.currentUser?.id ?? '';
    if (id.isEmpty) return const {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefix}_$id');
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final notes = <String, String>{};
      for (final entry in decoded.entries) {
        final note = entry.value?.toString().trim() ?? '';
        if (entry.key.toString().isEmpty || note.isEmpty) continue;
        notes[entry.key.toString()] = note;
      }
      return notes;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> save(String peerId, String remark, [String? userId]) async {
    final id = userId ?? AuthService.instance.currentUser?.id ?? '';
    if (id.isEmpty || peerId.isEmpty) return;
    final notes = Map<String, String>.from(await load(id));
    final next = remark.trim();
    if (next.isEmpty) {
      notes.remove(peerId);
    } else {
      notes[peerId] = next;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefix}_$id', jsonEncode(notes));
  }
}
