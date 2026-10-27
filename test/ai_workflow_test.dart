import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspiration_museum/community_feed.dart';
import 'package:inspiration_museum/community_post.dart';
import 'package:inspiration_museum/daily_letter_card.dart';
import 'package:inspiration_museum/daily_push.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';
import 'package:inspiration_museum/services/curation_service.dart';
import 'package:inspiration_museum/services/db_service.dart';

CommunityPost _post(String id) {
  return CommunityPost(
    id: id,
    author: 'Member',
    theme: 'CITY',
    themeEn: 'CITY',
    keywords: const ['street'],
    text: 'A note',
    quote: 'A quote',
    quoteAuthor: '',
  );
}

void main() {
  setUpAll(() async {
    await runZonedGuarded(() async {
      expect(CanvasType.body, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (error, stack) {});
  });

  test('curation keeps an http image and drops a bad address', () {
    final painted = CurationResult.fromResponse({
      'keywords': [' copper ', '', 'canal'],
      'quote': ' The water held the colour. ',
      'caption': ' A study. ',
      'used_ultra': true,
      'image_url': 'https://example.invalid/visual.jpg',
      'image_error': '',
    });
    expect(painted.keywords, ['copper', 'canal']);
    expect(painted.quote, 'The water held the colour.');
    expect(painted.caption, 'A study.');
    expect(painted.usedUltra, isTrue);
    expect(painted.imageUrl, 'https://example.invalid/visual.jpg');
    expect(painted.imageError, isNull);

    final textOnly = CurationResult.fromResponse({
      'keywords': ['copper'],
      'quote': 'A quiet evening.',
      'used_ultra': 'true',
      'image_url': 'not-a-url',
      'image_error': 'Painting took too long.',
    });
    expect(textOnly.usedUltra, isFalse);
    expect(textOnly.imageUrl, isNull);
    expect(textOnly.imageError, 'Painting took too long.');
  });

  test('curation rejects a response with no quote', () {
    expect(
      () => CurationResult.fromResponse({
        'keywords': ['copper'],
        'quote': '  ',
      }),
      throwsStateError,
    );
    expect(
      () => CurationResult.fromResponse({'quote': 'Only a sentence.'}),
      throwsStateError,
    );
  });

  test(
    'daily letter prefers a stored copy over the catalog and the stock prompt',
    () {
      const cached = DailyPush(keyword: 'CACHED', quote: 'From this device.');
      const remote = DailyPush(keyword: 'REMOTE', quote: 'From the account.');
      const prepared = DailyPush(
        keyword: 'PREPARED',
        quote: 'Written ahead.',
        whyToday: 'Because of the portrait.',
      );
      final catalog = {
        'keyword': 'CATALOG',
        'quote': 'A letter from the shelves.',
        'theme_name': 'CITY',
      };

      expect(
        resolveDailyLetter(cached: cached, prepared: prepared).source,
        DailyLetterSource.cache,
      );
      expect(
        resolveDailyLetter(remote: remote, prepared: prepared).push.keyword,
        'REMOTE',
      );
      expect(
        resolveDailyLetter(prepared: prepared, randomCatalog: catalog).source,
        DailyLetterSource.prepared,
      );
      final fromCatalog = resolveDailyLetter(randomCatalog: catalog);
      expect(fromCatalog.source, DailyLetterSource.catalog);
      expect(fromCatalog.push.isStockFallback, isFalse);
      expect(fromCatalog.push.keyword, 'CATALOG');

      expect(
        resolveDailyLetter(randomCatalog: {'keyword': '', 'quote': ''}).source,
        DailyLetterSource.fallback,
      );
      expect(
        resolveDailyLetter(randomUnavailable: true).push.isStockFallback,
        isTrue,
      );
      expect(resolveDailyLetter().push, DailyPush.fallback);
      expect(DailyPush.fromJson({}).isStockFallback, isTrue);
      expect(
        DailyPush.fromJson({
          'keyword': 'MARGIN',
          'quote': 'A different sentence.',
        }).isStockFallback,
        isFalse,
      );
    },
  );

  test('a non-http letter image is not kept', () {
    final push = DailyPush.fromJson({
      'keyword': 'LIGHT',
      'quote': 'The room kept the afternoon.',
      'image_url': 'post_images/not-public',
    });
    expect(push.imageUrl, isEmpty);
    expect(push.isStockFallback, isFalse);
  });

  test('rank ids ignore a bad payload and blank entries', () {
    expect(rankIdsFromResponse(null), isEmpty);
    expect(rankIdsFromResponse({'error': '首页还没有排好。'}), isEmpty);
    expect(rankIdsFromResponse({'ids': 'nope'}), isEmpty);
    expect(
      rankIdsFromResponse({
        'ids': [' post-a ', '', 'post-b'],
      }),
      ['post-a', 'post-b'],
    );
  });

  test('ranking cannot introduce a post that is not public', () {
    final posts = [_post('a'), _post('b'), _post('c')];
    final ordered = placeRankedFirst(posts, ['c', 'missing', 'a', 'c', '']);
    expect(ordered.map((post) => post.id), ['c', 'a', 'b']);
    expect(placeRankedFirst(posts, const []).map((post) => post.id), [
      'a',
      'b',
      'c',
    ]);
  });

  testWidgets('the stock prompt is not labeled as today\'s discovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 340,
            child: DailyLetterCard(push: DailyPush.fallback, onOpen: null),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('STARTING PROMPT'), findsOneWidget);
    expect(find.textContaining("TODAY'S DISCOVERY"), findsNothing);
    expect(find.textContaining(DailyPush.fallback.quote), findsOneWidget);
  });

  testWidgets('a prepared letter keeps the discovery label', (tester) async {
    const prepared = DailyPush(
      keyword: 'BRICK',
      quote: 'The wall kept a warmer colour.',
      whyToday: 'You wrote about walking home.',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 340,
            child: DailyLetterCard(push: prepared, onOpen: null),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining("TODAY'S DISCOVERY"), findsOneWidget);
    expect(find.textContaining('STARTING PROMPT'), findsNothing);
    expect(prepared.isStockFallback, isFalse);
  });
}
