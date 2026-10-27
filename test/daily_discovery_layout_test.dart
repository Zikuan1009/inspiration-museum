import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspiration_museum/daily_discovery/daily_discovery_screen.dart';
import 'package:inspiration_museum/daily_letter_card.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

// 这些信只在测试里用来检查版式，不进入任何正式流程。
const _quote =
    'If we learn to listen, the world itself is an unfinished piece of music.';

DailyPush _letter({
  required String keyword,
  String quote = _quote,
  String imageUrl = '',
}) {
  return DailyPush(
    keyword: keyword,
    quote: quote,
    quoteAuthor: 'Original prompt',
    themeName: '音乐',
    subThemeName: 'City sound and field recording',
    whyToday: 'You saved three posts about quiet streets this week.',
    cityName: 'Prague',
    cityCountry: 'Czech Republic',
    imageUrl: imageUrl,
  );
}

/// 找一个让 [discoveryModeOf] 落在 [mode] 上的关键词。
DailyPush _letterFor(DiscoveryMode mode, {String quote = _quote}) {
  if (mode == DiscoveryMode.image) {
    return _letter(
      keyword: 'brick revealing',
      quote: quote,
      imageUrl: 'https://example.invalid/image.jpg',
    );
  }
  const candidates = [
    'street ambience',
    'margin',
    'unfinished architecture',
    'slow light',
    'Prague',
    '城市声音',
  ];
  for (final keyword in candidates) {
    final push = _letter(keyword: keyword, quote: quote);
    if (discoveryModeOf(push) == mode) return push;
  }
  throw StateError('No candidate keyword for $mode');
}

Future<void> _pump(
  WidgetTester tester,
  DailyPush push, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: LivingCanvasTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 47, bottom: 34),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(DailyDiscoveryScreen.route(push: push)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// 背景的环境动画会一直请求新帧，不能用 pumpAndSettle；按固定时长推进到
/// 展开和揭示都结束。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    // google_fonts 在测试里拿不到网络字体，会在后台抛错。先在一个吞掉这些错误的
    // zone 里把所有字号都取一遍，之后版式用回退字体照常排。
    await runZonedGuarded(() async {
      final styles = [
        CanvasType.brand,
        CanvasType.display,
        CanvasType.hero,
        CanvasType.expressive,
        CanvasType.headline,
        CanvasType.section,
        CanvasType.collectionTitle,
        CanvasType.title,
        CanvasType.titleSmall,
        CanvasType.body,
        CanvasType.bodySmall,
        CanvasType.caption,
        CanvasType.label,
        CanvasType.overline,
        CanvasType.quote,
      ];
      expect(styles, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, stack) {});
  });

  const sizes = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'large phone': Size(430, 932),
  };

  for (final mode in DiscoveryMode.values) {
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('$mode on ${entry.key} at text ${scale}x has no overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            _letterFor(mode),
            size: entry.value,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Write a Reflection'), findsOneWidget);
          expect(find.bySemanticsLabel('Close Daily Inspiration'), findsOne);

          // 滚到底，所有段落和按钮都能排开。
          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -4000),
            3000,
          );
          await _settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Save to Drafts'), findsOneWidget);
          expect(find.text('Back to Home'), findsOneWidget);
        });
      }
    }
  }

  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets('Home card fits on a small phone at text ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: LivingCanvasTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 568),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: DailyLetterCard(
                  push: _letterFor(DiscoveryMode.keyword),
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Explore'), findsOneWidget);
    });
  }

  testWidgets('a very long quote stays readable and scrollable', (
    tester,
  ) async {
    final long = List.filled(12, _quote).join(' ');
    await _pump(
      tester,
      _letterFor(DiscoveryMode.quote, quote: long),
      size: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -6000),
      3000,
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Back to Home'), findsOneWidget);
  });

  testWidgets('Back to Home closes and returns false', (tester) async {
    bool? result;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final push = _letterFor(DiscoveryMode.keyword);
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context)
                  .push(DailyDiscoveryScreen.route(push: push));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Close Daily Inspiration'));
    await _settle(tester);
    expect(result, isFalse);
    expect(find.byType(DailyDiscoveryScreen), findsNothing);
  });

  testWidgets('returning from the editor keeps the reading position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final push = _letterFor(DiscoveryMode.keyword);
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(DailyDiscoveryScreen.route(push: push)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await _settle(tester);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(DailyDiscoveryScreen),
        matching: find.byType(Scrollable),
      ),
    );
    final before = scrollable.position.pixels;
    expect(before, greaterThan(100));

    await tester.tap(find.bySemanticsLabel('Write a Reflection'));
    await _settle(tester);
    expect(find.text('Give it a title'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);

    expect(find.text('Give it a title'), findsNothing);
    final after = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(DailyDiscoveryScreen),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows everything without animating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final push = _letterFor(DiscoveryMode.keyword);
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(DailyDiscoveryScreen.route(push: push)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // 环境动画关闭后不会一直有帧，pumpAndSettle 能结束。
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Write a Reflection'), findsOneWidget);
  });

  testWidgets('opening and closing do not paint the yellow double underline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final push = _letterFor(DiscoveryMode.keyword);
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(DailyDiscoveryScreen.route(push: push)),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    var sawLetter = false;
    for (final step in const [0, 40, 120, 240, 400]) {
      if (step > 0) {
        await tester.pump(Duration(milliseconds: step));
      }
      _expectNoFallbackUnderline(tester);
      if (find.text(push.keyword).evaluate().isNotEmpty) sawLetter = true;
    }
    expect(sawLetter, isTrue);
    await _settle(tester);
    _expectNoFallbackUnderline(tester);

    await tester.tap(find.bySemanticsLabel('Close Daily Inspiration'));
    await tester.pump();
    for (final step in const [40, 120, 240, 360]) {
      await tester.pump(Duration(milliseconds: step));
      _expectNoFallbackUnderline(tester);
    }
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

void _expectNoFallbackUnderline(WidgetTester tester) {
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    paragraph.text.visitChildren((span) {
      if (span is TextSpan) {
        final style = span.style;
        final decoration = style?.decoration;
        final paintsUnderline =
            decoration != null &&
            decoration != TextDecoration.none &&
            decoration.contains(TextDecoration.underline);
        expect(
          paintsUnderline &&
              style?.decorationStyle == TextDecorationStyle.double,
          isFalse,
          reason: 'fallback double underline on "${span.text}"',
        );
      }
      return true;
    });
  }
}
