import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspiration_museum/brand/museum_brand.dart';
import 'package:inspiration_museum/living_canvas/living_canvas.dart';

double _distanceToPath(Path path, Offset point) {
  var best = double.infinity;
  for (final metric in path.computeMetrics()) {
    const step = 0.4;
    for (var distance = 0.0; distance <= metric.length; distance += step) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;
      final gap = (tangent.position - point).distance;
      if (gap < best) best = gap;
    }
  }
  return best;
}

void main() {
  setUpAll(() async {
    await runZonedGuarded(() async {
      expect(CanvasType.section, isNotNull);
      expect(CanvasType.overline, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (error, stack) {});
  });

  test(
    'the frame is round on three corners and square on the bottom-right',
    () {
      const size = Size(128, 128);
      final path = MuseumMarkPaths.frame(size);
      final stroke = MuseumMarkPaths.strokeWidth(size);
      final radius = (size.shortestSide - stroke) * 0.28;
      final bottomRight = Offset(
        size.width - stroke / 2,
        size.height - stroke / 2,
      );
      final topLeft = Offset(stroke / 2, stroke / 2);
      final topRight = Offset(size.width - stroke / 2, stroke / 2);
      final bottomLeft = Offset(stroke / 2, size.height - stroke / 2);

      expect(_distanceToPath(path, bottomRight), lessThan(0.8));
      expect(_distanceToPath(path, topLeft), greaterThan(radius * 0.2));
      expect(_distanceToPath(path, topRight), greaterThan(radius * 0.2));
      expect(_distanceToPath(path, bottomLeft), greaterThan(radius * 0.2));
    },
  );

  test('the pier stays on the left and the sparkle is a four-point star', () {
    const size = Size(128, 128);
    final pier = MuseumMarkPaths.pier(size).getBounds();
    final star = MuseumMarkPaths.sparkle(size);
    final bounds = star.getBounds();

    expect(pier.center.dx, lessThan(size.width * 0.45));
    expect(bounds.center.dx, greaterThan(size.width * 0.55));
    expect(pier.right, lessThan(bounds.left));

    final center = bounds.center;
    expect(star.contains(center), isTrue);
    expect(star.contains(center + const Offset(0, -8)), isTrue);
    expect(star.contains(center + const Offset(8, 0)), isTrue);
    expect(star.contains(center + const Offset(0, 8)), isTrue);
    expect(star.contains(center + const Offset(-8, 0)), isTrue);
    expect(star.contains(center + const Offset(10, 10)), isFalse);
  });

  testWidgets('the mark paints cleanly from 24 to 128', (tester) async {
    for (final size in const [24.0, 32.0, 40.0, 64.0, 128.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: InspirationMuseumMark(size: size)),
          ),
        ),
      );
      expect(find.byType(InspirationMuseumMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'the home brand header fits a narrow phone and keeps its actions',
    (tester) async {
      var searches = 0;
      var filters = 0;

      Future<void> pump(Size size, double scale) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(
          MaterialApp(
            theme: LivingCanvasTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SizedBox(
                  height: 64,
                  child: InspirationMuseumBrandHeader(
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => searches++,
                          icon: const Icon(Icons.search),
                          tooltip: 'Search',
                        ),
                        IconButton(
                          onPressed: () => filters++,
                          icon: const Icon(Icons.tune),
                          tooltip: 'Backstage',
                        ),
                        const CircleAvatar(radius: 16, child: Text('A')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      addTearDown(tester.view.reset);

      for (final size in const [Size(320, 640), Size(390, 844)]) {
        for (final scale in const [1.0, 1.4]) {
          await pump(size, scale);
          expect(find.text('Inspiration Museum'), findsOneWidget);
          expect(find.text('灵感博物馆'), findsNothing);
          expect(find.text('INSPIRATION MUSEUM'), findsNothing);
          expect(find.text('A MUSEUM OF A BRIGHTER YOU'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }

      await tester.tap(find.byTooltip('Search'));
      await tester.tap(find.byTooltip('Backstage'));
      expect(searches, 1);
      expect(filters, 1);
    },
  );

  testWidgets('the tagline is available only when requested', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LivingCanvasTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 360,
            child: InspirationMuseumBrandHeader(showTagline: true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Inspiration Museum'), findsOneWidget);
    expect(find.text('A MUSEUM OF A BRIGHTER YOU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
