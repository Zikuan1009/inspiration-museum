import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inspiration_museum/living_canvas/tokens.dart';

/// 打包在 assets/fonts 里的 Noto Serif SC 子集，只含品牌标题和栏目名的几个字。
/// 放在衬线回退的第一位：子集里没有的字会继续往后找。
const museumSerifSC = 'MuseumSerifSC';

/// 中文回退。Inter 和 DM Serif Display 都没有中文字形，中文总会落到这里。
const canvasSansFallback = <String>[
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Noto Sans SC',
  'Noto Sans CJK SC',
  'sans-serif',
];

const canvasSerifFallback = <String>[
  museumSerifSC,
  'Songti SC',
  'STSong',
  'Noto Serif SC',
  'Noto Serif CJK SC',
  ...canvasSansFallback,
];

/// 字号层级。brand、display、hero、expressive、headline、section、quote
/// 用 DM Serif Display，其余用 Inter。中文正文行高放到 1.6。
abstract final class CanvasType {
  static TextStyle _sans({
    required double size,
    required double height,
    FontWeight weight = FontWeight.w400,
    double spacing = 0,
    Color color = CanvasColors.text,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color,
    ).copyWith(fontFamilyFallback: canvasSansFallback);
  }

  static TextStyle _serif({
    required double size,
    required double height,
    FontStyle style = FontStyle.normal,
    double spacing = 0,
    Color color = CanvasColors.text,
  }) {
    return GoogleFonts.dmSerifDisplay(
      fontSize: size,
      height: height,
      fontStyle: style,
      letterSpacing: spacing,
      color: color,
    ).copyWith(fontFamilyFallback: canvasSerifFallback);
  }

  /// 刊头：灵感博物馆。
  static final brand = _serif(size: 28, height: 1.1, spacing: 1.2);

  /// 封面级大标题，一屏最多一个。
  static final display = _serif(size: 40, height: 1.1, spacing: -0.6);

  /// 每日来信卡片里的今日关键词。
  static final hero = _serif(size: 32, height: 1.08, spacing: -0.4);

  /// 斜体强调，用于精选标题。
  static final expressive = _serif(
    size: 30,
    height: 1.12,
    style: FontStyle.italic,
    spacing: -0.3,
  );

  /// 页面标题。
  static final headline = _serif(size: 26, height: 1.2, spacing: -0.2);

  /// 栏目标题，例如首页的 Collections。
  static final section = _serif(size: 22, height: 1.2, spacing: -0.1);

  /// 作品卡片的标题。
  static final collectionTitle = _serif(size: 18, height: 1.22);

  /// 卡片、详情页里的 UI 标题。
  static final title = _sans(
    size: 17,
    height: 1.35,
    weight: FontWeight.w600,
    spacing: -0.1,
  );

  static final titleSmall = _sans(
    size: 15,
    height: 1.4,
    weight: FontWeight.w600,
  );

  /// 正文与长段落。
  static final body = _sans(size: 15, height: 1.6);

  static final bodySmall = _sans(size: 13.5, height: 1.58);

  /// 日期、计数、辅助说明。
  static final caption = _sans(
    size: 12,
    height: 1.4,
    color: CanvasColors.textSecondary,
  );

  /// 按钮与可点的控件文字。
  static final label = _sans(
    size: 14,
    height: 1.2,
    weight: FontWeight.w600,
    spacing: 0.1,
  );

  /// 栏目眉题、标签。大写英文，字距放开。
  static final overline = _sans(
    size: 10.5,
    height: 1.2,
    weight: FontWeight.w600,
    spacing: 1.8,
    color: CanvasColors.textSecondary,
  );

  /// 引文。衬线斜体。
  static final quote = _serif(size: 20, height: 1.4, style: FontStyle.italic);
}
