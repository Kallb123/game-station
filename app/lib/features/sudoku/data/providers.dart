// The Riverpod wiring over `features/sudoku/data`.
//
// Same shape as `core/storage/providers.dart`: the implementation is behind a
// provider so that a widget test overrides it with a fake and never generates.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../model/sudoku_menu.dart';
import 'puzzle_source.dart';

/// Where every screen gets its puzzles.
///
/// Watches the repository's `.notifier` rather than the repository itself: the
/// value of a [ChangeNotifierProvider] changes on every `notifyListeners`, so
/// watching it would rebuild this provider on every saved move and throw away
/// the in-flight map — and with it the de-duplication that makes a pre-warm
/// worth having.
final Provider<PuzzleSource> puzzleSourceProvider = Provider<PuzzleSource>((
  ref,
) {
  final source = IsolatePuzzleSource(
    ref.watch(progressRepositoryProvider.notifier),
  );
  // A generation cannot be cancelled, so one can outlive the scope. Told the
  // scope has gone, the source stops writing to a repository that has gone
  // with it.
  ref.onDispose(source.dispose);
  return source;
});

/// What the menu shows for the profile that is playing.
///
/// Watches [activeProfileProvider] rather than the repository, so switching
/// profile redraws the solved counts, the best times and the streak, and a
/// saved move on a screen nobody is looking at does not.
final Provider<SudokuMenu> sudokuMenuProvider = Provider<SudokuMenu>(
  (ref) => SudokuMenu.of(ref.watch(activeProfileProvider).sudoku),
);
