// The Tracks puzzle record's tests: that what the generator makes survives the
// encode and decode the cache puts it through, and that each way an entry can
// be wrong is refused with a FormatException and nothing else.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_record.dart';
import 'package:zibo_games/features/tracks/model/tracks_session_codec.dart';

import '../tracks_fixtures.dart';

void main() {
  final id = TracksPuzzleId.parse('tracks:5x5:easy:0');
  final record = TracksPuzzleRecord.of(puzzleFor(id.value));
  final encoded = record.encode();
  final split = encoded.lastIndexOf('|');
  final clueLine = encoded.substring(0, split);
  final solutionLine = encoded.substring(split + 1);

  /// Decoding [text] must fail with a FormatException, not any other error.
  void expectRefused(String text, {TracksPuzzleId? as}) {
    expect(
      () => TracksPuzzleRecord.decode(as ?? id, text),
      throwsA(isA<FormatException>()),
      reason: text,
    );
  }

  group('round trip', () {
    for (final name in [
      'tracks:5x5:easy:0',
      'tracks:7x7:easy:0',
      'tracks:9x9:easy:0',
    ]) {
      test('a generated $name decodes to what it was', () {
        final puzzleId = TracksPuzzleId.parse(name);
        final original = TracksPuzzleRecord.of(puzzleFor(name));

        final decoded = TracksPuzzleRecord.decode(puzzleId, original.encode());

        expect(decoded, original);
        expect(decoded.hashCode, original.hashCode);
        expect(decoded.clues, puzzleFor(name).clues);
        expect(decoded.solution, puzzleFor(name).solution);
      });
    }

    test('the solution cannot be changed through the record', () {
      expect(() => record.solution[0] = 5, throwsUnsupportedError);
    });

    test('toString names the encoded form', () {
      expect(record.toString(), 'TracksPuzzleRecord($encoded)');
    });
  });

  group('refuses', () {
    test('an entry with no separator', () {
      expectRefused('');
      expectRefused('not a puzzle');
    });

    test('a clue line that does not decode', () {
      expectRefused('garbage|$solutionLine');
      expectRefused('|$solutionLine');
    });

    test('clues for another size', () {
      final other = TracksPuzzleId.parse('tracks:7x7:easy:0');
      expectRefused(TracksPuzzleRecord.of(puzzleFor(other.value)).encode());
    });

    test('a solution that is too short, too long or not hex', () {
      expectRefused('$clueLine|${solutionLine.substring(1)}');
      expectRefused('$clueLine|${solutionLine}0');
      expectRefused('$clueLine|${'z' * solutionLine.length}');
      expectRefused('$clueLine|');
    });

    test('a solution mask that is neither empty nor a piece', () {
      // 3 is north and east: a bend, so a piece. 15 is all four sides.
      final cells = decodeTracksCells(id.spec, solutionLine);
      final cell = cells.indexOf(0);
      expect(cell, isNonNegative, reason: 'the fixture has an empty cell');
      final broken = [...cells]..[cell] = 15;

      expectRefused('$clueLine|${encodeTracksCells(id.spec, broken)}');
    });

    test('a fixed clue the solution disagrees with', () {
      final cells = decodeTracksCells(id.spec, solutionLine);
      final cell = record.clues.fixed.indexWhere((mask) => mask != 0);
      expect(cell, isNonNegative, reason: 'the fixture has a fixed piece');
      final other = TrackSide.pieces.firstWhere(
        (piece) => piece != record.clues.fixed[cell],
      );
      final broken = [...cells]..[cell] = other;

      expectRefused('$clueLine|${encodeTracksCells(id.spec, broken)}');
    });
  });
}
