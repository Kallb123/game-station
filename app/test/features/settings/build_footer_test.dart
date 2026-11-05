// The settings footer's *home build* marker: shown for the private flavour and
// for nothing else, since it is the only way to tell the two builds apart on a
// tablet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/build_info.dart';
import 'package:zibo_games/features/settings/settings_screen.dart';

void main() {
  Future<void> pumpFooter(WidgetTester tester, String? flavor) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuildFooter(
            info: BuildInfo(
              version: '0.1.0+1',
              timestamp: '2026-08-15T13:07:41Z',
              flavor: flavor,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('says home build for the private flavour', (tester) async {
    await pumpFooter(tester, 'private');

    expect(find.textContaining('home build'), findsOneWidget);
  });

  testWidgets('says nothing of it for the store flavour', (tester) async {
    await pumpFooter(tester, 'store');

    expect(find.textContaining('home build'), findsNothing);
    expect(find.textContaining('Version 0.1.0+1'), findsOneWidget);
  });

  testWidgets('says nothing of it with no flavour', (tester) async {
    await pumpFooter(tester, null);

    expect(find.textContaining('home build'), findsNothing);
  });
}
