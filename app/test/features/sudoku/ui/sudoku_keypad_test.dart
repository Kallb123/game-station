// The keypad's tests.
//
// The 56 dp floor is `PLAN.md` §4.2 and it is the one rule here that a child
// feels directly: a button under it is a button they miss.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/sudoku/data/puzzle_record.dart';
import 'package:zibo_games/features/sudoku/model/sudoku_session.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_keypad.dart';

import '../../../core/ui/ui_harness.dart';
import '../puzzle_fixtures.dart';

void main() {
  final small = PuzzleId.parse('sudoku:6x6:easy:5');
  final large = PuzzleId.parse('sudoku:9x9:easy:5');

  Future<void> pumpKeypad(
    WidgetTester tester,
    SudokuSession session, {
    ThemeData? theme,
  }) => pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: SizedBox(width: 360, child: SudokuKeypad(session: session)),
      ),
    ),
    theme: theme ?? AppTheme.day(),
  );

  /// The first cell of [session] a child could type into.
  int firstEmpty(SudokuSession session) => emptyCells(session).first;

  /// The control labelled [tooltip].
  ///
  /// By its tooltip's ancestor rather than by the tooltip itself: `IconButton`
  /// builds the `Tooltip` inside itself, so `find.byTooltip` lands on the
  /// wrapper and not on the button whose `onPressed` these tests read.
  Finder control(String tooltip) => find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );

  group('the digits', () {
    for (final id in [small, large]) {
      testWidgets('are ${id.spec.digits} of them for a ${id.spec.label}', (
        tester,
      ) async {
        await pumpKeypad(tester, fixtureSession(id));

        for (var digit = 1; digit <= id.spec.digits; digit++) {
          expect(find.widgetWithText(FilledButton, '$digit'), findsOneWidget);
        }
        expect(
          find.byType(FilledButton),
          findsNWidgets(id.spec.digits),
          reason: 'no digit the grid does not have',
        );
      });

      testWidgets('are laid out ${id.spec.boxCols} to a row at '
          '${id.spec.label}', (tester) async {
        // The pad is one box of the grid: 3x3 for a 9x9, the shape of a phone
        // keypad, and 2x3 for a 6x6. Both come from `spec.boxCols`.
        await pumpKeypad(tester, fixtureSession(id));

        double topOf(int digit) => tester.getTopLeft(find.text('$digit')).dy;
        double leftOf(int digit) => tester.getTopLeft(find.text('$digit')).dx;

        for (var col = 2; col <= id.spec.boxCols; col++) {
          expect(topOf(col), topOf(1), reason: '$col shares row 1');
          expect(leftOf(col), greaterThan(leftOf(col - 1)));
        }
        expect(
          topOf(id.spec.boxCols + 1),
          greaterThan(topOf(1)),
          reason: 'the row wraps after ${id.spec.boxCols}',
        );
        expect(leftOf(id.spec.boxCols + 1), leftOf(1));
      });
    }

    testWidgets('enter into the selected cell', (tester) async {
      final session = fixtureSession(large);
      final target = firstEmpty(session);
      session.select(target);
      await pumpKeypad(tester, session);

      await tester.tap(find.widgetWithText(FilledButton, '5'));
      await tester.pump();

      expect(session.digitAt(target), 5);
    });

    testWidgets(
      'grey out a digit once it is on the board as many times as a row',
      (tester) async {
        // A clueless board, so the count starts at zero and the test does not
        // depend on how many of the digit the fixture's own clues happen to
        // give away.
        final session = SudokuSession.start(
          id: large,
          record: PuzzleRecord(
            clues: PuzzleRecord.emptyCell * large.spec.cells,
            solution: fixtureRecord(large).solution,
          ),
        );
        const digit = 5;
        await pumpKeypad(tester, session);

        bool enabled() =>
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '$digit'),
                )
                .onPressed !=
            null;

        expect(enabled(), isTrue);

        for (var index = 0; index < session.spec.digits; index++) {
          session
            ..select(index)
            ..enter(digit);
        }
        await tester.pump();

        expect(enabled(), isFalse);
      },
    );

    testWidgets('write a pencil mark instead when pencil mode is on', (
      tester,
    ) async {
      final session = fixtureSession(large);
      final target = firstEmpty(session);
      session.select(target);
      await pumpKeypad(tester, session);

      await tester.tap(find.byTooltip('Pencil marks'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '5'));
      await tester.pump();

      expect(session.digitAt(target), 0);
      expect(session.notesAt(target), 1 << 4);
    });
  });

  group('the controls', () {
    testWidgets('erase the selected cell', (tester) async {
      final session = fixtureSession(large);
      final target = firstEmpty(session);
      session
        ..select(target)
        ..enter(5);
      await pumpKeypad(tester, session);

      await tester.tap(find.byTooltip('Erase'));
      await tester.pump();

      expect(session.digitAt(target), 0);
    });

    testWidgets('show the pencil mode as a glyph, not only a colour', (
      tester,
    ) async {
      final session = fixtureSession(large);
      await pumpKeypad(tester, session);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.byTooltip('Pencil marks'));
      await tester.pump();

      expect(session.pencilMode, isTrue);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('undo and redo follow what there is to undo', (tester) async {
      final session = fixtureSession(large);
      final target = firstEmpty(session);
      session.select(target);
      await pumpKeypad(tester, session);

      bool enabled(String tooltip) =>
          tester.widget<IconButton>(control(tooltip)).onPressed != null;

      expect(enabled('Undo'), isFalse);
      expect(enabled('Redo'), isFalse);

      await tester.tap(find.widgetWithText(FilledButton, '5'));
      await tester.pump();
      expect(enabled('Undo'), isTrue);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(session.digitAt(target), 0);
      expect(enabled('Undo'), isFalse);
      expect(enabled('Redo'), isTrue);

      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(session.digitAt(target), 5);
    });

    testWidgets('hint fills a cell, whatever is selected', (tester) async {
      // Enabled with nothing selected, unlike undo and redo: the hint decides
      // which cell it is about, so there is no state in which it does nothing
      // (`PLAN-phase-3.md` §4.6). What it fills a cell *with* is the session's
      // test, not this one.
      final session = fixtureSession(large);
      await pumpKeypad(tester, session);

      expect(tester.widget<IconButton>(control('Hint')).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Hint'));
      await tester.pump();

      expect(session.hints, 1);
      expect(session.selected, isNotNull);
      expect(session.digitAt(session.selected!), isNot(0));
    });
  });

  for (final entry in appThemes.entries) {
    testWidgets('every button clears the 56 dp floor in ${entry.key}', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpKeypad(tester, fixtureSession(large), theme: entry.value());

      void expectAboveFloor(Finder buttons) {
        for (var at = 0; at < buttons.evaluate().length; at++) {
          final size = tester.getSize(buttons.at(at));
          expect(
            size.shortestSide,
            greaterThanOrEqualTo(AppTapTargets.min),
            reason: 'button $at of ${buttons.evaluate().length}',
          );
        }
      }

      expectAboveFloor(find.byType(FilledButton));
      expectAboveFloor(find.byType(IconButton));
    });
  }
}
