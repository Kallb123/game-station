/// Every route in the app.
///
/// Named constants rather than string literals at each call site: a typo in a
/// route name is otherwise a runtime surprise on a screen a child is looking
/// at, and there is no URL bar anywhere to correct it from.
///
/// In its own file so that a screen can name a route without importing the
/// app root, which imports every screen.
abstract final class AppRoutes {
  /// The home screen.
  static const String home = '/';

  /// The profile picker.
  static const String profiles = '/profiles';

  /// The settings screen.
  static const String settings = '/settings';

  /// Sudoku, from phase 3.
  static const String sudoku = '/sudoku';

  /// One Sudoku puzzle, being played. Pushed with a `SudokuPlayArgs`, which is
  /// the only route in the app that takes arguments at all.
  static const String sudokuPlay = '/sudoku/play';

  /// The arcade, from phase 4.
  static const String arcade = '/arcade';
}
