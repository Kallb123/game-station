// The Tracks generator, like Sudoku's, is a stored format: a save keeps the ID
// and throws the grid away. These tests check the contract for a handful of
// indices per combination; the volume run is `fuzz_test.dart` and the frozen
// output is `determinism_test.dart`'s goldens.
//
// `TRACKS_INDICES` raises the count per combination from the default 20, the
// figure the plan's PR 3 asks for (`PLAN-phase-9-tracks.md` §6).

import 'dart:io';

import 'package:puzzle_engine/src/difficulty.dart';
import 'package:puzzle_engine/src/generator.dart' show generatorMaxAttempts;
import 'package:puzzle_engine/src/hash.dart';
import 'package:puzzle_engine/src/rng.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_counter.dart';
import 'package:puzzle_engine/src/tracks/tracks_deduction.dart';
import 'package:puzzle_engine/src/tracks/tracks_generator.dart';
import 'package:puzzle_engine/src/tracks/tracks_puzzle_id.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:puzzle_engine/src/tracks/tracks_walk.dart';
import 'package:test/test.dart';

import '../combinations.dart';
import 'tracks_fixtures.dart';

/// How many indices of each combination to generate.
final int indices =
    int.tryParse(Platform.environment['TRACKS_INDICES'] ?? '') ?? 20;

