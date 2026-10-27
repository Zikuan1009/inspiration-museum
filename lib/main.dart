import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/post_share.dart';
import 'package:inspiration_museum/shared_post_screen.dart';
import 'package:inspiration_museum/auth_session.dart';
import 'package:inspiration_museum/envelope_stage.dart' show ArchiveLoading;
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/main_screen.dart';
import 'package:inspiration_museum/onboarding_screen.dart';
import 'package:inspiration_museum/services/auth_service.dart';
import 'package:inspiration_museum/services/db_service.dart';
import 'package:inspiration_museum/visuals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 替换为你的 Supabase 项目 URL 与 anon public key。
const kSupabaseUrl = 'https://whagmiyzuhqtyjlurmht.supabase.co';
const kSupabaseAnonKey = 'sb_publishable_WxRZpbs4xIyLHoDziR3igg_Xz4HlY5z';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
    await AuthService.instance.ensureProfile();
  } catch (error, stack) {
    debugPrint('Supabase.initialize failed: $error\n$stack');
  }
  runApp(const InspirationMuseumApp());
}

class InspirationMuseumApp extends StatefulWidget {
  const InspirationMuseumApp({super.key});

  @override
  State<InspirationMuseumApp> createState() => _InspirationMuseumAppState();
}

class _InspirationMuseumAppState extends State<InspirationMuseumApp> {
  final AuthSession _session = AuthSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  static final _theme = LivingCanvasTheme.light();

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      session: _session,
      child: MaterialApp(
        title: 'Inspiration Museum',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: const AuthWrapper(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 路由守卫：无会话 → 登录页（强制）；有会话（含游客）→ 按用户查询引导标志
// ---------------------------------------------------------------------------

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? AuthService.instance.currentSession;

        if (session == null &&
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: PaperBackground()),
                SafeArea(child: ArchiveLoading()),
              ],
            ),
          );
        }

        final sharedPostId = PostShareLink.pageId();
        if (session == null) {
          if (sharedPostId != null) {
            return SharedPostScreen(postId: sharedPostId);
          }
          return const AuthScreen();
        }

        final userId = session.user.id;
        if (userId.isEmpty) {
          if (sharedPostId != null) {
            return SharedPostScreen(postId: sharedPostId);
          }
          return const AuthScreen();
        }
        return MuseumGate(
          key: ValueKey(userId),
          userId: userId,
          openPostId: sharedPostId,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 启动分流：首次进入引导页，否则进入信封馆藏
// ---------------------------------------------------------------------------

class MuseumGate extends StatefulWidget {
  const MuseumGate({super.key, required this.userId, this.openPostId});

  final String userId;
  final String? openPostId;

  @override
  State<MuseumGate> createState() => _MuseumGateState();
}

class _MuseumGateState extends State<MuseumGate> {
  bool? _hasCompletedOnboarding;

  @override
  void initState() {
    super.initState();
    _readFlag();
  }

  @override
  void didUpdateWidget(covariant MuseumGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _hasCompletedOnboarding = null;
      _readFlag();
    }
  }

  Future<void> _readFlag() async {
    final completed = await ArchiveStore.hasCompletedOnboarding(widget.userId);
    if (!mounted) return;
    if (widget.userId != AuthService.instance.currentUser?.id) return;
    setState(() => _hasCompletedOnboarding = completed);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasCompletedOnboarding == null) {
      return const Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: PaperBackground()),
            SafeArea(child: ArchiveLoading()),
          ],
        ),
      );
    }
    if (!_hasCompletedOnboarding!) {
      return OnboardingScreen(onFinished: _finishOnboarding);
    }
    return MainScreen(openPostId: widget.openPostId);
  }

  Future<void> _finishOnboarding(List<String> themes) async {
    if (themes.isEmpty) return;
    await ArchiveStore.completeOnboarding(themes, userId: widget.userId);
    if (!mounted) return;
    setState(() => _hasCompletedOnboarding = true);
  }
}

// ---------------------------------------------------------------------------
// 馆藏数据模型
// ---------------------------------------------------------------------------

