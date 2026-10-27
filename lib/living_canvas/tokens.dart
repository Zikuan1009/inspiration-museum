import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Museum Luxe Editorial 的颜色。象牙色纸面、墨色文字，
/// 四个矿物色只给内容和少数重点元素，不用来装饰每一个控件。
abstract final class CanvasColors {
  static const background = Color(0xFFF3F0E8);
  static const surface = Color(0xFFFAF8F3);
  static const sunken = Color(0xFFEAE6DC);
  static const text = Color(0xFF22231F);
  static const textSecondary = Color(0xFF79766F);
  static const textOnInk = Color(0xFFF6F3EA);
  static const divider = Color(0xFFDDD8CE);
  static const scrim = Color(0x6622231F);

  static const forest = Color(0xFF244D43);
  static const mineral = Color(0xFF68849A);
  static const terracotta = Color(0xFFB56D53);
  static const gold = Color(0xFFB39A66);

  /// 深底上的小字和细线。比 [gold] 亮一档，压在森林绿上仍可读。
  static const goldLight = Color(0xFFD9C79C);

  /// 错误提示。比陶土色更深，在纸面上对比足够。
  static const danger = Color(0xFFA2432C);

  static const accents = <Color>[forest, mineral, terracotta, gold];

  /// 同一个字符串总是拿到同一个矿物色，用于话题、作者等稳定的点缀。
  static Color accentFor(String seed) {
    return accents[stableHash(seed) % accents.length];
  }

  /// 矿物色在纸面上的浅底，用于标签和选中态。
  static Color tint(Color accent, [double amount = 0.12]) {
    return Color.alphaBlend(accent.withValues(alpha: amount), surface);
  }

  /// 跨运行稳定的字符串哈希。String.hashCode 在 Web 和原生上不一致。
  static int stableHash(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

/// 4 的倍数。页面左右边距用 [page]，段落之间用 [section]。
abstract final class CanvasSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double page = 20;
  static const double section = 32;

  /// 瀑布流两列之间与上下之间的间距。
  static const double gridColumn = 14;
  static const double gridRow = 22;
}

abstract final class CanvasRadius {
  static const double tag = 3;
  static const double image = 5;
  static const double card = 8;
  static const double button = 8;
  static const double input = 8;
  static const double dialog = 12;

  static const BorderRadius tagAll = BorderRadius.all(Radius.circular(tag));
  static const BorderRadius imageAll = BorderRadius.all(Radius.circular(image));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius buttonAll = BorderRadius.all(
    Radius.circular(button),
  );
  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(dialog),
  );
}

/// 阴影用正文墨色而不是纯黑，在象牙底上不会发灰。
abstract final class CanvasShadow {
  static const none = <BoxShadow>[];

  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x0A22231F), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D22231F), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const raised = <BoxShadow>[
    BoxShadow(color: Color(0x0D22231F), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A22231F), blurRadius: 28, offset: Offset(0, 12)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x1222231F), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x2422231F), blurRadius: 40, offset: Offset(0, 18)),
  ];
}

/// 渐变只给每日来信、精选内容和沉浸场景。都是同一色系内的深浅过渡，
/// 像矿物和颜料的层次，而不是跨色相的霓虹渐变。
abstract final class CanvasGradients {
  /// 每日来信：深森林绿压向墨色，右上角透出一点矿物蓝。
  static const dailyLetter = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF3B6763), CanvasColors.forest, Color(0xFF16302A)],
    stops: [0, 0.45, 1],
  );

  /// 安静的沉浸场景：矿物蓝到森林绿。
  static const mineral = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [CanvasColors.mineral, Color(0xFF3E6366)],
  );

  /// 暖色精选：陶土到暗金。
  static const ember = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [CanvasColors.terracotta, Color(0xFF9C7B4F)],
  );

  /// 铺在大块背景上的浅色版本，文字可以直接压在上面。
  static const mist = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF6F2E8), CanvasColors.background, Color(0xFFE9ECE6)],
    stops: [0, 0.5, 1],
  );

  /// 图片上叠字时用的底部压暗。
  static const imageScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0016302A), Color(0xB316302A)],
  );
}

abstract final class CanvasMotion {
  /// 按压、选中这类直接反馈。
  static const quick = Duration(milliseconds: 160);

  /// 大多数状态切换。
  static const standard = Duration(milliseconds: 280);

  /// 页面进入、卡片展开。
  static const emphasized = Duration(milliseconds: 420);

  /// 每日来信这类需要被看见的揭示。
  static const reveal = Duration(milliseconds: 640);

  /// 列表依次进入时，每一项之间的间隔。
  static const stagger = Duration(milliseconds: 56);

  /// 背景渐变缓慢漂移一圈的时长。
  static const ambient = Duration(seconds: 18);

  static const Curve standardCurve = Cubic(0.2, 0, 0, 1);
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve exit = Cubic(0.3, 0, 0.8, 0.15);
  static const Curve drift = Curves.easeInOutSine;

  /// 按下时缩到的比例。
  static const double pressScale = 0.97;
}
