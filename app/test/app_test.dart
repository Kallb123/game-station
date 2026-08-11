import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/app.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

void main() {
  testWidgets('app boots to the scaffold screen', (tester) async {
    await tester.pumpWidget(const GameStationApp());

    expect(find.text('Game Station'), findsOneWidget);
    expect(find.text('No ads. No network. No tracking.'), findsOneWidget);
  });

  testWidgets('the engine package resolves through the path dependency', (
    tester,
  ) async {
    await tester.pumpWidget(const GameStationApp());

    expect(
      find.text('Scaffold — puzzle engine v$generatorVersion'),
      findsOneWidget,
    );
  });

  // One test per brightness rather than a loop inside one: `MediaQuery.fromView`
  // does not pick up a change to the dispatcher's test value on a tree that is
  // already built, so a second iteration would keep the first brightness and
  // the assertion would be testing the harness rather than the app.
  for (final brightness in Brightness.values) {
    testWidgets('the scaffold screen follows $brightness', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = brightness;

      await tester.pumpWidget(const GameStationApp());

      // Not just "it did not throw": assert the theme actually followed, so a
      // missing darkTheme would fail here rather than pass silently.
      final context = tester.element(find.text('Game Station'));
      expect(Theme.of(context).brightness, brightness);
    });
  }
}
