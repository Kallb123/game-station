import 'hash.dart';
import 'puzzle_id.dart';
import 'rng.dart';
import 'solver.dart';
import 'sudoku_board.dart';
import 'sudoku_spec.dart';
import 'technique_solver.dart';

/// How many times [generateSudoku] starts over before it settles for the
/// closest puzzle it saw (`PLAN.md` §3.4).
const int generatorMaxAttempts = 250;

/// What one label on one size asks a grid to be: which technique tiers count as
/// that label, and how many clues may be left standing.
///
/// Two constraints rather than one, because neither alone describes a puzzle a
/// child would recognise. Technique tier is the honest measure of difficulty —
/// clue count correlates with it poorly, and `PLAN.md` §3.4 says not to infer
/// one from the other — but a grid with 24 clues does not *look* Easy however
/// few techniques it needs, and the dig has to know where to stop.
class PuzzleRecipe {
  /// A label that accepts tiers [lowestTier] to [highestTier] over [floor] to
  /// [ceiling] clues.
  const PuzzleRecipe({
    required this.lowestTier,
    required this.highestTier,
    required this.floor,
    required this.ceiling,
  });

  /// The easiest technique tier this label accepts.
  final Difficulty lowestTier;

  /// The hardest tier it accepts, which is also the tier the dig refuses to
  /// pass: a hole that would make the grid harder than this is put back.
  final Difficulty highestTier;

  /// The fewest clues to leave. The dig stops here once [highestTier] is
  /// reached, and keeps going past it while the grid is still too easy.
  final int floor;

  /// The most clues a finished puzzle may keep.
  final int ceiling;

  /// Whether a grid judged [tier] with [clues] clues is what this label wants.
  bool accepts(Difficulty tier, int clues) =>
      tier.index >= lowestTier.index &&
      tier.index <= highestTier.index &&
      clues >= floor &&
      clues <= ceiling;
}

/// The recipe for a size and a label (`PLAN.md` §3.4).
///
/// Every number here was measured rather than guessed, and several moved from
/// what `PLAN.md` §3.4 first specified — the reasoning is recorded there and in
/// `PLAN-phase-2.md` §4.7. The two that matter most:
///
/// - **9x9 Hard sits at 24 to 29 clues, not 26 to 29.** A grid becomes Hard on
///   the way down, and it reaches T3 at 24 or 25 clues far more often than at
///   26 exactly.
/// - **6x6 Medium accepts Easy techniques.** A 6x6 has no room for a tier
///   between "singles finish it" and "needs a triple or a wing": needing a pair
///   and nothing more is about one dug grid in 300, so a Medium defined that
///   way would be an Easy puzzle wearing a Medium label three times in four.
///   What makes a 6x6 harder for a child is sparseness, so 6x6 Medium is the
///   same techniques over 12 clues instead of 18, and 6x6 Hard is the one that
///   asks for a technique beyond singles. This is the single place in the
///   engine where a label is not a pure statement about technique, and it is
///   confined to the size that cannot express one.
///
/// Throws [ArgumentError] for 6x6 Expert, which has no recipe because it has no
/// tier: `PLAN.md` §3.4 rules it out for want of room. [PuzzleId.parse] refuses
/// to spell it, and this is the same rule holding in release, where assertions
/// do not run.
PuzzleRecipe recipeFor(SudokuSpec spec, Difficulty difficulty) {
  if (spec == SudokuSpec.s9x9) {
    switch (difficulty) {
      case Difficulty.easy:
        return const PuzzleRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 36,
          ceiling: 45,
        );
      case Difficulty.medium:
        return const PuzzleRecipe(
          lowestTier: Difficulty.medium,
          highestTier: Difficulty.medium,
          floor: 28,
          ceiling: 35,
        );
      case Difficulty.hard:
        return const PuzzleRecipe(
          lowestTier: Difficulty.hard,
          highestTier: Difficulty.hard,
          floor: 24,
          ceiling: 29,
        );
      case Difficulty.expert:
        return const PuzzleRecipe(
          lowestTier: Difficulty.expert,
          highestTier: Difficulty.expert,
          floor: 22,
          ceiling: 25,
        );
    }
  }
  if (spec == SudokuSpec.s6x6) {
    switch (difficulty) {
      case Difficulty.easy:
        return const PuzzleRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 18,
          ceiling: 24,
        );
      case Difficulty.medium:
        return const PuzzleRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 12,
          ceiling: 14,
        );
      case Difficulty.hard:
        return const PuzzleRecipe(
          lowestTier: Difficulty.medium,
          highestTier: Difficulty.hard,
          floor: 9,
          ceiling: 12,
        );
      case Difficulty.expert:
        throw ArgumentError.value(
          difficulty.name,
          'difficulty',
          '${spec.label} has no Expert tier',
        );
    }
  }
  throw ArgumentError.value(spec.label, 'spec', 'no recipe for this size');
}

/// One puzzle, and what it cost to make.
class GeneratedPuzzle {
  /// A puzzle for [id] with the grid, the tier it earned and the retry count.
  const GeneratedPuzzle({
    required this.id,
    required this.clues,
    required this.solution,
    required this.requested,
    required this.tier,
    required this.clueCount,
    required this.attempts,
    required this.widened,
  });

