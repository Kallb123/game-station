/// The shape of a Sudoku grid: how many rows and columns a box has.
///
/// Everything else is derived. `PLAN.md` §3.3 describes a spec of four fields —
/// rows, columns, box rows, box columns — but two of the four are redundant,
/// and a four-field record is a record that can be built inconsistent. Deriving
/// [digits] and [cells] from the box shape removes that state rather than
/// validating it away.
///
/// The engine is size-generic, so 4x4 and 12x12 cost nothing later. Only [s9x9]
/// and [s6x6] are named here because those are the sizes a puzzle ID can spell
/// (`PLAN-phase-2.md` §2) — an unsupported size is rejected when the ID is
/// parsed, rather than reaching a solver that would work perfectly well on it.
class SudokuSpec {
  /// A grid whose boxes are [boxRows] tall and [boxCols] wide.
  const SudokuSpec({required this.boxRows, required this.boxCols});

  /// Boxes of 3 rows by 3 columns: digits 1–9 over 81 cells.
  static const SudokuSpec s9x9 = SudokuSpec(boxRows: 3, boxCols: 3);

  /// Boxes of 2 rows by 3 columns: digits 1–6 over 36 cells.
  ///
  /// The shape is not square, which is the point of storing it: a 6x6 box
  /// spans two rows and three columns, and getting that backwards produces a
  /// grid that still looks plausible.
  static const SudokuSpec s6x6 = SudokuSpec(boxRows: 2, boxCols: 3);

  /// Rows in one box.
  final int boxRows;

  /// Columns in one box.
  final int boxCols;

  /// The highest digit, and equally the number of rows and of columns.
  int get digits => boxRows * boxCols;

  /// Cells in the whole grid.
  int get cells => digits * digits;

  /// Boxes across the grid, which is also the number of box bands down it.
  int get boxesPerRow => digits ~/ boxCols;

  /// A bitmask with one bit set per legal digit: bit `d - 1` stands for `d`.
  int get fullMask => (1 << digits) - 1;

  /// The size as it appears in a puzzle ID: `9x9`, `6x6`.
  String get label => '${digits}x$digits';

  /// The row of the cell at [index], counting from 0.
  int rowOf(int index) => index ~/ digits;

  /// The column of the cell at [index], counting from 0.
  int colOf(int index) => index % digits;

  /// The box of the cell at [index], numbered left to right then top to bottom.
  int boxOf(int index) =>
      (rowOf(index) ~/ boxRows) * boxesPerRow + colOf(index) ~/ boxCols;

  /// The index of the cell at [row] and [col].
  int indexAt(int row, int col) => row * digits + col;

  @override
  bool operator ==(Object other) =>
      other is SudokuSpec &&
      other.boxRows == boxRows &&
      other.boxCols == boxCols;

  @override
  int get hashCode => Object.hash(boxRows, boxCols);

  @override
  String toString() => 'SudokuSpec($label, boxes ${boxRows}x$boxCols)';
}
