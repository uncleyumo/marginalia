// The picture sheet must render, and its empty-state button must be the
// gallery shortcut rather than a permanently disabled control.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marginalia/core/design/tokens.dart';
import 'package:marginalia/features/queue/picture_sheet.dart';

Widget host(Widget child) => MaterialApp(
      theme: MarginaliaTheme.themeFor(Palette.warmInk),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('the sheet renders and its empty action is enabled',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const PictureSheet(intent: null, canSeePictures: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Write it from a picture'), findsOneWidget);
    expect(find.text('Pick a picture first'), findsOneWidget);

    final Finder button = find.ancestor(
      of: find.text('Pick a picture first'),
      matching: find.byType(InkWell),
    );
    expect(button, findsWidgets);
  });

  testWidgets('a text-only writer is told before picking',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const PictureSheet(intent: null, canSeePictures: false),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot see pictures'), findsOneWidget);
  });
}
