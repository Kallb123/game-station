// The home screen's own rules: the size floors it inherits, that it survives a
// large text scale on a small phone, and that the two cards are told apart by
// more than their colour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/avatars.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/home/home_screen.dart';

import '../../app_harness.dart';

void main() {
  MemorySaveStore storeWithAvatar(AvatarId avatar) => MemorySaveStore(
    initial: SaveData(
      activeProfileId: 'p1',
      profiles: [
        Profile(id: 'p1', name: 'Bo', avatar: avatar, createdAt: testClock()),
      ],
    ),
  );

  testWidgets('every control clears the tap-target floor', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    for (final card in const ['Sudoku', 'Arcade']) {
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(card),
                matching: find.byType(FilledButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(AppTapTargets.primary),
        reason: '$card is a primary action',
      );
    }
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(AppTapTargets.min),
    );
    expect(
      tester.getSize(find.byTooltip('Settings')).height,
      greaterThanOrEqualTo(AppTapTargets.min),
    );
  });

  testWidgets('it fits a small phone at 200% text scale', (tester) async {
    // The narrowest target the app claims to support, at the largest text
    // scale PLAN.md §9 promises. An overflow here fails the test on its own.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Arcade'), findsOneWidget);
    expect(find.text('Playing as Player 1'), findsOneWidget);
  });

  testWidgets('the two cards differ by icon as well as by colour', (
    tester,
  ) async {
    // Colour never carries information on its own (`tokens.dart`), so a player
    // who cannot tell the two colours apart still has a glyph and a word.
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(find.byIcon(homeSudokuIcon), findsOneWidget);
    expect(find.byIcon(homeArcadeIcon), findsOneWidget);
    expect(homeSudokuIcon, isNot(homeArcadeIcon));

    final palette = AppPalette.of(Brightness.light);
    expect(
      AppTheme.roleScheme(palette.sudoku, Brightness.light).primary,
      isNot(AppTheme.roleScheme(palette.arcade, Brightness.light).primary),
    );
  });

  testWidgets('the chip shows the active profile picture', (tester) async {
    await pumpApp(tester, store: storeWithAvatar(AvatarId.panda));

    expect(find.text('Playing as Bo'), findsOneWidget);
    expect(find.byIcon(avatarIcon(AvatarId.panda)), findsOneWidget);
  });
}
