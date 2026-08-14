// One cell of the board: its digit or its pencil marks, its share of the grid
// lines, and whatever highlight the current selection gives it.
//
// **Each cell listens to the session itself and rebuilds only when its own
// slice of it changed** (`PLAN-phase-3.md` §4.5). Eighty-one cells rebuilt on
// every keystroke is the shape that gets slow on a cheap tablet, and the
// alternative — one `ListenableBuilder` around the whole grid — is exactly that
// shape. [_CellView] is the slice: a value the cell can compare, so a digit
// entered in one cell repaints the cells whose highlight moved and no others.

import 'package:flutter/material.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/ui/tokens.dart';
import '../model/sudoku_session.dart';

/// The colours a cell draws itself in.
///
/// Passed down from the grid rather than read per cell: they come from
/// `AppTheme.roleScheme`, which builds a tonal palette, and eighty-one lookups
/// of one memoised map entry is eighty-one lookups too many.
///
/// Every one of them is paired with something that is not a colour — the
/// selected cell also has a border, a wrong digit is also underlined, a given
/// is also heavier — because nothing in this app is signalled by colour alone
/// (`AGENTS.md`, `PLAN.md` §9).
@immutable
class SudokuCellColors {
  /// The colours to draw a cell of the board in.
  const SudokuCellColors({
    required this.line,
    required this.selected,
    required this.sameDigit,
    required this.peer,
    required this.given,
    required this.entered,
    required this.wrong,
    required this.note,
  });

  /// The grid lines, box and cell alike.
  final Color line;

  /// Behind the selected cell.
  final Color selected;

  /// Behind a cell holding the same digit as the selected one.
  final Color sameDigit;

  /// Behind the selected cell's row, column and box.
  final Color peer;

  /// A digit the puzzle came with.
  final Color given;

  /// A digit the child entered.
  final Color entered;

  /// An entered digit the solution disagrees with.
  final Color wrong;

  /// Pencil marks.
  final Color note;
}

/// One cell of [session]'s board, at [index].
class SudokuCell extends StatefulWidget {
  /// A cell drawing [index] of [session], with digits [digitSize] tall and
  /// pencil marks [noteSize] tall.
  const SudokuCell({
    required this.session,
    required this.index,
    required this.colors,
    required this.digitSize,
    required this.noteSize,
    super.key,
  });

  /// The puzzle being played.
  final SudokuSession session;

  /// Which cell of it this is.
  final int index;

  /// What to draw it in.
  final SudokuCellColors colors;

  /// The digit's font size, in logical pixels.
  ///
  /// Derived from the cell's own geometry by the grid and deliberately not
  /// multiplied by `MediaQuery.textScaler`: an 80% larger digit in an unchanged
  /// cell is a clipped digit (`PLAN-phase-3.md` §4.5). The chrome around the
  /// board scales normally.
  final double digitSize;

  /// A pencil mark's font size, in logical pixels.
  final double noteSize;

  @override
  State<SudokuCell> createState() => _SudokuCellState();
}

class _SudokuCellState extends State<SudokuCell> {
  late _CellView _view;

