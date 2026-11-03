/// Connection bits for one cell, and the six pieces they combine into.
///
/// A cell's state is a mask of the sides its track leaves through: 0 for an
/// empty cell, otherwise exactly two bits. A port cell has its outward bit
/// set, so the start cell holds [west] and the goal cell [south]
/// (`PLAN-phase-9-tracks.md` §4.3).
///
/// A holder class rather than top-level constants: bare `north` and `east`
/// would land in the namespace of every file that imports the package.
abstract final class TrackSide {
  /// The side facing row 0.
  static const int north = 1;

  /// The side facing the last column.
  static const int east = 2;

  /// The side facing the last row.
  static const int south = 4;

  /// The side facing column 0.
  static const int west = 8;

  /// The four sides in a fixed order. Iterate this, never a `Set`, wherever
  /// the order can reach an output.
  static const List<int> all = [north, east, south, west];

  /// The six pieces, in this frozen order: NS, EW, NE, ES, SW, NW.
  ///
  /// Frozen because a search that tries them in this order finds solutions, and
  /// counts nodes, in an order a golden can depend on.
  static const List<int> pieces = [
    north | south,
    east | west,
    north | east,
    east | south,
    south | west,
    north | west,
  ];

  /// The side facing [side].
  ///
  /// Throws an [ArgumentError] for anything but one of the four single bits:
  /// an unchecked fallthrough would turn a typo into a wrong board.
  static int opposite(int side) {
    switch (side) {
      case north:
        return south;
      case south:
        return north;
      case east:
        return west;
      case west:
        return east;
    }
    throw ArgumentError.value(side, 'side', 'must be one of the four sides');
  }

  /// Whether [mask] is exactly one of the six [pieces].
  static bool isPiece(int mask) => pieces.contains(mask);
}
