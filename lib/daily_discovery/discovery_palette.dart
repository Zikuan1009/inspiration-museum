import 'package:flutter/painting.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/tokens.dart';

/// 每日灵感的整体色调。同一封信在首页卡片、全屏页和写作页用同一套，
/// 展开和返回时颜色不会跳。
class DiscoveryPalette {
  const DiscoveryPalette({
    required this.name,
    required this.deep,
    required this.mid,
    required this.glow,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.shape,
    required this.bar,
    this.isLight = false,
  });

  final String name;

  /// 背景渐变：最暗处、主体、透光处。
  final Color deep;
  final Color mid;
  final Color glow;

  /// 主文字与次要文字。
  final Color ink;
  final Color muted;

  /// 眉题、细线、小标记。
  final Color accent;

  /// 背景构成里的大色面与细竖条。
  final Color shape;
  final Color bar;

  /// 浅底深字。图片压字时不会选它。
  final bool isLight;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [glow, mid, deep],
    stops: const [0, 0.48, 1],
  );

  /// 主按钮：在深底上是象牙色块，在浅底上是墨色块。
  Color get actionFill => ink;
  Color get actionText => isLight ? CanvasColors.textOnInk : deep;

  static const mineralBlue = DiscoveryPalette(
    name: 'Mineral Blue',
    deep: Color(0xFF17232D),
    mid: Color(0xFF34495A),
    glow: Color(0xFF6F8BA0),
    ink: Color(0xFFF4F1E8),
    muted: Color(0xFFC3CDD3),
    accent: Color(0xFFD9C79C),
    shape: Color(0xFF8FA8BA),
    bar: Color(0xFFC98A68),
  );

  static const deepForest = DiscoveryPalette(
    name: 'Deep Forest',
    deep: Color(0xFF12261F),
    mid: CanvasColors.forest,
    glow: Color(0xFF3F6B66),
    ink: Color(0xFFF6F3EA),
    muted: Color(0xFFC6D1C9),
    accent: CanvasColors.goldLight,
    shape: CanvasColors.mineral,
    bar: CanvasColors.terracotta,
  );

  static const warmTerracotta = DiscoveryPalette(
    name: 'Warm Terracotta',
    deep: Color(0xFF3A1D14),
    mid: Color(0xFF7D4330),
    glow: Color(0xFFB9775A),
    ink: Color(0xFFFBF4EA),
    muted: Color(0xFFE6CDBE),
    accent: Color(0xFFF0D7AE),
    shape: Color(0xFFD9A07F),
    bar: Color(0xFF2E4A42),
  );

  static const antiqueGold = DiscoveryPalette(
    name: 'Antique Gold',
    deep: Color(0xFF2B2316),
    mid: Color(0xFF5E4C2C),
    glow: Color(0xFF9C8455),
    ink: Color(0xFFFAF5E8),
    muted: Color(0xFFDCD0B4),
    accent: Color(0xFFF0E1B8),
    shape: Color(0xFFC9B07A),
    bar: Color(0xFF8C4A35),
  );

  static const inkAndIvory = DiscoveryPalette(
    name: 'Ink and Ivory',
    deep: Color(0xFFE6E1D5),
    mid: Color(0xFFF1EDE3),
    glow: Color(0xFFFAF8F2),
    ink: CanvasColors.text,
    muted: CanvasColors.textSecondary,
    accent: CanvasColors.terracotta,
    shape: Color(0xFFB9C4C2),
    bar: CanvasColors.forest,
    isLight: true,
  );

  static const all = <DiscoveryPalette>[
    deepForest,
    mineralBlue,
    warmTerracotta,
    antiqueGold,
    inkAndIvory,
  ];

  /// 领域名里出现这些词时用对应色调。领域可能是中文库名，先换成英文标签。
  static const _byTheme = <String, DiscoveryPalette>{
    'MUSIC': mineralBlue,
    'SOUND': mineralBlue,
    'SCIENCE': mineralBlue,
    'OPTICS': mineralBlue,
    'MIND': mineralBlue,
    'LOGIC': mineralBlue,
    'MECHANIC': mineralBlue,
    'TRANSIT': mineralBlue,
    'FUTURE': mineralBlue,
    'TECH': mineralBlue,
    'NATURE': deepForest,
    'LAND': deepForest,
    'PHILOSOPHY': deepForest,
    'EXISTENCE': deepForest,
    'MYTH': deepForest,
    'DANCE': deepForest,
    'ARCHITECTURE': warmTerracotta,
    'BUILDING': warmTerracotta,
    'CITY': warmTerracotta,
    'SCULPTURE': warmTerracotta,
    'OBJECT': warmTerracotta,
    'GEOMETRY': warmTerracotta,
    'FOOD': warmTerracotta,
    'LITERATURE': antiqueGold,
    'BOOK': antiqueGold,
    'CALLIGRAPHY': antiqueGold,
    'THEATRE': antiqueGold,
    'PAINTING': antiqueGold,
    'LOVE': antiqueGold,
    'FASHION': antiqueGold,
    'PHOTOGRAPHY': inkAndIvory,
    'FILM': inkAndIvory,
    'TYPOGRAPHY': inkAndIvory,
    'VISUAL': inkAndIvory,
  };

  /// 先看领域，再看子领域；都没有就按关键词稳定地选一套。
  /// 有配图的信不用浅色调，图片下方的压暗需要深色。
  static DiscoveryPalette of(DailyPush push) {
    final hasImage = push.imageUrl.trim().startsWith('http');
    for (final raw in [push.themeName, push.subThemeName]) {
      if (raw.trim().isEmpty) continue;
      final label = CommunityPost.themeLabel(raw).toUpperCase();
      for (final entry in _byTheme.entries) {
        if (!label.contains(entry.key)) continue;
        final palette = entry.value;
        if (hasImage && palette.isLight) return deepForest;
        return palette;
      }
    }
    final pool = hasImage ? all.where((p) => !p.isLight).toList() : all;
    final seed = CanvasColors.stableHash(
      push.keyword.trim().isEmpty ? push.quote : push.keyword,
    );
    return pool[seed % pool.length];
  }
}
