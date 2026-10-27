import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspiration_museum/daily_discovery/discovery_palette.dart';
import 'package:inspiration_museum/inspiration_editor_screen.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/curation_service.dart';

// 这里的策展结果只在测试里替换网络调用，用来检查画面区域的各个状态。

Future<void> _frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required CurateCall curate,
  EditorPublish? publish,
  Size size = const Size(390, 844),
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
      home: InspirationEditorScreen(
        keywords: const ['brick revealing'],
        quote: 'The brick reveals a hidden hue at dusk.',
        atmosphere: DiscoveryPalette.warmTerracotta,
        curate: curate,
        publish: publish,
      ),
    ),
  );
  await _frames(tester, 4);
}

Future<void> _write(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextField).at(1),
    'The canal walls turned copper on the walk home.',
  );
  await tester.pump();
}

/// 列表是懒加载的，先滚到目标被建出来再操作。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _tapGenerate(WidgetTester tester) async {
  final button = find.bySemanticsLabel('Generate Image');
  await _reveal(tester, button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await runZonedGuarded(() async {
      final styles = [
        CanvasType.hero,
        CanvasType.headline,
        CanvasType.collectionTitle,
        CanvasType.body,
        CanvasType.bodySmall,
        CanvasType.caption,
        CanvasType.label,
        CanvasType.overline,
        CanvasType.quote,
        CanvasType.display,
      ];
      expect(styles, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }, (error, stack) {});
  });

  testWidgets('Generate shows a loading state, then the generated visual', (
    tester,
  ) async {
    final pending = Completer<CurationResult>();
    var calls = 0;
    await _pump(
      tester,
      curate: ({required title, required text, required deep}) {
        calls++;
        expect(deep, isFalse);
        expect(text, contains('copper'));
        return pending.future;
      },
    );
    await _write(tester);
    await _tapGenerate(tester);
    await _frames(tester, 6);

    expect(calls, 1);
    expect(find.text('GENERATED VISUAL'), findsOneWidget);
    expect(find.text('Reading your reflection…'), findsOneWidget);
    expect(find.bySemanticsLabel('Generating…'), findsOneWidget);

    await _frames(tester, 45);
    expect(find.text('Painting the visual…'), findsOneWidget);

    pending.complete(
      const CurationResult(
        keywords: ['copper', 'canal'],
        quote: 'The water held the colour longer than the sky did.',
        caption: '',
        usedUltra: false,
        imageUrl: 'https://example.invalid/visual.jpg',
      ),
    );
    await _frames(tester);

    expect(find.text('GENERATED VISUAL'), findsOneWidget);
    expect(find.text('Reading your reflection…'), findsNothing);
    expect(find.byType(Image), findsWidgets);
    expect(find.bySemanticsLabel('Regenerate'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove'), findsOneWidget);
    expect(find.text('copper  ·  canal'), findsOneWidget);
    expect(find.text('CURATED BY NANO'), findsOneWidget);
    expect(find.bySemanticsLabel('Generate Image'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _reveal(tester, find.bySemanticsLabel('Remove'));
    await tester.tap(find.bySemanticsLabel('Remove'));
    await _frames(tester);
    expect(find.text('GENERATED VISUAL'), findsNothing);
  });

  testWidgets('Generate without any text asks for words first', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      curate: ({required title, required text, required deep}) async {
        calls++;
        throw StateError('should not be called');
      },
    );
    await _tapGenerate(tester);
    await _frames(tester, 4);
    expect(calls, 0);
    expect(find.text('Write a title or a few lines first.'), findsOneWidget);

    await _write(tester);
    await _frames(tester, 4);
    expect(find.text('Write a title or a few lines first.'), findsNothing);
  });

  testWidgets('a failed generation shows an error with Try Again', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      curate: ({required title, required text, required deep}) async {
        calls++;
        throw StateError('Curation did not finish.');
      },
    );
    await _write(tester);
    await _tapGenerate(tester);
    await _frames(tester);

    expect(find.text('The visual could not be generated.'), findsOneWidget);
    expect(find.text('Curation did not finish.'), findsOneWidget);
    final retry = find.bySemanticsLabel('Try Again');
    expect(retry, findsOneWidget);
    await _reveal(tester, retry);
    await tester.tap(retry);
    await _frames(tester);
    expect(calls, 2);
  });

  testWidgets('text without an image surfaces the image error inline', (
    tester,
  ) async {
    await _pump(
      tester,
      curate: ({required title, required text, required deep}) async =>
          const CurationResult(
            keywords: ['copper'],
            quote: 'A quiet copper evening.',
            caption: '',
            usedUltra: true,
            imageError: 'Painting took too long. Try again or choose an image.',
          ),
    );
    await _write(tester);
    await _tapGenerate(tester);
    await _frames(tester);
    expect(find.text('The visual could not be generated.'), findsOneWidget);
    expect(
      find.text('Painting took too long. Try again or choose an image.'),
      findsOneWidget,
    );
    expect(find.text('REFINED BY ULTRA'), findsOneWidget);
  });

  testWidgets('Go Deeper sends deep and shows the refined caption', (
    tester,
  ) async {
    final pending = Completer<CurationResult>();
    var calls = 0;
    await _pump(
      tester,
      curate: ({required title, required text, required deep}) {
        calls++;
        expect(deep, isTrue);
        expect(text, contains('copper'));
        return pending.future;
      },
    );
    await _write(tester);
    final deeper = find.bySemanticsLabel('Go Deeper');
    await _reveal(tester, deeper);
    await tester.tap(deeper);
    await tester.pump();
    await _frames(tester, 4);
    expect(calls, 1);
    expect(find.bySemanticsLabel('Refining…'), findsOneWidget);

    pending.complete(
      const CurationResult(
        keywords: ['copper', 'canal'],
        quote: 'The water held the colour longer than the sky did.',
        caption: 'A small study of light on brick.',
        usedUltra: true,
        imageUrl: 'https://example.invalid/deeper.jpg',
      ),
    );
    await _frames(tester);
    expect(find.text('REFINED BY ULTRA'), findsOneWidget);
    expect(find.text('A small study of light on brick.'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Publish keeps the generated image URL', (tester) async {
    EditorPublishRequest? saved;
    await _pump(
      tester,
      publish: (request) async {
        saved = request;
      },
      curate: ({required title, required text, required deep}) async =>
          const CurationResult(
            keywords: ['copper', 'canal'],
            quote: 'The water held the colour longer than the sky did.',
            caption: 'A small study of light on brick.',
            usedUltra: true,
            imageUrl: 'https://example.invalid/visual.jpg',
          ),
    );
    await _write(tester);
    await _tapGenerate(tester);
    await _frames(tester);
    await tester.tap(find.bySemanticsLabel('Publish'));
    await _frames(tester, 4);
    final request = saved;
    expect(request, isNotNull);
    expect(request!.generatedImageUrl, 'https://example.invalid/visual.jpg');
    expect(request.editing, isFalse);
    expect(request.keywords, ['copper', 'canal']);
    expect(
      request.quote,
      'The water held the colour longer than the sky did.\n'
      'A small study of light on brick.',
    );
    expect(find.text('Published'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1400));
  });

  testWidgets('Publish does not invent an image URL when painting fails', (
    tester,
  ) async {
    EditorPublishRequest? saved;
    await _pump(
      tester,
      publish: (request) async {
        saved = request;
      },
      curate: ({required title, required text, required deep}) async =>
          const CurationResult(
            keywords: ['copper'],
            quote: 'A quiet copper evening.',
            caption: '',
            usedUltra: false,
            imageError: 'Painting took too long. Try again or choose an image.',
          ),
    );
    await _write(tester);
    await _tapGenerate(tester);
    await _frames(tester);
    await tester.tap(find.bySemanticsLabel('Publish'));
    await _frames(tester, 4);
    expect(saved, isNotNull);
    expect(saved!.generatedImageUrl, isNull);
    expect(saved!.body, contains('copper'));
    await tester.pump(const Duration(milliseconds: 1400));
  });

  for (final scale in [1.0, 1.6]) {
    for (final size in const [Size(320, 568), Size(430, 932)]) {
      testWidgets(
        'composer fits ${size.width.toInt()}w at text ${scale}x with a visual',
        (tester) async {
          await _pump(
            tester,
            size: size,
            textScale: scale,
            curate: ({required title, required text, required deep}) async =>
                const CurationResult(
                  keywords: ['copper', 'canal'],
                  quote: 'The water held the colour longer than the sky did.',
                  caption: 'A small study of light on brick.',
                  usedUltra: false,
                  imageUrl: 'https://example.invalid/visual.jpg',
                ),
          );
          expect(tester.takeException(), isNull);
          await _write(tester);
          await _tapGenerate(tester);
          await _frames(tester);
          expect(tester.takeException(), isNull);
          expect(find.bySemanticsLabel('Publish'), findsOneWidget);
          expect(find.bySemanticsLabel('Public'), findsOneWidget);
          await tester.fling(
            find.byType(SingleChildScrollView),
            const Offset(0, -1600),
            2400,
          );
          await _frames(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
