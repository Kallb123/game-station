import '../difficulty.dart';
import 'tracks_clues.dart';
import 'tracks_puzzle_id.dart';

/// One Tracks puzzle, and what it cost to make (`PLAN-phase-9-tracks.md` §4.3).
///
/// The counterpart of `GeneratedPuzzle`: the clues are what the player sees and
/// the cache line encodes, and the rest is what the generator knows about them.
class TracksPuzzle {
  /// A puzzle for [id] with the clues, their one solution and the retry count.
  ///
  /// Stores an unmodifiable copy of [solution], so a session holding the
  /// puzzle cannot corrupt the answer it checks hints against.
  TracksPuzzle({
    required this.id,
    required this.clues,
    required List<int> solution,
    required this.tier,
    required this.attempts,
    required this.widened,
  }) : solution = List.unmodifiable(solution);

  /// The ID this was generated from. Regenerating it reproduces this exactly.
  final TracksPuzzleId id;

  /// The puzzle as the player sees it: ports, counts and the pieces laid.
  final TracksClues clues;

  /// The one completion of [clues], as connection masks in row-major order
  /// with the port bits set. Not stored in a save: it is regenerated from the
  /// ID or recovered by the solver from [clues] (§4.3).
  final List<int> solution;

  /// The tier that was asked for.
  Difficulty get requested => id.difficulty;

  /// The tier the deduction solver needed, which is what the puzzle earned
  /// (§4.5). Read [widened] to tell "what was asked for" from "the closest
  /// thing to it".
  final Difficulty tier;

  /// How many attempts it took, counting the one that produced this.
  final int attempts;

  /// Whether the generator settled for something other than what was asked,
  /// after exhausting its attempts. The puzzle is shown anyway: a child cannot
  /// act on "could not generate a puzzle" (`AGENTS.md`).
  final bool widened;

  @override
  String toString() =>
      'TracksPuzzle($id, ${tier.name}, '
      '$attempts attempt${attempts == 1 ? '' : 's'}'
      '${widened ? ', widened from ${requested.name}' : ''})';
}