  /// The ID this was generated from. Regenerating it reproduces this exactly.
  final PuzzleId id;

  /// The starting grid, as `SudokuBoard.toClueString` writes it. This is what
  /// `puzzleCache` stores in `PLAN.md` §5.2.
  final String clues;

  /// The one completion of [clues].
  final String solution;

  /// The tier that was asked for.
  final Difficulty requested;

  /// The tier the puzzle actually earned, judged by technique.
  ///
  /// Equal to [requested] for six of the seven size-and-label combinations. The
  /// exception is by design rather than by failure: a 6x6 Medium is Easy by
  /// technique and Medium by sparseness, because a 6x6 has no room for a tier
  /// in between (`PLAN.md` §3.4). Read [widened] to tell "this is what was
  /// asked for" from "this was the closest thing to it".
  final Difficulty tier;

  /// How many cells [clues] fills in.
  final int clueCount;

  /// How many attempts it took, counting the one that produced this.
  final int attempts;

  /// Whether the generator settled for something other than what was asked.
  ///
  /// False means the puzzle satisfies its recipe: a tier the label accepts, and
  /// a clue count inside the band. True means [generatorMaxAttempts] attempts
  /// all missed and this was the closest of them — usually a neighbouring tier,
  /// sometimes the right tier at the wrong clue count. Phase 3 shows the puzzle
  /// either way: a child cannot act on "could not generate a puzzle"
  /// (`AGENTS.md`), and a slightly-off puzzle is a better answer than an error.
  ///
  /// It is rare by measurement rather than by hope — under 1 in 100 for every
  /// combination over 200 indices each — and PR 6's goldens fail the build if
  /// more than 5 in 100 of any file are widened.
  final bool widened;

  @override
  String toString() =>
      'GeneratedPuzzle($id, ${tier.name}, $clueCount clues, '
      '$attempts attempt${attempts == 1 ? '' : 's'}'
      '${widened ? ', widened from ${requested.name}' : ''})';
}

/// Builds the puzzle [id] names. The same ID always returns the same grid.
///
/// Grow a full grid, dig holes while the solution stays unique, judge what is
/// left by technique, and start over if it missed (`PLAN.md` §3.4). Every
/// ordering decision comes from [Rng] seeded from the ID, so this is a pure
/// function of its argument on every platform and in every release — which is
/// what lets a save store the ID and throw the grid away.
///
/// The seed derivation is frozen along with everything it feeds:
///
/// ```
/// attempt 0 : seed = fnv1a32(id.value)
/// attempt n : seed = fnv1a32('${id.value}#$n')
/// ```
///
/// Hashing a suffixed string rather than adding to the seed keeps consecutive
/// attempts uncorrelated: `Rng` expands its seed through SplitMix32, so seed+1
/// would be a different sequence anyway, but a hash makes that true by
/// construction rather than by a property of the seeding.
///
/// Never throws for a puzzle it cannot make well: after [generatorMaxAttempts]
/// it returns the closest attempt with `widened: true`. It does throw
/// [ArgumentError] for a size and tier that do not exist, which is a caller
/// mistake rather than a hard puzzle.
GeneratedPuzzle generateSudoku(PuzzleId id) {
  final recipe = recipeFor(id.spec, id.difficulty);
  _Attempt? closest;

  for (var attempt = 0; attempt < generatorMaxAttempts; attempt++) {
    final seed = attempt == 0
        ? fnv1a32(id.value)
        : fnv1a32('${id.value}#$attempt');
    final rng = Rng(seed);

    final solution = _grow(id.spec, rng);
    final puzzle = _dig(solution, rng, recipe.floor, recipe.highestTier);
    final report = solveWithTechniques(puzzle);
    final candidate = _Attempt(
      number: attempt + 1,
      clues: puzzle.toClueString(),
      solution: solution.toClueString(),
      tier: report.tier,
      clueCount: puzzle.filledCount,
    );

    if (recipe.accepts(candidate.tier, candidate.clueCount)) {
      return candidate.toPuzzle(id, widened: false);
    }
    closest = _closer(closest, candidate, recipe);
  }

  return closest!.toPuzzle(id, widened: true);
}

/// One try at a puzzle, kept so the retry loop has something to settle for.
class _Attempt {
  const _Attempt({
    required this.number,
    required this.clues,
    required this.solution,
    required this.tier,
    required this.clueCount,
  });

  final int number;
  final String clues;
  final String solution;
  final Difficulty tier;
  final int clueCount;

  GeneratedPuzzle toPuzzle(PuzzleId id, {required bool widened}) =>
      GeneratedPuzzle(
        id: id,
        clues: clues,
        solution: solution,
        requested: id.difficulty,
        tier: tier,
        clueCount: clueCount,
        attempts: number,
        widened: widened,
      );
}

