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

  /// The Puzzles menu: Sudoku and Tracks behind one home card
  /// (`PLAN-phase-9-tracks.md` §4.14).
  static const String puzzles = '/puzzles';

  /// Sudoku, from phase 3. Reached through [puzzles] since phase 9.
  static const String sudoku = '/sudoku';

  /// One Sudoku puzzle, being played. Pushed with a `SudokuPlayArgs`.
  static const String sudokuPlay = '/sudoku/play';

  /// The Tracks menu, reached through [puzzles] (`PLAN-phase-9-tracks.md`
  /// §4.14).
  static const String tracks = '/tracks';

  /// One Tracks puzzle, being played. Pushed with a `TracksPlayArgs`
  /// (`PLAN-phase-9-tracks.md` §6, PR 7).
  static const String tracksPlay = '/tracks/play';

  /// The arcade, from phase 4.
  static const String arcade = '/arcade';

  /// Space Invaders (`PLAN-phase-4.md` §6, PR 4). Takes no arguments: the
  /// options a run starts with come from the profile, so there is no second
  /// copy to disagree with the stored one (`PLAN-phase-4.md` §4.10).
  static const String arcadeInvaders = '/arcade/invaders';

  /// Snake (`PLAN-phase-7-snake.md` §6, PR 4). Takes no arguments, for the
  /// same reason [arcadeInvaders] does not: the options a run starts with —
  /// easy mode and the counting choice — come from the profile.
  static const String arcadeSnake = '/arcade/snake';

  /// The Quiz menu (`PLAN-phase-10-quiz.md` §4.5).
  static const String quiz = '/quiz';

  /// The quiz shelf, where a child ticks what they have read or watched
  /// (`PLAN-phase-10-quiz.md` §4.5).
  static const String quizShelf = '/quiz/shelf';

  /// The list of titles to play one of (`PLAN-phase-10-quiz.md` §4.5).
  static const String quizPick = '/quiz/pick';

  /// One quiz round, being played. Pushed with a `QuizPlayArgs`
  /// (`PLAN-phase-10-quiz.md` §4.5).
  static const String quizPlay = '/quiz/play';

  /// The drawing gallery, from phase 8.
  static const String draw = '/draw';

  /// One sheet, being drawn on. Pushed with a `DrawSheetArgs`, which names
  /// which drawing to resume — or none, for a blank sheet
  /// (`PLAN-phase-8.md` §6, PR 4).
  static const String drawSheet = '/draw/sheet';

  /// Moving players to or from a file, reached from the settings screen
  /// (`PLAN-transfer.md` §3.4).
  static const String transfer = '/transfer';
}
