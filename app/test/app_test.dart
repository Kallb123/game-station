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

  testWidgets('the scaffold screen renders in both themes', (tester) async {
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpWidget(const GameStationApp());
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  });
}
