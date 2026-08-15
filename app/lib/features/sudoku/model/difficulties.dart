// What the menu is allowed to offer.
//
// One function, imported by the menu and by its test, so that "the picker
// offers what the engine builds" is a shared fact rather than two lists that
// agree until one of them is edited (`PLAN-phase-3.md` §5).

import 'package:puzzle_engine/puzzle_engine.dart';

/// The sizes the menu offers, in the order its toggle draws them.
const List<SudokuSpec> sudokuSizes = <SudokuSpec>[
  SudokuSpec.s9x9,
  SudokuSpec.s6x6,
];

/// The size a profile with no history is offered.
const SudokuSpec defaultSudokuSpec = SudokuSpec.s9x9;

/// The difficulty a profile with no history is offered.
const Difficulty defaultSudokuDifficulty = Difficulty.easy;

/// The difficulties [spec] can be played at, easiest first.
///
/// 6x6 has no Expert tier: 36 cells leave too little room for a genuine T4
/// (`PLAN.md` §3.4), and the engine refuses the combination in two places —
/// `PuzzleId.parse` will not spell it and `generateSudoku` throws for it. This
/// is the third, and the only one a child ever meets: a difficulty the engine
/// would refuse is never drawn, so nothing here can produce the exception.
///
/// Filtered rather than listed, so a tier added to [Difficulty] later shows up
/// for both sizes without an edit here — two hardcoded lists is the shape of
/// mistake this function exists to prevent.
///
/// 9x9 Expert **is** offered, last, which answers `PLAN-phase-2.md` §9's open
/// question: the engine builds it either way, and a child who wants something
/// harder finding nothing above Hard is a worse outcome than one who tries
/// Expert and backs out (`PLAN-phase-3.md` §4.7).
List<Difficulty> difficultiesFor(SudokuSpec spec) => <Difficulty>[
  for (final difficulty in Difficulty.values)
    if (spec != SudokuSpec.s6x6 || difficulty != Difficulty.expert) difficulty,
];