class CatalogEntry {
  const CatalogEntry({required this.id, required this.text});

  final String id;
  final String text;

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    return CatalogEntry(id: json['id'] as String, text: json['text'] as String);
  }
}

class QuoteEntry {
  const QuoteEntry({
    required this.id,
    required this.text,
    required this.author,
    required this.theme,
  });

  final String id;
  final String text;
  final String author;
  final String theme;

  factory QuoteEntry.fromJson(Map<String, dynamic> json) {
    return QuoteEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      author: json['author'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
    );
  }
}

class Catalog {
  const Catalog({
    required this.themes,
    required this.visual,
    required this.audio,
    required this.mechanical,
    required this.quotes,
  });

  final Map<String, List<CatalogEntry>> themes;
  final List<CatalogEntry> visual;
  final List<CatalogEntry> audio;
  final List<CatalogEntry> mechanical;
  final List<QuoteEntry> quotes;

  static List<CatalogEntry> _parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => CatalogEntry.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty && e.text.isNotEmpty)
        .toList(growable: false);
  }

  static List<QuoteEntry> _parseQuotes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => QuoteEntry.fromJson(Map<String, dynamic>.from(e)))
        .where(
          (e) =>
              e.id.isNotEmpty &&
              e.text.isNotEmpty &&
              e.author.isNotEmpty &&
              e.theme.isNotEmpty,
        )
        .toList(growable: false);
  }

  factory Catalog.fromJson(Map<String, dynamic> json) {
    final themes = <String, List<CatalogEntry>>{};
    final rawThemes = json['themes'];
    if (rawThemes is Map) {
      for (final entry in rawThemes.entries) {
        final key = entry.key.toString();
        final list = _parseList(entry.value);
        if (key.isNotEmpty && list.isNotEmpty) {
          themes[key] = list;
        }
      }
    }

    List<CatalogEntry> pool(List<String> names) {
      return [
        for (final name in names) ...(themes[name] ?? const <CatalogEntry>[]),
      ];
    }

    final visual = json['visual'] is List
        ? _parseList(json['visual'])
        : pool(const [
            '绘画',
            '建筑',
            '摄影',
            '雕塑',
            '书法',
            '几何',
            '城市',
            '光学',
            '神话',
            '自然',
            '文学',
            '排版',
            '服饰',
            '饮食',
          ]);
    final audio = json['audio'] is List
        ? _parseList(json['audio'])
        : pool(const ['音乐', '戏剧', '电影', '舞蹈']);
    final mechanical = json['mechanical'] is List
        ? _parseList(json['mechanical'])
        : pool(const ['机械', '器物', '交通']);
    final quotes = _parseQuotes(json['quotes']);

    final catalog = Catalog(
      themes: Map<String, List<CatalogEntry>>.unmodifiable(themes),
      visual: visual,
      audio: audio,
      mechanical: mechanical,
      quotes: quotes,
    );
    if (catalog.themes.length < 3 || catalog.quotes.isEmpty) {
      throw const FormatException('The catalog has an empty category.');
    }
    return catalog;
  }

  static Future<Catalog> loadFromBundle() async {
    final source = await rootBundle.loadString('assets/data.json');
    return Catalog.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}

class DailyDraw {
  const DailyDraw({
    required this.visual,
    required this.audio,
    required this.mechanical,
    required this.quote,
    required this.quoteAuthor,
  });

  final String visual;
  final String audio;
  final String mechanical;
  final String quote;
  final String quoteAuthor;

  List<String> get keywords => [visual, audio, mechanical];
}

// ---------------------------------------------------------------------------
// 无放回抽样 + 本地持久化
// ---------------------------------------------------------------------------

abstract final class ArchiveStore {
  static const hasCompletedOnboardingPrefix = 'has_completed_onboarding';
  static const dailyLetterPrefix = 'daily_letter';
  static const letterOpenedPrefix = 'letter_opened';
  static const usedQuotesPrefix = 'used_quotes';
  static const usedThemePrefix = 'used_theme_';
  static const selectedThemesPrefix = 'selected_themes';

