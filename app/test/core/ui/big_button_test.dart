import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('reports its label and calls back on a tap', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: BigButton(
            icon: Icons.videogame_asset,
            label: 'Arcade',
            onPressed: () => taps++,
          ),
        ),
      ),
      theme: AppTheme.day(),
    );

    expect(find.text('Arcade'), findsOneWidget);
    await tester.tap(find.byType(BigButton));
    expect(taps, 1);
  });

  testWidgets('is disabled when given no callback', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Center(
          child: BigButton(
            icon: Icons.videogame_asset,
            label: 'Arcade',
            onPressed: null,
          ),
        ),
      ),
      theme: AppTheme.day(),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
  });

  // The rule from AGENTS.md and PLAN.md §5: nothing is signalled by colour
  // alone. A player who cannot separate the two container colours still has
  // the check icon and the border.
  testWidgets('signals selection with an icon, not only a colour', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BigButton(
                icon: Icons.pets,
                label: 'Ana',
                onPressed: () {},
                selected: true,
              ),
              BigButton(icon: Icons.pets, label: 'Sam', onPressed: () {}),
            ],
          ),
        ),
      ),
      theme: AppTheme.day(),
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // The selection also reaches a screen reader, on the button's own node
    // rather than a second one beside it.
    expect(
      tester.getSemantics(find.byType(BigButton).first),
      isSemantics(label: 'Ana', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byType(BigButton).last),
      isSemantics(label: 'Sam', isButton: true, isSelected: false),
    );
  });

  testWidgets('selecting a button does not move its neighbours', (
    tester,
  ) async {
    Future<Size> sizeWith({required bool selected}) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: BigButton(
                icon: Icons.pets,
                label: 'Ana',
                onPressed: () {},
                selected: selected,
              ),
            ),
          ),
        ),
        theme: AppTheme.day(),
      );
      return tester.getSize(find.byType(BigButton));
    }

    // The unselected button carries a transparent border of the same width, so
    // the two sizes match; without it, selecting one would nudge a whole row.
    expect(await sizeWith(selected: false), await sizeWith(selected: true));
  });

  testWidgets('wraps a long label at 200% text scale instead of overflowing', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: BigButton(
            icon: Icons.grid_on,
            label: 'Sudoku puzzle of the day',
            onPressed: () {},
          ),
        ),
      ),
      theme: AppTheme.day(),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    // Taller than the floor, which is what "wrapped" looks like from outside:
    // the label did not shrink and it was not clipped.
    expect(
      tester.getSize(find.byType(BigButton)).height,
      greaterThan(AppTapTargets.primary),
    );
  });
}