/// Whichever of [held] and [fresh] is nearer to what was asked for.
///
/// Tier distance first, because a Hard puzzle offered as Medium is a worse
/// answer than a Medium one with two clues too many. Then distance from the
/// band, then the earlier attempt — the last of the three matters only because
/// the choice has to be the same on every device, and "the first of the equally
/// close" is a rule that does not depend on anything but the sequence.
_Attempt _closer(_Attempt? held, _Attempt fresh, PuzzleRecipe recipe) {
  if (held == null) return fresh;

  final heldTier = _distance(
    held.tier.index,
    recipe.lowestTier.index,
    recipe.highestTier.index,
  );
  final freshTier = _distance(
    fresh.tier.index,
    recipe.lowestTier.index,
    recipe.highestTier.index,
  );
  if (freshTier != heldTier) return freshTier < heldTier ? fresh : held;

  final heldClues = _distance(held.clueCount, recipe.floor, recipe.ceiling);
  final freshClues = _distance(fresh.clueCount, recipe.floor, recipe.ceiling);
  if (freshClues != heldClues) return freshClues < heldClues ? fresh : held;

  return held;
}

/// How far [value] falls outside `low..high`; 0 when it is inside.
int _distance(int value, int low, int high) {
  if (value < low) return low - value;
  if (value > high) return value - high;
  return 0;
}

/// A complete, legal grid, filled cell by cell in index order with the digits
/// tried in [rng] order.
///
/// A complete grid always exists from an empty board, so this backtracks but
/// never fails. The [StateError] is not a case a puzzle can reach — it would
/// mean the board rejected a placement the rules allow — and it is here because
/// returning a half-filled grid would produce a puzzle with no solution rather
/// than a visible failure.
SudokuBoard _grow(SudokuSpec spec, Rng rng) {
  final board = SudokuBoard(spec);
  if (!_fill(board, rng)) {
    throw StateError('no complete ${spec.label} grid exists, which cannot be');
  }
  return board;
}

/// Fills the first empty cell every way [rng] offers, recursively.
///
/// The digit order is shuffled afresh each time a cell is entered, including
/// when the search comes back to it after backtracking. That is a draw from the
/// frozen stream and so part of the generator's output: a shuffle hoisted out
/// of the recursion would consume [Rng] differently and produce different
/// puzzles from the same ID.
bool _fill(SudokuBoard board, Rng rng) {
  var target = -1;
  for (var index = 0; index < board.spec.cells; index++) {
    if (board.digitAt(index) == 0) {
      target = index;
      break;
    }
  }
  if (target < 0) return true;

  final digits = List.generate(board.spec.digits, (i) => i + 1);
  rng.shuffle(digits);
  for (final digit in digits) {
    if (!board.place(target, digit)) continue;
    if (_fill(board, rng)) return true;
    board.remove(target);
  }
  return false;
}

/// Empties cells of [full] in [rng] order, keeping a hole only while the grid
/// has exactly one solution and is still no harder than [ceiling].
///
/// Both stopping rules exist because difficulty is a property of which holes
/// there are, not of how many, and digging blindly overshoots it both ways:
///
/// - **[ceiling].** A hole that pushes the grid past the tier asked for is put
///   back and the walk carries on with the next cell. Without it the dig lands
///   on whatever tier that clue count happens to produce, which is not the tier
///   anyone asked for: measured over 50 indices each, 9x9 Hard came out Expert
///   30 times in 50. Tier never falls as clues come out, so once the ceiling is
///   reached the dig can only keep it, never lose it.
/// - **[floor], but only once the ceiling tier has been reached.** Digging to
///   exhaustion always arrives near the minimum — about 24 clues at 9x9 — so an
///   Easy band of 36 to 45 would be unreachable from above. Stopping at the
///   floor regardless, which is what `PLAN-phase-2.md` §4.7 specified, has the
///   opposite failure: a grid that is still Medium at 26 clues stops there and
///   is thrown away, when three more holes would have made it the Hard puzzle
///   that was asked for. Hard is reached at 24 to 26 clues far more often than
///   at 26 exactly, which is why the band moved rather than the rule bending.
///
/// Judging after each accepted removal is the expensive part — one technique
/// solve per hole rather than one per attempt — and it pays for itself several
/// times over by cutting the attempts a puzzle needs.
///
/// A count of [unknownSolutionCount] restores the digit like any other
/// non-unique answer: the node cap is deterministic, so treating "unknown" as
/// "not unique" costs an occasional hole that could have been kept and never
/// costs a puzzle with two solutions.
SudokuBoard _dig(SudokuBoard full, Rng rng, int floor, Difficulty ceiling) {
  final board = full.copy();
  final order = List.generate(board.spec.cells, (index) => index);
  rng.shuffle(order);

  var tier = Difficulty.easy;
  for (final index in order) {
    if (tier == ceiling && board.filledCount <= floor) break;
    final digit = board.digitAt(index);
    if (digit == 0) continue;

    board.remove(index);
    if (countSolutions(board) == 1) {
      final dug = solveWithTechniques(board).tier;
      if (dug.index <= ceiling.index) {
        tier = dug;
        continue;
      }
    }
    board.place(index, digit);
  }
  return board;
}