  static String? _currentUserId() {
    final id = AuthService.instance.currentUser?.id;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// 所有本地缓存 Key 必须拼接当前用户 ID，禁止使用全局固定键。
  static String _scoped(String prefix, [String? userId]) {
    final id = userId ?? _currentUserId();
    if (id == null) {
      throw StateError('Local cache must belong to the signed-in member.');
    }
    return '${prefix}_$id';
  }

  static String dateKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// 当天第一次进入才会自动展开来信。
  static Future<bool> hasOpenedLetterToday([String? userId]) async {
    final id = userId ?? _currentUserId();
    if (id == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${letterOpenedPrefix}_$id') == dateKey();
  }

  static Future<void> markLetterOpenedToday([String? userId]) async {
    final id = userId ?? _currentUserId();
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${letterOpenedPrefix}_$id', dateKey());
  }

  /// 先抽三个不同领域的词，再从这三类名言中无放回抽取一条。
  static Future<DailyDraw> resolveToday(Catalog catalog) async {
    final prefs = await SharedPreferences.getInstance();
    final today = dateKey();
    final cached = _readCachedDraw(prefs, today);
    if (cached != null) return cached;

    final rng = math.Random();
    final fields = _pickFields(catalog, prefs, rng, 3);
    final words = <CatalogEntry>[];
    for (final field in fields) {
      final pool = catalog.themes[field];
      if (pool == null || pool.isEmpty) continue;
      words.add(
        await _drawWithoutReplacement(
          prefs: prefs,
          usedKey: _scoped('$usedThemePrefix$field'),
          pool: pool,
          rng: rng,
        ),
      );
    }
    while (words.length < 3) {
      words.add(const CatalogEntry(id: '', text: '—'));
    }

    final matchedQuotes = catalog.quotes
        .where((q) => fields.contains(q.theme))
        .toList(growable: false);
    final quotePool = matchedQuotes.isNotEmpty ? matchedQuotes : catalog.quotes;
    final quote = await _drawQuoteWithoutReplacement(
      prefs: prefs,
      pool: quotePool,
      rng: rng,
    );

    final draw = DailyDraw(
      visual: words[0].text,
      audio: words[1].text,
      mechanical: words[2].text,
      quote: quote.text,
      quoteAuthor: quote.author,
    );
    await prefs.setString(
      _scoped(dailyLetterPrefix),
      jsonEncode({
        'date': today,
        'visual': draw.visual,
        'audio': draw.audio,
        'mechanical': draw.mechanical,
        'quote': draw.quote,
        'quoteAuthor': draw.quoteAuthor,
      }),
    );
    return draw;
  }

  static List<String> _pickFields(
    Catalog catalog,
    SharedPreferences prefs,
    math.Random rng,
    int count,
  ) {
    final available = catalog.themes.keys
        .where((name) => (catalog.themes[name] ?? const []).isNotEmpty)
        .toList();
    available.shuffle(rng);

    final selected =
        (prefs.getStringList(_scoped(selectedThemesPrefix)) ?? const <String>[])
            .where(available.contains)
            .toList();
    selected.shuffle(rng);

    final picked = <String>[];
    for (final name in selected) {
      if (picked.length >= count) break;
      picked.add(name);
    }
    for (final name in available) {
      if (picked.length >= count) break;
      if (!picked.contains(name)) picked.add(name);
    }
    return picked;
  }

  static DailyDraw? _readCachedDraw(SharedPreferences prefs, String today) {
    final raw = prefs.getString(_scoped(dailyLetterPrefix));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      if (data['date'] != today) return null;
      final visual = data['visual'] as String?;
      final audio = data['audio'] as String?;
      final mechanical = data['mechanical'] as String?;
      final quote = data['quote'] as String?;
      final author = data['quoteAuthor'] as String?;
      if (visual == null ||
          audio == null ||
          mechanical == null ||
          quote == null ||
          author == null ||
          author.isEmpty) {
        return null;
      }
      return DailyDraw(
        visual: visual,
        audio: audio,
        mechanical: mechanical,
        quote: quote,
        quoteAuthor: author,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<CatalogEntry> _drawWithoutReplacement({
    required SharedPreferences prefs,
    required String usedKey,
    required List<CatalogEntry> pool,
    required math.Random rng,
  }) async {
    final picked = await _drawUnusedId(
      prefs: prefs,
      usedKey: usedKey,
      pool: pool,
      idOf: (e) => e.id,
      rng: rng,
    );
    return picked;
  }

  static Future<QuoteEntry> _drawQuoteWithoutReplacement({
    required SharedPreferences prefs,
    required List<QuoteEntry> pool,
    required math.Random rng,
  }) {
    return _drawUnusedId(
      prefs: prefs,
      usedKey: _scoped(usedQuotesPrefix),
      pool: pool,
      idOf: (e) => e.id,
      rng: rng,
    );
  }

  static Future<T> _drawUnusedId<T>({
    required SharedPreferences prefs,
    required String usedKey,
    required List<T> pool,
    required String Function(T) idOf,
    required math.Random rng,
  }) async {
    if (pool.isEmpty) {
      throw const FormatException('The draw pool is empty.');
    }
    final poolIds = pool.map(idOf).toSet();
    var used = (prefs.getStringList(usedKey) ?? const <String>[])
        .where(poolIds.contains)
        .toList();

    var candidates = pool.where((e) => !used.contains(idOf(e))).toList();
    if (candidates.isEmpty) {
      used = <String>[];
      candidates = List<T>.from(pool);
    }

    final picked = candidates[rng.nextInt(candidates.length)];
    used.add(idOf(picked));
    await prefs.setStringList(usedKey, used);
    return picked;
  }

  static Future<bool> hasCompletedOnboarding([String? userId]) async {
    final id = userId ?? _currentUserId();
    if (id == null) return false;

    try {
      final cloud = await SupabaseDBService.instance.fetchOnboardingState(id);
      if (cloud.themes.isNotEmpty) {
        await _writeLocalOnboarding(id, cloud.themes, completed: true);
        return true;
      }
      await _writeLocalOnboarding(id, const [], completed: false);
      return false;
    } catch (_) {}

    final metaThemes = _themesFromRaw(
      AuthService.instance.currentUser?.userMetadata?['selected_themes'],
    );
    if (metaThemes.isNotEmpty) {
      await _writeLocalOnboarding(id, metaThemes, completed: true);
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    final local =
        prefs.getStringList('${selectedThemesPrefix}_$id') ?? const <String>[];
    return local.isNotEmpty;
  }

  static Future<List<String>> readSelectedThemes([String? userId]) async {
    final id = userId ?? _currentUserId();
    if (id == null) return const [];
    try {
      final cloud = await SupabaseDBService.instance.fetchOnboardingState(id);
      if (cloud.themes.isNotEmpty) {
        await _writeLocalOnboarding(id, cloud.themes, completed: true);
        return cloud.themes;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('${selectedThemesPrefix}_$id') ??
        const <String>[];
  }

  static Future<void> completeOnboarding(
    List<String> themes, {
    String? userId,
  }) async {
    if (themes.isEmpty) return;
    final id = userId ?? _currentUserId();
    if (id == null) {
      throw StateError('Finishing onboarding requires a signed-in member.');
    }
    await _writeLocalOnboarding(id, themes, completed: true);
    try {
      await SupabaseDBService.instance.saveOnboarding(themes);
    } catch (_) {}
  }

  static Future<void> _writeLocalOnboarding(
    String id,
    List<String> themes, {
    required bool completed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${selectedThemesPrefix}_$id', themes);
    await prefs.setBool('${hasCompletedOnboardingPrefix}_$id', completed);
  }

  static List<String> _themesFromRaw(dynamic raw) {
    if (raw is List) {
      return [
        for (final item in raw)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    }
    return const [];
  }
}
