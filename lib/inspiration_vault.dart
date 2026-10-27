import 'dart:convert';

import 'package:inspiration_museum/inspiration_record.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class InspirationVault {
  static const savedInspirations = 'saved_inspirations';

  static String? _scopedKey() {
    final id = AuthService.instance.currentUser?.id;
    if (id == null || id.isEmpty) return null;
    return '${savedInspirations}_$id';
  }

  static Future<List<InspirationRecord>> load() async {
    final key = _scopedKey();
    if (key == null) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(key) ?? const <String>[];
    final records = <InspirationRecord>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          records.add(InspirationRecord.fromJson(decoded));
        } else if (decoded is Map) {
          records.add(
            InspirationRecord.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        continue;
      }
    }
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  static Future<void> append(InspirationRecord record) async {
    final key = _scopedKey();
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.from(
      prefs.getStringList(key) ?? const <String>[],
    );
    raw.add(jsonEncode(record.toJson()));
    await prefs.setStringList(key, raw);
  }
}
