import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspiration_museum/auth_screen.dart';
import 'package:inspiration_museum/judge_demo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    );
  });

  Future<void> pumpAuth(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pump();
  }

  testWidgets('Explore Judge Demo is visible and leaves the password empty', (
    tester,
  ) async {
    await pumpAuth(tester, const Size(1280, 900));

    expect(find.text('Explore Judge Demo'), findsOneWidget);
    expect(find.text('Explore our prepared demo collection.'), findsOneWidget);
    expect(find.text('JUDGE ENTRANCE'), findsNothing);

    await tester.tap(find.text('Explore Judge Demo'));
    await tester.pump();

    expect(
      find.text('Use the demo password provided in the hackathon submission.'),
      findsOneWidget,
    );
    expect(find.text('Enter Museum'), findsOneWidget);
    expect(find.text('ENTER'), findsNothing);
    expect(find.text('Register'), findsNothing);
    expect(find.text(JudgeDemo.publicEmail), findsOneWidget);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(1));
    expect(fields.single.obscureText, isTrue);
    expect(fields.single.controller?.text, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Back to sign in'));
    await tester.pump();
    expect(find.text('ENTER'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Explore Judge Demo'), findsOneWidget);
  });

  testWidgets('the judge entrance fits a narrow phone width', (tester) async {
    await pumpAuth(tester, const Size(320, 800));
    expect(find.text('Explore Judge Demo'), findsOneWidget);
    await tester.tap(find.text('Explore Judge Demo'));
    await tester.pump();
    expect(find.text(JudgeDemo.publicEmail), findsOneWidget);
    expect(find.text('Enter Museum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