void main() {
  group('every puzzle it makes', () {
    for (final (spec, difficulty) in tracksCombinations) {
      test('${spec.label} ${difficulty.name} is a real puzzle', () {
        for (var index = 0; index < indices; index++) {
          final id = TracksPuzzleId(spec, difficulty, index);
          final puzzle = generateTracks(id);
          final where = '$puzzle';

          expect(puzzle.id, id, reason: where);
          expect(puzzle.requested, difficulty, reason: where);
          expect(puzzle.attempts, greaterThanOrEqualTo(1), reason: where);
          expect(puzzle.widened, isFalse, reason: where);

          // The tier is the label: no combination here is Easy by technique
          // under a harder name (`tracksRecipeFor`).
          expect(puzzle.tier, difficulty, reason: where);
          expect(solveTracks(puzzle.clues).tier, difficulty, reason: where);

          expect(countTracksSolutions(puzzle.clues), 1, reason: where);
          expect(brokenRules(puzzle.clues, puzzle.solution), isEmpty);

          // Every fixed piece is the solution's piece, and the cache line
          // round-trips: what a save would hold rebuilds the same clues.
          for (var cell = 0; cell < spec.cells; cell++) {
            final fixed = puzzle.clues.fixed[cell];
            if (fixed != 0) expect(fixed, puzzle.solution[cell], reason: where);
          }
          expect(
            TracksClues.decode(puzzle.clues.encode()).encode(),
            puzzle.clues.encode(),
          );
        }
      });

      test('${spec.label} ${difficulty.name} keeps to its recipe', () {
        final recipe = tracksRecipeFor(spec, difficulty);
        for (var index = 0; index < indices; index++) {
          final puzzle = generateTracks(
            TracksPuzzleId(spec, difficulty, index),
          );
          final fixed = puzzle.clues.fixed.where((m) => m != 0).length;
          final length = puzzle.solution.where((m) => m != 0).length;
          final where = '$puzzle with $fixed fixed';

          expect(recipe.accepts(puzzle.tier, fixed), isTrue, reason: where);
          expect(
            length,
            inInclusiveRange(recipe.band.minLength, recipe.band.maxLength),
            reason: where,
          );
          expect(
            tracksTurns(puzzle.solution),
            greaterThanOrEqualTo(recipe.band.minTurns),
            reason: where,
          );
        }
      });
    }

    test('easy carries more fixed pieces than medium, medium than hard', () {
      for (final spec in TracksSpec.supported) {
        var previous = 1 << 30;
        for (final difficulty in Difficulty.values) {
          if (difficulty == Difficulty.expert) continue;
          if (!tracksCombinations.contains((spec, difficulty))) continue;
          final floor = tracksRecipeFor(spec, difficulty).floor;
          expect(
            floor,
            lessThan(previous),
            reason: '${spec.label} $difficulty',
          );
          previous = floor;
        }
      }
    });
  });

  group('the recipes', () {
    test('refuse Expert at every size', () {
      for (final spec in TracksSpec.supported) {
        expect(
          () => tracksRecipeFor(spec, Difficulty.expert),
          throwsArgumentError,
          reason: spec.label,
        );
      }
      expect(
        () => generateTracks(
          const TracksPuzzleId(TracksSpec.s7x7, Difficulty.expert, 0),
        ),
        throwsArgumentError,
      );
    });

    test('refuse 5x5 Hard, which TracksPuzzleId.parse does not spell', () {
      expect(
        () => tracksRecipeFor(TracksSpec.s5x5, Difficulty.hard),
        throwsArgumentError,
      );
      expect(
        () => generateTracks(
          const TracksPuzzleId(TracksSpec.s5x5, Difficulty.hard, 0),
        ),
        throwsArgumentError,
      );
    });

    test('refuse a size that is not offered', () {
      expect(
        () => tracksRecipeFor(const TracksSpec(6), Difficulty.easy),
        throwsArgumentError,
      );
    });

    test('exist for exactly the combinations the engine lists', () {
      for (final spec in TracksSpec.supported) {
        for (final difficulty in Difficulty.values) {
          final listed = tracksCombinations.contains((spec, difficulty));
          Object? thrown;
          try {
            tracksRecipeFor(spec, difficulty);
          } on ArgumentError catch (e) {
            thrown = e;
          }
          expect(thrown == null, listed, reason: '${spec.label} $difficulty');
        }
      }
    });
  });

  group('the same ID', () {
    test('produces the same puzzle, down to the attempt count', () {
      for (final (spec, difficulty) in tracksCombinations) {
        for (var index = 0; index < indices; index++) {
          final id = TracksPuzzleId(spec, difficulty, index);
          final first = generateTracks(id);
          final second = generateTracks(id);

          expect(first.clues.encode(), second.clues.encode(), reason: '$id');
          expect(first.solution, second.solution, reason: '$id');
          expect(first.tier, second.tier, reason: '$id');
          expect(first.attempts, second.attempts, reason: '$id');
          expect(first.widened, second.widened, reason: '$id');
        }
      }
    });

    test('is reproduced from its parsed string', () {
      expect(
        generateTracks(
          TracksPuzzleId.parse('tracks:7x7:medium:7'),
        ).clues.encode(),
        generateTracks(
          const TracksPuzzleId(TracksSpec.s7x7, Difficulty.medium, 7),
        ).clues.encode(),
      );
    });
  });

  group('different IDs', () {
    test('are different puzzles, not one puzzle dug twice', () {
      final lines = <String>{};
      var made = 0;
      for (final (spec, difficulty) in tracksCombinations) {
        for (var index = 0; index < 10; index++) {
          lines.add(
            generateTracks(
              TracksPuzzleId(spec, difficulty, index),
            ).clues.encode(),
          );
          made++;
        }
      }
      expect(lines.length, made);
    });
  });

  group('when the recipe cannot be met', () {
    // A fixed-piece floor above the whole path: the dig stops before it removes
    // anything, so every attempt is a fully fixed path, never inside the band,
    // and the closest is the one with the most pieces.
    const impossible = TracksRecipe(
      lowestTier: Difficulty.easy,
      highestTier: Difficulty.easy,
      floor: 99,
      ceiling: 99,
      band: TracksWalkBand(minLength: 9, maxLength: 15, minTurns: 3),
    );
    const id = TracksPuzzleId(TracksSpec.s5x5, Difficulty.easy, 3);

    test('it widens after every attempt rather than throwing', () {
      final puzzle = generateTracksWith(id, impossible);
      expect(puzzle.widened, isTrue);
      expect(countTracksSolutions(puzzle.clues), 1);
      expect(brokenRules(puzzle.clues, puzzle.solution), isEmpty);
      expect(puzzle.toString(), contains('widened from easy'));
      expect(
        generateTracksWith(id, impossible).clues.encode(),
        puzzle.clues.encode(),
      );
    });

    test('it keeps the attempt nearest the band, earliest on a tie', () {
      final puzzle = generateTracksWith(id, impossible);

      // Rebuild every attempt's path with the generator's seeds: the winner is
      // the first one of the longest length, not simply the first.
      final lengths = <int>[];
      for (var attempt = 0; attempt < generatorMaxAttempts; attempt++) {
        final rng = Rng(
          attempt == 0 ? fnv1a32(id.value) : fnv1a32('${id.value}#$attempt'),
        );
        final (row, column) = drawTracksPorts(id.spec, rng);
        final path = walkTracksPath(id.spec, row, column, rng, impossible.band);
        lengths.add(path?.length ?? 0);
      }
      final longest = lengths.reduce((a, b) => a > b ? a : b);
      expect(puzzle.solution.where((m) => m != 0).length, longest);
      expect(puzzle.attempts, lengths.indexOf(longest) + 1);
    });
  });

  group('the hint', () {
    test('walks a generated puzzle to solved from an empty board', () {
      for (final (spec, difficulty) in tracksCombinations) {
        for (var index = 0; index < 3; index++) {
          final puzzle = generateTracks(
            TracksPuzzleId(spec, difficulty, index),
          );
          final board = List<int>.filled(spec.cells, 0);
          // Fixed pieces are on the board from the start, as the session will
          // show them; the hint never names one.
          for (var cell = 0; cell < spec.cells; cell++) {
            board[cell] = puzzle.clues.fixed[cell];
          }

          var steps = 0;
          while (true) {
            final step = nextTracksStep(puzzle.clues, board);
            if (step == null) break;
            expect(step.mask, puzzle.solution[step.cell], reason: '$puzzle');
            expect(board[step.cell], isNot(step.mask));
            board[step.cell] = step.mask;
            expect(++steps, lessThanOrEqualTo(spec.cells), reason: '$puzzle');
          }
          expect(board, puzzle.solution, reason: '$puzzle');
        }
      }
    });
  });
}
