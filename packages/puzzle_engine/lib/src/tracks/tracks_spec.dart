/// The shape of a Tracks grid: a square, so one side length is the whole spec.
///
/// Unlike a Sudoku spec there is nothing to derive a second dimension from, and
/// nothing that could be built inconsistent. Only [s5x5], [s7x7] and [s9x9] are
/// named because those are the sizes a puzzle ID can spell
/// (`PLAN-phase-9-tracks.md` §4.1): an unsupported size is rejected when the ID
/// or the clue line is parsed, rather than reaching a generator that would work
/// on it but whose output no golden freezes.
class TracksSpec {
  /// A square grid [side] cells across.
  const TracksSpec(this.side) : assert(side >= 1, 'a grid has at least a cell');

  /// 5x5: a first puzzle for a five-year-old.
  static const TracksSpec s5x5 = TracksSpec(5);

  /// 7x7: the middle size.
  static const TracksSpec s7x7 = TracksSpec(7);

  /// 9x9: the largest grid whose cells stay readable on a phone.
  static const TracksSpec s9x9 = TracksSpec(9);

  /// The sizes an ID or a clue line may spell, in the order the menu lists
  /// them.
  static const List<TracksSpec> supported = [s5x5, s7x7, s9x9];

  /// Rows, and equally columns.
  final int side;

  /// Cells in the whole grid.
  int get cells => side * side;

  /// The size as it appears in a puzzle ID: `5x5`, `7x7`, `9x9`.
  String get label => '${side}x$side';

  /// The row of the cell at [index], counting from 0 at the north.
  int rowOf(int index) => index ~/ side;

  /// The column of the cell at [index], counting from 0 at the west.
  int columnOf(int index) => index % side;

  /// The index of the cell at [row] and [column].
  int indexAt(int row, int column) => row * side + column;

  @override
  bool operator ==(Object other) => other is TracksSpec && other.side == side;

  @override
  int get hashCode => side.hashCode;

  @override
  String toString() => 'TracksSpec($label)';
}
