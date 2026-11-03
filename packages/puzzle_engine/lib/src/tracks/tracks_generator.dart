import '../difficulty.dart';
import '../generator.dart' show generatorMaxAttempts;
import '../hash.dart';
import '../rng.dart';
import 'tracks_clues.dart';
import 'tracks_counter.dart';
import 'tracks_deduction.dart';
import 'tracks_puzzle.dart';
import 'tracks_puzzle_id.dart';
import 'tracks_spec.dart';
import 'tracks_walk.dart';

/// What one label on one size asks a Tracks puzzle to be: the walk its path
/// comes from, which technique tiers count as that label, and how many pieces
/// may be left fixed.
///
/// The counterpart of `PuzzleRecipe`, with the same two constraints and for the
/// same reason (`PLAN-phase-9-tracks.md` §4.5). Technique tier is the honest
/// measure of difficulty, but a 5x5 with eleven pieces fixed does not *look*
/// like a puzzle however few deductions it needs, and the dig has to know where
/// to stop. The walk band is a third constraint Sudoku has no equivalent of: it
/// shapes the grid the dig starts from.
class TracksRecipe {
  /// A label that accepts tiers [lowestTier] to [highestTier] over [floor] to
  /// [ceiling] fixed pieces, on paths that fit [band].
  const TracksRecipe({
    required this.lowestTier,
    required this.highestTier,
    required this.floor,
    required this.ceiling,
    required this.band,
  });

  /// The easiest technique tier this label accepts.
  final Difficulty lowestTier;

  /// The hardest tier it accepts, which is also the tier the dig refuses to
  /// pass: a piece whose removal would make the puzzle harder than this is put
  /// back.
  final Difficulty highestTier;

  /// The fewest fixed pieces to leave. The dig stops here once [highestTier] is
  /// reached, and keeps going past it while the puzzle is still too easy.
  final int floor;

  /// The most fixed pieces a finished puzzle may keep.
  final int ceiling;

  /// The path the walk draws before the dig starts.
  final TracksWalkBand band;

  /// Whether a puzzle judged [tier] with [fixed] pieces fixed is what this
  /// label wants.
  bool accepts(Difficulty tier, int fixed) =>
      tier.index >= lowestTier.index &&
      tier.index <= highestTier.index &&
      fixed >= floor &&
      fixed <= ceiling;
}

/// The recipe for a size and a label (`PLAN-phase-9-tracks.md` §4.5).
///
/// Every number was measured over 200 indices per combination rather than
/// guessed (§4.5 holds the table). Three things the measurement showed shape
/// the recipes:
///
/// - **Technique alone does not separate the labels; the fixed-piece floor
///   does.** Row and column counts carry most of the deduction, so even a
///   puzzle with no piece fixed is usually Easy by technique. Easy is therefore
///   Easy by technique *and* generous with fixed pieces (a little over half the
///   path), so the first 5x5 puzzles are nearly done and teach the rule
///   (`PLAN-phase-9-tracks.md` §2). Medium and Hard are reached on the way down and keep a quarter and
///   about a tenth of the path.
/// - **Medium and Hard are honest technique tiers on every size offered.**
///   Unlike Sudoku's 6x6 Medium, no label here is Easy by technique: each
///   puzzle's `tier` is the label it was asked for, and the dig only stops once
///   the solver needed that tier.
/// - **5x5 Hard is not offered.** Its T3 puzzles exist only with one fixed
///   piece out of about fourteen, or none (11 attempts at the median for one
///   piece, 33 for two, and 34 in 200 widened at three): a counting puzzle with
///   nothing to start from. That is no step up in kind from 5x5 Medium for the
///   child it is for, and costs several times the generation. A child who has
///   outgrown 5x5 Medium is offered 7x7.
///
/// Throws [ArgumentError] for Expert, which Tracks has no tier for
/// (`PLAN-phase-9-tracks.md` §1), for 5x5 Hard, and for a size that is not
/// offered. [TracksPuzzleId.parse] refuses to spell the first two, and this is
/// the same rule holding in release, where assertions do not run.
TracksRecipe tracksRecipeFor(TracksSpec spec, Difficulty difficulty) {
  if (difficulty == Difficulty.expert) {
    throw ArgumentError.value(
      difficulty.name,
      'difficulty',
      'Tracks has no Expert tier',
    );
  }
  if (spec == TracksSpec.s5x5) {
    switch (difficulty) {
      case Difficulty.easy:
        return const TracksRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 8,
          ceiling: 10,
          band: TracksWalkBand(minLength: 9, maxLength: 15, minTurns: 3),
        );
      case Difficulty.medium:
        return const TracksRecipe(
          lowestTier: Difficulty.medium,
          highestTier: Difficulty.medium,
          floor: 4,
          ceiling: 6,
          band: TracksWalkBand(minLength: 9, maxLength: 15, minTurns: 3),
        );
      case Difficulty.hard:
      case Difficulty.expert:
        break;
    }
  }
  if (spec == TracksSpec.s7x7) {
    switch (difficulty) {
      case Difficulty.easy:
        return const TracksRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 14,
          ceiling: 16,
          band: TracksWalkBand(minLength: 17, maxLength: 29, minTurns: 6),
        );
      case Difficulty.medium:
        return const TracksRecipe(
          lowestTier: Difficulty.medium,
          highestTier: Difficulty.medium,
          floor: 7,
          ceiling: 9,
          band: TracksWalkBand(minLength: 17, maxLength: 29, minTurns: 6),
        );
      case Difficulty.hard:
        return const TracksRecipe(
          lowestTier: Difficulty.hard,
          highestTier: Difficulty.hard,
          floor: 3,
          ceiling: 5,
          band: TracksWalkBand(minLength: 17, maxLength: 29, minTurns: 6),
        );
      case Difficulty.expert:
        break;
    }
  }
  if (spec == TracksSpec.s9x9) {
    switch (difficulty) {
      case Difficulty.easy:
        return const TracksRecipe(
          lowestTier: Difficulty.easy,
          highestTier: Difficulty.easy,
          floor: 22,
          ceiling: 24,
          band: TracksWalkBand(minLength: 27, maxLength: 45, minTurns: 9),
        );
      case Difficulty.medium:
        return const TracksRecipe(
          lowestTier: Difficulty.medium,
          highestTier: Difficulty.medium,
          floor: 11,
          ceiling: 13,
          band: TracksWalkBand(minLength: 27, maxLength: 45, minTurns: 9),
        );
      case Difficulty.hard:
        return const TracksRecipe(
          lowestTier: Difficulty.hard,
          highestTier: Difficulty.hard,
          floor: 5,
          ceiling: 7,
          band: TracksWalkBand(minLength: 27, maxLength: 45, minTurns: 9),
        );
      case Difficulty.expert:
        break;
    }
  }
  throw ArgumentError.value(
    '${spec.label} ${difficulty.name}',
    'spec',
    'Tracks does not offer this combination',
  );
}

