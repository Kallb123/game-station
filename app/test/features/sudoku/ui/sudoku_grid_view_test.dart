// The board's tests.
//
// Both sizes, everywhere: a grid that transposed the box shape would draw a 9x9
// correctly and a 6x6 with its boxes 3 wide and 2 tall, which still looks like
// a Sudoku. That is the bug `PLAN.md` §3.6 tests for in the engine, and this is
// the same test one layer up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/ui/theme.dart';
import 'package:game_station/core/ui/tokens.dart';
import 'package:game_station/features/sudoku/model/sudoku_session.dart';
import 'package:game_station/features/sudoku/ui/sudoku_cell.dart';
import 'package:game_station/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/ui/ui_harness.dart';
import '../puzzle_fixtures.dart';

void main() {
  final small = PuzzleId.parse('sudoku:6x6:easy:3');
  final large = PuzzleId.parse('sudoku:9x9:easy:3');

  /// Pumps [session]'s board in a box of [side] by [side] logical pixels.
  Future<void> pumpGrid(
    WidgetTester tester,
    SudokuSession session, {
    double side = 400,
  }) => pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: side,
          child: SudokuGridView(session: session),
        ),
      ),
    ),
    theme: AppTheme.day(),
  );

  /// The outer [DecoratedBox] of the cell at [index] — the one carrying its
  /// share of the grid lines and its highlight.
  BoxDecoration decorationOf(WidgetTester tester, int index) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byKey(ValueKey<int>(index)),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  group('the box lines', () {
    /// The columns whose left-hand line is a box line rather than a cell line.
    Set<int> thickColumns(SudokuSpec spec) => {
      for (var col = 0; col < spec.digits; col++)
        if (sudokuCellBorder(
              spec,
              spec.indexAt(0, col),
              const Color(0xFF000000),
            ).left.width ==
            AppBorders.gridBox)
          col,
    };

    /// The rows whose top line is a box line.
    Set<int> thickRows(SudokuSpec spec) => {
      for (var row = 0; row < spec.digits; row++)
        if (sudokuCellBorder(
              spec,
              spec.indexAt(row, 0),
              const Color(0xFF000000),
            ).top.width ==
            AppBorders.gridBox)
          row,
    };

    test('fall after columns 3 and 6 and rows 3 and 6 at 9x9', () {
      expect(thickColumns(SudokuSpec.s9x9), {3, 6});
      expect(thickRows(SudokuSpec.s9x9), {3, 6});
    });

    test('fall after column 3 and rows 2 and 4 at 6x6', () {
      // The case that catches a transposed box: a 3-tall, 2-wide box would put
      // these at columns 2 and 4 and row 3, and would pass the 9x9 case above.
      expect(thickColumns(SudokuSpec.s6x6), {3});
      expect(thickRows(SudokuSpec.s6x6), {2, 4});
    });

    test('are not drawn twice down the same line', () {
      // Only the top and left, so the line between two cells belongs to one of
      // them; the frame around the outside is the grid's.
      final border = sudokuCellBorder(
        SudokuSpec.s9x9,
        0,
        const Color(0xFF000000),
      );

      expect(border.top, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
      expect(border.bottom, BorderSide.none);
    });

    testWidgets('are what the cells are actually drawn with', (tester) async {
      await pumpGrid(tester, fixtureSession(large));

      Border borderOf(int index) =>
          decorationOf(tester, index).border! as Border;

      // Cell 3 is row 0, column 3: the first column of the second box.
      expect(borderOf(3).left.width, AppBorders.gridBox);
      expect(borderOf(2).left.width, AppBorders.hairline);
      expect(
        borderOf(27).top.width,
        AppBorders.gridBox,
        reason: 'row 3 starts a box band',
      );
    });
  });

  group('the board', () {
    testWidgets('is square, on the shorter side of the space it is given', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 500,
              child: SudokuGridView(session: fixtureSession(large)),
            ),
          ),
        ),
        theme: AppTheme.day(),
      );

      final frame = find
          .descendant(
            of: find.byType(SudokuGridView),
            matching: find.byType(DecoratedBox),
          )
          .first;

      expect(tester.getSize(frame), const Size(300, 300));
    });

    for (final id in [small, large]) {
      testWidgets('draws one cell per cell of a ${id.spec.label}', (
        tester,
      ) async {
        await pumpGrid(tester, fixtureSession(id));

        expect(find.byType(SudokuCell), findsNWidgets(id.spec.cells));
      });

      testWidgets('draws every clue of a ${id.spec.label}', (tester) async {
        final session = fixtureSession(id);
        await pumpGrid(tester, session);

        for (var index = 0; index < id.spec.cells; index++) {
          final digit = session.digitAt(index);
          expect(
            find.descendant(
              of: find.byKey(ValueKey<int>(index)),
              matching: find.text('$digit'),
            ),
            digit == 0 ? findsNothing : findsOneWidget,
          );
        }
      });
    }
  });

  group('a tap', () {
    /// The first empty cell of [session], which is the one a test can play in.
    int firstEmpty(SudokuSession session) {
      for (var index = 0; index < session.spec.cells; index++) {
        if (!session.isGiven(index)) return index;
      }
      throw StateError('a puzzle with no empty cell');
    }

    testWidgets('selects the cell it landed on', (tester) async {
      final session = fixtureSession(large);
      await pumpGrid(tester, session);
      final target = firstEmpty(session);

      await tester.tap(find.byKey(ValueKey<int>(target)));
      await tester.pump();

      expect(session.selected, target);
      expect(decorationOf(tester, target).color, isNotNull);
    });

    testWidgets('washes the row, the column and the box, and nothing else', (
      tester,
    ) async {
      final session = fixtureSession(large);
      final spec = session.spec;
      await pumpGrid(tester, session);
      // An empty cell, so that no cell is highlighted for sharing its digit
      // and the wash below is the only thing under test.
      final target = firstEmpty(session);

      await tester.tap(find.byKey(ValueKey<int>(target)));
      await tester.pump();

      for (var index = 0; index < spec.cells; index++) {
        final isPeer =
            spec.rowOf(index) == spec.rowOf(target) ||
            spec.colOf(index) == spec.colOf(target) ||
            spec.boxOf(index) == spec.boxOf(target);

        expect(
          decorationOf(tester, index).color,
          isPeer ? isNotNull : isNull,
          reason: 'cell $index',
        );
      }
    });

    testWidgets('highlights every cell holding the same digit', (tester) async {
      final session = fixtureSession(large);
      final spec = session.spec;
      await pumpGrid(tester, session);
      // A given, and one whose digit appears somewhere outside its row, column
      // and box — which is every digit of a solvable grid, since the digit
      // appears once per box.
      final target = [
        for (var index = 0; index < spec.cells; index++)
          if (session.isGiven(index)) index,
      ].first;
      final digit = session.digitAt(target);
      final elsewhere = [
        for (var index = 0; index < spec.cells; index++)
          if (session.digitAt(index) == digit &&
              spec.rowOf(index) != spec.rowOf(target) &&
              spec.colOf(index) != spec.colOf(target) &&
              spec.boxOf(index) != spec.boxOf(target))
            index,
      ];

      await tester.tap(find.byKey(ValueKey<int>(target)));
      await tester.pump();

      expect(elsewhere, isNotEmpty);
      for (final index in elsewhere) {
        expect(decorationOf(tester, index).color, isNotNull, reason: '$index');
      }
    });

    testWidgets('reaches a screen reader as its row, column and contents', (
      tester,
    ) async {
      final session = fixtureSession(large);
      await pumpGrid(tester, session);
      final target = firstEmpty(session);

      expect(
        tester.getSemantics(find.byKey(ValueKey<int>(target))),
        isSemantics(
          label:
              'row ${session.spec.rowOf(target) + 1}, '
              'column ${session.spec.colOf(target) + 1}, empty',
          isButton: true,
          isSelected: false,
          // A cell that announces itself as a button has to be activatable as
          // one: the tap lives on this node, not only on the gesture detector
          // whose semantics the label excludes.
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(ValueKey<int>(target)));
      await tester.pump();

      expect(
        tester.getSemantics(find.byKey(ValueKey<int>(target))),
        isSemantics(isSelected: true),
      );
    });
  });

  group('pencil marks', () {
    testWidgets('are laid out in the shape of a box', (tester) async {
      // A 6x6's box is 2 rows of 3, so its notes are too: 4 sits under 1.
      final session = fixtureSession(small);
      final spec = session.spec;
      final target = [
        for (var index = 0; index < spec.cells; index++)
          if (!session.isGiven(index)) index,
      ].first;
      session
        ..select(target)
        ..pencilMode = true
        ..enter(1)
        ..enter(3)
        ..enter(4);

      await pumpGrid(tester, session);

      Offset noteAt(String digit) => tester.getCenter(
        find.descendant(
          of: find.byKey(ValueKey<int>(target)),
          matching: find.text(digit),
        ),
      );

      expect(noteAt('1').dy, noteAt('3').dy);
      expect(noteAt('4').dy, greaterThan(noteAt('1').dy));
      expect(noteAt('4').dx, noteAt('1').dx);
      expect(
        find.descendant(
          of: find.byKey(ValueKey<int>(target)),
          matching: find.text('2'),
        ),
        findsNothing,
      );
    });

    testWidgets('give way to a digit entered over them', (tester) async {
      final session = fixtureSession(large);
      final target = [
        for (var index = 0; index < session.spec.cells; index++)
          if (!session.isGiven(index)) index,
      ].first;
      session
        ..select(target)
        ..pencilMode = true
        ..enter(4);
      await pumpGrid(tester, session);

      session
        ..pencilMode = false
        ..enter(7);
      await tester.pump();

      final cell = find.byKey(ValueKey<int>(target));
      expect(
        find.descendant(of: cell, matching: find.text('7')),
        findsOneWidget,
      );
      expect(find.descendant(of: cell, matching: find.text('4')), findsNothing);
    });
  });

  testWidgets('a wrong digit is underlined as well as recoloured', (
    tester,
  ) async {
    final session = fixtureSession(large);
    final record = fixtureRecord(large);
    final target = [
      for (var index = 0; index < session.spec.cells; index++)
        if (!session.isGiven(index)) index,
    ].first;
    final right = int.parse(record.solution[target]);
    final wrong = right % session.spec.digits + 1;

    session
      ..select(target)
      ..enter(wrong);
    await pumpGrid(tester, session);

    // Colour is never the only signal (`AGENTS.md`, `PLAN.md` §9).
    final style = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<int>(target)),
            matching: find.text('$wrong'),
          ),
        )
        .style;
    expect(style?.decoration, TextDecoration.underline);
  });

  testWidgets('a digit is drawn the same size at 200% text scale', (
    tester,
  ) async {
    // An 80% larger digit in an unchanged cell is a clipped digit
    // (`PLAN-phase-3.md` §4.5), so the board sizes its own text from the cell
    // and the keypad and chrome around it scale normally.
    Future<Size> digitSizeAt(double textScale) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 400,
              child: SudokuGridView(session: fixtureSession(large)),
            ),
          ),
        ),
        theme: AppTheme.day(),
        textScale: textScale,
      );

      return tester.getSize(
        find
            .descendant(
              of: find.byType(SudokuGridView),
              matching: find.byType(Text),
            )
            .first,
      );
    }

    expect(await digitSizeAt(2), await digitSizeAt(1));
  });
}