  @override
  void initState() {
    super.initState();
    _view = _CellView.of(widget.session, widget.index);
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(SudokuCell old) {
    super.didUpdateWidget(old);
    if (old.session == widget.session && old.index == widget.index) return;
    old.session.removeListener(_onSessionChanged);
    widget.session.addListener(_onSessionChanged);
    _view = _CellView.of(widget.session, widget.index);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Rebuilds only when this cell looks different than it did.
  void _onSessionChanged() {
    final next = _CellView.of(widget.session, widget.index);
    if (next == _view) return;
    setState(() => _view = next);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.session.spec;
    final colors = widget.colors;

    return Semantics(
      // `row 3, column 7, empty` (`PLAN-phase-3.md` §2). Counted from one,
      // because it is read out to a person rather than indexed by one. The
      // accessibility pass proper is phase 5; this is the label that pass
      // should not have to invent from scratch.
      label:
          'row ${spec.rowOf(widget.index) + 1}, '
          'column ${spec.colOf(widget.index) + 1}, '
          '${_view.digit == 0 ? 'empty' : _view.digit}',
      selected: _view.isSelected,
      button: true,
      // The tap belongs on this node rather than only on the
      // [GestureDetector] below: `excludeSemantics` drops the whole subtree's
      // semantics, the detector's action with it, which would leave a cell
      // that announces itself as a button and cannot be activated as one.
      onTap: () => widget.session.select(widget.index),
      excludeSemantics: true,
      child: GestureDetector(
        // Opaque, so a tap anywhere in the cell selects it — including the
        // empty space around a digit, which is most of the cell.
        //
        // A `GestureDetector` rather than an `InkWell`: an ink splash paints on
        // the nearest `Material`, which is behind this cell's own background,
        // so the ripple would be invisible. The selection highlight is the
        // feedback, and it lands on the same frame as the tap.
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.session.select(widget.index),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _background(colors),
            border: sudokuCellBorder(spec, widget.index, colors.line),
          ),
          child: _view.isSelected
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.entered,
                      width: AppBorders.selected,
                    ),
                  ),
                  child: _content(),
                )
              : _content(),
        ),
      ),
    );
  }

  Color? _background(SudokuCellColors colors) {
    if (_view.isSelected) return colors.selected;
    if (_view.sharesDigit) return colors.sameDigit;
    if (_view.isPeer) return colors.peer;
    return null;
  }

  Widget _content() {
    if (_view.digit != 0) return _digit();
    if (_view.notes != 0) return _notes();
    return const SizedBox.expand();
  }

  /// The digit, drawn as a given, an entry, or an entry the solution
  /// disagrees with.
  ///
  /// A wrong digit is flagged as soon as it is entered, which is
  /// `MistakeFeedback.immediate` — the default and, until PR 7 reads the
  /// profile's choice, the only behaviour. PR 7 gates this on that setting
  /// rather than adding a second way to draw a digit.
  Widget _digit() {
    final colors = widget.colors;
    final color = _view.isWrong
        ? colors.wrong
        : _view.isGiven
        ? colors.given
        : colors.entered;

    return Center(
      child: Text(
        '${_view.digit}',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: widget.digitSize,
          height: 1,
          color: color,
          // A given is heavier and a wrong digit is underlined, so neither
          // depends on its colour being told apart from the other two.
          fontWeight: _view.isGiven ? FontWeight.w700 : FontWeight.w500,
          decoration: _view.isWrong ? TextDecoration.underline : null,
          decorationColor: color,
        ),
      ),
    );
  }

  /// The pencil marks, laid out in the same shape as a box of this grid.
  ///
  /// Derived from the spec rather than assumed square: a 9x9 gets 3x3, a 6x6
  /// gets 2x3, and neither is written down anywhere as a number.
  Widget _notes() {
    final spec = widget.session.spec;

    return Column(
      children: [
        for (var row = 0; row < spec.boxRows; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < spec.boxCols; col++)
                  Expanded(
                    child: Center(
                      child: Text(
                        _view.notes & 1 << (row * spec.boxCols + col) == 0
                            ? ''
                            : '${row * spec.boxCols + col + 1}',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: widget.noteSize,
                          height: 1,
                          color: widget.colors.note,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The grid lines drawn by the cell at [index], in [color].
///
/// Only the top and left, so an interior line is drawn once rather than twice
/// at double width by both of the cells it separates; the grid draws the frame
/// around the outside.
///
/// The thick lines are where a box ends, which comes from `spec.boxRows` and
/// `spec.boxCols` rather than from the size: a 9x9 gets them after rows and
/// columns 3 and 6, and a 6x6 after rows 2 and 4 and column 3. A grid that
/// transposed the box shape would look right at 9x9 and wrong at 6x6, which is
/// the bug `PLAN.md` §3.6 already tests for in the engine.
Border sudokuCellBorder(SudokuSpec spec, int index, Color color) {
  final row = spec.rowOf(index);
  final col = spec.colOf(index);

  return Border(
    top: row == 0
        ? BorderSide.none
        : BorderSide(
            color: color,
            width: row % spec.boxRows == 0
                ? AppBorders.gridBox
                : AppBorders.hairline,
          ),
    left: col == 0
        ? BorderSide.none
        : BorderSide(
            color: color,
            width: col % spec.boxCols == 0
                ? AppBorders.gridBox
                : AppBorders.hairline,
          ),
  );
}

/// Everything about one cell that is visible, and nothing else.
///
/// The comparison a cell makes to decide whether it has anything to redraw, so
/// it holds the highlight state as well as the contents: entering a digit
/// changes the cells that share it, and moving the selection changes a row, a
/// column and a box.
@immutable
class _CellView {
  const _CellView({
    required this.digit,
    required this.notes,
    required this.isGiven,
    required this.isWrong,
    required this.isSelected,
    required this.isPeer,
    required this.sharesDigit,
  });

  factory _CellView.of(SudokuSession session, int index) {
    final spec = session.spec;
    final selected = session.selected;
    final digit = session.digitAt(index);
    final isSelected = selected == index;

    return _CellView(
      digit: digit,
      notes: session.notesAt(index),
      isGiven: session.isGiven(index),
      isWrong: session.isWrong(index),
      isSelected: isSelected,
      isPeer:
          selected != null &&
          !isSelected &&
          (spec.rowOf(selected) == spec.rowOf(index) ||
              spec.colOf(selected) == spec.colOf(index) ||
              spec.boxOf(selected) == spec.boxOf(index)),
      sharesDigit:
          selected != null &&
          !isSelected &&
          digit != 0 &&
          digit == session.digitAt(selected),
    );
  }

  final int digit;
  final int notes;
  final bool isGiven;
  final bool isWrong;
  final bool isSelected;
  final bool isPeer;
  final bool sharesDigit;

  @override
  bool operator ==(Object other) =>
      other is _CellView &&
      other.digit == digit &&
      other.notes == notes &&
      other.isGiven == isGiven &&
      other.isWrong == isWrong &&
      other.isSelected == isSelected &&
      other.isPeer == isPeer &&
      other.sharesDigit == sharesDigit;

  @override
  int get hashCode => Object.hash(
    digit,
    notes,
    isGiven,
    isWrong,
    isSelected,
    isPeer,
    sharesDigit,
  );
}