/// Builds the puzzle [id] names. The same ID always returns the same puzzle.
///
/// Draw the ports, walk a path between them, fix every piece of it, take
/// pieces away while deduction still finishes the puzzle, judge what is left
/// by the techniques it needs, and start over if it missed
/// (`PLAN-phase-9-tracks.md` §4.5). Every choice comes from [Rng] seeded from
/// the ID, so this is a pure function of its argument on every platform and in
/// every release, which is what lets a save store the ID and throw the grid
/// away.
///
/// The seed derivation is frozen along with everything it feeds, and is the one
/// `generateSudoku` uses:
///
/// ```
/// attempt 0 : seed = fnv1a32(id.value)
/// attempt n : seed = fnv1a32('${id.value}#$n')
/// ```
///
/// Within an attempt the draws are, in order: the ports (`drawTracksPorts`),
/// the walk (`walkTracksPath`), and one shuffle of the path for the dig. An
/// attempt whose walk exhausts its step budget is spent without the later
/// draws.
///
/// Never throws for a puzzle it cannot make well: after
/// [generatorMaxAttempts] it returns the closest attempt with `widened: true`.
/// It does throw [ArgumentError] for a combination that does not exist, which
/// is a caller mistake rather than a hard puzzle.
TracksPuzzle generateTracks(TracksPuzzleId id) =>
    generateTracksWith(id, tracksRecipeFor(id.spec, id.difficulty));

/// [generateTracks] with the recipe supplied rather than looked up.
///
/// Not exported from the package: it exists so a test can ask for a recipe no
/// puzzle satisfies and watch the widening path run, and so the measurement
/// that chose the recipes in [tracksRecipeFor] could try candidates without
/// editing them.
TracksPuzzle generateTracksWith(TracksPuzzleId id, TracksRecipe recipe) {
  _Attempt? closest;

  for (var attempt = 0; attempt < generatorMaxAttempts; attempt++) {
    final seed = attempt == 0
        ? fnv1a32(id.value)
        : fnv1a32('${id.value}#$attempt');
    final rng = Rng(seed);

    final (startRow, goalColumn) = drawTracksPorts(id.spec, rng);
    final path = walkTracksPath(
      id.spec,
      startRow,
      goalColumn,
      rng,
      recipe.band,
    );
    if (path == null) continue;

    final solution = tracksSolutionFor(id.spec, path);
    final candidate = _dig(
      id.spec,
      startRow,
      goalColumn,
      path,
      solution,
      rng,
      recipe,
      attempt + 1,
    );

    final wanted = recipe.accepts(candidate.tier, candidate.fixedCount);
    if (!wanted && closest != null && !_closer(closest, candidate, recipe)) {
      continue;
    }

    // The independent check, only for an attempt about to be returned: a
    // report of "solved" already proves uniqueness (`solveTracks`), so this
    // second opinion from the exhaustive counter guards against a bug in a
    // deduction rather than doing the work of the dig, and an attempt that
    // would be thrown away anyway is not worth its cost. One that fails is
    // spent like a walk that missed, so a wrong rule can cost a puzzle but
    // never ship one.
    if (countTracksSolutions(candidate.clues) != 1) continue;

    if (wanted) return candidate.toPuzzle(id, widened: false);
    closest = candidate;
  }

  if (closest == null) {
    throw StateError(
      'no attempt of $generatorMaxAttempts produced a $id, which cannot be',
    );
  }
  return closest.toPuzzle(id, widened: true);
}

