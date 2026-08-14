// A temporary way onto the board. **PR 8 deletes this file whole.**
//
// `PLAN-phase-3.md` §6 asks for exactly one button here, so that the play
// screen is reachable — and testable through the app's own routes — before the
// menu that will launch it properly exists. Nothing but the route table imports
// this, so replacing `/sudoku` with `sudoku_menu_screen.dart` is a one-line
// change there and a deletion here.

import 'package:flutter/material.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/ui/big_button.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../routes.dart';
import '../../home/home_screen.dart' show homeSudokuIcon;
import 'sudoku_play_screen.dart';

/// The one puzzle this launcher offers.
///
/// Fixed rather than the daily index, so that closing the app and opening it
/// again lands on the same board: the manual half of this pull request's
/// done-criterion is a force-quit and a relaunch, and a launcher that handed
/// out a different puzzle each day would test something else on the second run.
const PuzzleId launcherPuzzle = PuzzleId(SudokuSpec.s6x6, Difficulty.easy, 0);

/// What the button says. Public because the test names the same string.
const String launcherLabel = 'Play 6x6 Easy';

/// `/sudoku` until PR 8 puts the menu here.
class SudokuLauncherScreen extends StatelessWidget {
  /// The temporary launcher.
  const SudokuLauncherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Sudoku',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BigButton(
            icon: homeSudokuIcon,
            label: launcherLabel,
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.sudokuPlay,
              arguments: const SudokuPlayArgs(launcherPuzzle),
            ),
          ),
        ],
      ),
    );
  }
}
