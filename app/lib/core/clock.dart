// Where the app reads the wall clock.
//
// Moved out of `features/sudoku/data/providers.dart` in `PLAN-phase-4.md` §4.3:
// arcade's `GameRng` seeds itself from the same clock the daily puzzle reads,
// and a provider two features import should not live inside one of them.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wall clock, as a function rather than a [DateTime].
///
/// A function so that a screen that stays open across midnight asks again on
/// its next build instead of holding yesterday's answer, and a provider so
/// that a test can fix today: the Sudoku daily card names a puzzle id, and a
/// test that had to compute the same id from the real clock would pass every
/// day except the one it ran across a UTC midnight on.
final Provider<DateTime Function()> nowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