/// One try at a puzzle, kept so the retry loop has something to settle for.
class _Attempt {
  const _Attempt({
    required this.number,
    required this.clues,
    required this.solution,
    required this.tier,
    required this.fixedCount,
  });

  final int number;
  final TracksClues clues;
  final List<int> solution;
  final Difficulty tier;
  final int fixedCount;

  TracksPuzzle toPuzzle(TracksPuzzleId id, {required bool widened}) =>
      TracksPuzzle(
        id: id,
        clues: clues,
        solution: solution,
        tier: tier,
        attempts: number,
        widened: widened,
      );
}

/// Whether [fresh] is nearer to what was asked for than [held].
///
/// Tier distance first, because a Hard puzzle offered as Medium is a worse
/// answer than a Medium one with two pieces too many. Then distance from the
/// fixed-piece band, and on a tie the earlier attempt wins, because the choice
/// has to be the same on every device and "the first of the equally close" is a
/// rule that depends on nothing but the sequence.
bool _closer(_Attempt held, _Attempt fresh, TracksRecipe recipe) {
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
  if (freshTier != heldTier) return freshTier < heldTier;

  final heldFixed = _distance(held.fixedCount, recipe.floor, recipe.ceiling);
  final freshFixed = _distance(fresh.fixedCount, recipe.floor, recipe.ceiling);
  return freshFixed < heldFixed;
}

/// How far [value] falls outside `low..high`; 0 when it is inside.
int _distance(int value, int low, int high) {
  if (value < low) return low - value;
  if (value > high) return value - high;
  return 0;
}

/// Unfixes the pieces of [path] in [rng] order, keeping a piece unfixed only
/// while deduction at [TracksRecipe.highestTier] still finishes the puzzle.
///
/// The two stopping rules are Sudoku's `_dig`, for the same reasons
/// (`generator.dart`):
///
/// - **The ceiling.** A removal that needs a technique above
///   [TracksRecipe.highestTier] is put back, because the solver at that ceiling
///   reports it unsolved. Without it the dig lands on whatever tier its fixed
///   count happens to produce.
/// - **The floor, but only once the ceiling tier has been reached.** Digging to
///   exhaustion lands far below any Easy band, so Easy is reached from above,
///   and Medium and Hard are reached on the way down rather than at a fixed
///   count. Stopping at the floor regardless would throw away a puzzle that is
///   still Easy there when a few more removals would have made it Medium.
///
/// There is no uniqueness check per removal. A report of "solved" from
/// `solveTracks` is a proof of uniqueness, because every rule is a consequence
/// of the game's rules, so a removal the solver can still finish is a removal
/// that keeps one solution. That is what makes this dig cheaper than
/// Sudoku's, which has to call its counter after each hole.
_Attempt _dig(
  TracksSpec spec,
  int startRow,
  int goalColumn,
  List<int> path,
  List<int> solution,
  Rng rng,
  TracksRecipe recipe,
  int number,
) {
  final side = spec.side;
  final rowCounts = List<int>.filled(side, 0);
  final columnCounts = List<int>.filled(side, 0);
  for (final cell in path) {
    rowCounts[spec.rowOf(cell)]++;
    columnCounts[spec.columnOf(cell)]++;
  }

  TracksClues cluesFor(List<int> fixed) => TracksClues(
    spec: spec,
    startRow: startRow,
    goalColumn: goalColumn,
    rowCounts: rowCounts,
    columnCounts: columnCounts,
    fixed: fixed,
  );

  final fixed = List<int>.of(solution);
  var fixedCount = path.length;
  final order = List<int>.of(path);
  rng.shuffle(order);

  var tier = Difficulty.easy;
  for (final cell in order) {
    if (tier == recipe.highestTier && fixedCount <= recipe.floor) break;

    final piece = fixed[cell];
    fixed[cell] = 0;
    final report = solveTracks(cluesFor(fixed), ceiling: recipe.highestTier);
    if (report.solved) {
      tier = report.tier;
      fixedCount--;
    } else {
      fixed[cell] = piece;
    }
  }

  // Judged again on what was left rather than trusting the last removal's
  // report, so the tier on the puzzle is by construction the one the fuzz will
  // re-derive from its clues.
  final clues = cluesFor(fixed);
  return _Attempt(
    number: number,
    clues: clues,
    solution: solution,
    tier: solveTracks(clues, ceiling: recipe.highestTier).tier,
    fixedCount: fixedCount,
  );
}
