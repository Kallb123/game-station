// The session model's tests.
//
// Plain `test()` calls with no `pumpWidget`, because the model imports nothing
// of Flutter beyond `foundation.dart` (`PLAN-phase-3.md` §5) — the whole file
// is milliseconds, so the widget tests that come next have no reason to cover
// any of it again.
//
// The puzzles are real, from the shared fixtures: a made-up grid would let a
// test pass against a board no engine would produce, and the point of `isWrong`
// and `isSolved` is that they agree with a solution the generator wrote.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/sudoku/data/puzzle_record.dart';
import 'package:zibo_games/features/sudoku/model/session_codec.dart';
import 'package:zibo_games/features/sudoku/model/sudoku_session.dart';

import '../puzzle_fixtures.dart';

void main() {
  final id = PuzzleId.parse('sudoku:9x9:easy:7');
  final spec = id.spec;
  final record = fixtureRecord(id);

  SudokuSession start() => SudokuSession.start(id: id, record: record);

  /// The first cell the puzzle leaves empty, and the digit that belongs there.
  final firstEmpty = record.clues.indexOf('.');
  final firstGiven = record.clues.indexOf(RegExp('[1-9]'));
  int solutionAt(int index) => int.parse(record.solution[index]);

  /// A digit that is not the solution's, so entering it is a mistake.
  int wrongAt(int index) => solutionAt(index) % spec.digits + 1;

  group('a fresh session', () {
    test('starts from the clues with nothing else on the board', () {
      final session = start();

      for (var index = 0; index < spec.cells; index++) {
        final clue = record.clues[index];
        expect(session.digitAt(index), clue == '.' ? 0 : int.parse(clue));
        expect(session.isGiven(index), clue != '.');
        expect(session.notesAt(index), 0);
        expect(session.isWrong(index), isFalse);
      }
      expect(session.selected, isNull);
      expect(session.pencilMode, isFalse);
      expect(session.mistakes, 0);
      expect(session.hints, 0);
      expect(session.elapsed, Duration.zero);
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isFalse);
      expect(session.isSolved, isFalse);
    });

    test('notifies when the selection changes, and not when it does not', () {
      final session = start();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.select(firstEmpty);
      session.select(firstEmpty);
      expect(notifications, 1);

      session.select(null);
      expect(notifications, 2);
    });

    test('refuses a selection outside the grid', () {
      expect(() => start().select(spec.cells), throwsRangeError);
      expect(() => start().select(-1), throwsRangeError);
    });
  });

  group('entering a digit', () {
    test('fills the selected cell', () {
      final session = start()..select(firstEmpty);

      session.enter(solutionAt(firstEmpty));

      expect(session.digitAt(firstEmpty), solutionAt(firstEmpty));
      expect(session.isWrong(firstEmpty), isFalse);
      expect(session.mistakes, 0);
    });

    test('does nothing without a selection', () {
      final session = start();

      session.enter(1);

      expect(session.canUndo, isFalse);
    });

    test('cannot overwrite a given', () {
      final session = start()..select(firstGiven);
      final clue = solutionAt(firstGiven);

      session
        ..enter(clue % spec.digits + 1)
        ..erase();

      expect(session.digitAt(firstGiven), clue);
      expect(session.canUndo, isFalse);
      expect(session.mistakes, 0);
    });

    test('counts a wrong digit as a mistake and flags the cell', () {
      final session = start()..select(firstEmpty);

      session.enter(wrongAt(firstEmpty));

      expect(session.isWrong(firstEmpty), isTrue);
      expect(session.mistakes, 1);
    });

    test('does not count the same wrong digit twice, or a corrected one', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(wrongAt(firstEmpty))
        ..enter(wrongAt(firstEmpty))
        ..enter(solutionAt(firstEmpty));

      expect(session.isWrong(firstEmpty), isFalse);
      // Corrected on the board, not in the history: `SolvedPuzzle.mistakes` is
      // what decides the clean star.
      expect(session.mistakes, 1);
    });

    test('clears the cell notes, which were a question the digit answers', () {
      final session = start()..select(firstEmpty);

      session
        ..pencilMode = true
        ..enter(1)
        ..pencilMode = false
        ..enter(solutionAt(firstEmpty));

      expect(session.notesAt(firstEmpty), 0);
    });

    test('refuses a digit the size does not have', () {
      final session = start()..select(firstEmpty);

      expect(() => session.enter(0), throwsRangeError);
      expect(() => session.enter(spec.digits + 1), throwsRangeError);
    });
  });

  group('pencil marks', () {
    test('toggle on and off, one bit per digit', () {
      final session = start()
        ..select(firstEmpty)
        ..pencilMode = true;

      session
        ..enter(1)
        ..enter(4);
      expect(session.notesAt(firstEmpty), 1 | 1 << 3);

      session.enter(1);
      expect(session.notesAt(firstEmpty), 1 << 3);
      expect(session.digitAt(firstEmpty), 0);
    });

    test('are not written under a digit, where nothing would show them', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(solutionAt(firstEmpty))
        ..pencilMode = true
        ..enter(2);

      expect(session.notesAt(firstEmpty), 0);
      expect(session.toSaved().undoStack, hasLength(1));
    });
  });

  group('erasing', () {
    test('clears the digit and the notes together', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(solutionAt(firstEmpty))
        ..erase();

      expect(session.digitAt(firstEmpty), 0);
      expect(session.notesAt(firstEmpty), 0);
    });

    test('does nothing to an already empty cell', () {
      final session = start()..select(firstEmpty);

      session.erase();

      expect(session.canUndo, isFalse);
    });
  });

  group('undo and redo', () {
    test('walk back through digits and notes alike', () {
      final session = start()..select(firstEmpty);
      final digit = solutionAt(firstEmpty);

      session
        ..pencilMode = true
        ..enter(3)
        ..pencilMode = false
        ..enter(digit)
        ..erase();
      expect(session.digitAt(firstEmpty), 0);
      expect(session.notesAt(firstEmpty), 0);

      session.undo();
      expect(session.digitAt(firstEmpty), digit);

      session.undo();
      expect(session.digitAt(firstEmpty), 0);
      expect(session.notesAt(firstEmpty), 1 << 2);

      session.undo();
      expect(session.notesAt(firstEmpty), 0);
      expect(session.canUndo, isFalse);

      session.undo();
      expect(session.notesAt(firstEmpty), 0);
    });

    test('put back what the other took away', () {
      final session = start()..select(firstEmpty);
      final digit = solutionAt(firstEmpty);

      session
        ..enter(digit)
        ..undo();
      expect(session.canRedo, isTrue);

      session.redo();
      expect(session.digitAt(firstEmpty), digit);
      expect(session.canRedo, isFalse);
      expect(session.canUndo, isTrue);
    });

    test('select the cell that changed, so the board shows what moved', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(solutionAt(firstEmpty))
        ..select(null)
        ..undo();

      expect(session.selected, firstEmpty);
    });

    test('do not take the mistake count back down', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(wrongAt(firstEmpty))
        ..undo();

      expect(session.isWrong(firstEmpty), isFalse);
      expect(session.mistakes, 1);
    });

    test('redo is dropped by a new move', () {
      final session = start()..select(firstEmpty);

      session
        ..enter(solutionAt(firstEmpty))
        ..undo();
      expect(session.canRedo, isTrue);

      session.enter(wrongAt(firstEmpty));

      expect(session.canRedo, isFalse);
    });

    test('keep the newest $undoStackCap moves and drop the oldest', () {
      final session = start()
        ..select(firstEmpty)
        ..pencilMode = true;

      /// The state the stack's oldest surviving entry restores: the cell as it
      /// stood before the move that pushed the first entry out.
      late int atCap;
      for (var move = 0; move < undoStackCap + 50; move++) {
        if (move == 50) atCap = session.notesAt(firstEmpty);
        session.enter(move % spec.digits + 1);
      }
      expect(session.toSaved().undoStack, hasLength(undoStackCap));

      for (var move = 0; move < undoStackCap; move++) {
        session.undo();
      }

      expect(session.canUndo, isFalse);
      expect(session.notesAt(firstEmpty), atCap);
    });
  });

  group('solving', () {
    test('is every cell agreeing with the solution', () {
      final session = start();

      for (var index = 0; index < spec.cells; index++) {
        if (session.isGiven(index)) continue;
        session
          ..select(index)
          ..enter(solutionAt(index));
      }

      expect(session.isSolved, isTrue);
      expect(session.mistakes, 0);
    });

    test('is not reached by a full board with a wrong digit in it', () {
      final session = start();

      for (var index = 0; index < spec.cells; index++) {
        if (session.isGiven(index)) continue;
        session
          ..select(index)
          ..enter(index == firstEmpty ? wrongAt(index) : solutionAt(index));
      }

      expect(session.isSolved, isFalse);
      expect(session.mistakes, 1);
    });
  });

  group('a digit being complete', () {
    /// The digit the solution puts in [firstEmpty], and every other cell it
    /// belongs in.
    final digit = solutionAt(firstEmpty);
    Iterable<int> cellsOf(int digit) sync* {
      for (var index = 0; index < spec.cells; index++) {
        if (solutionAt(index) == digit) yield index;
      }
    }

    test('is false until every cell it belongs in holds it', () {
      final session = start();
      final cells = cellsOf(digit).where((i) => !session.isGiven(i)).toList();

      for (final index in cells.take(cells.length - 1)) {
        session
          ..select(index)
          ..enter(digit);
        expect(session.isDigitComplete(digit), isFalse);
      }

      session
        ..select(cells.last)
        ..enter(digit);
      expect(session.isDigitComplete(digit), isTrue);
    });

    test('is not reached by a wrong digit standing in for it', () {
      final session = start();
      final cells = cellsOf(digit).where((i) => !session.isGiven(i)).toList();

      for (final index in cells) {
        session
          ..select(index)
          ..enter(wrongAt(index));
      }

      expect(session.isDigitComplete(digit), isFalse);
    });

    test('is not undone by a wrong digit placed elsewhere', () {
      final session = start();
      for (final index in cellsOf(digit)) {
        if (session.isGiven(index)) continue;
        session
          ..select(index)
          ..enter(digit);
      }
      expect(session.isDigitComplete(digit), isTrue);

      // A non-given cell the solution puts some other digit in, given a
      // wrong one.
      final elsewhere = List<int>.generate(spec.cells, (index) => index)
          .firstWhere(
            (index) => solutionAt(index) != digit && !session.isGiven(index),
          );
      session
        ..select(elsewhere)
        ..enter(wrongAt(elsewhere));

      expect(session.isDigitComplete(digit), isTrue);
    });
  });

  group('a hint', () {
    test('fills a cell the solution agrees with, and counts', () {
      final session = start();
      session.hint();

      final filled = session.selected;
      expect(filled, isNotNull);
      expect(session.isGiven(filled!), isFalse);
      expect(session.digitAt(filled), solutionAt(filled));
      expect(session.hints, 1);
      expect(session.mistakes, 0, reason: 'a hint is never a mistake');
    });

    test('is an ordinary move, so undo takes it back', () {
      final session = start();
      session.hint();
      final filled = session.selected!;

      session.undo();

      expect(session.digitAt(filled), 0);
      // The count does not come back down, for the same reason a corrected
      // mistake still counts: it records what was given away, not what is on
      // the board now.
      expect(session.hints, 1);
    });

    test('clears the pencil marks under the cell it fills', () {
      final session = start()
        ..select(firstEmpty)
        ..pencilMode = true
        ..enter(1)
        ..pencilMode = false;
      expect(session.notesAt(firstEmpty), isNot(0));

      // Whichever cell the hint lands on, that cell ends up holding a digit and
      // no marks — and this is the run where it lands on one that had some.
      while (session.digitAt(firstEmpty) == 0) {
        session.hint();
      }

      expect(session.notesAt(firstEmpty), 0);
    });

    test('points at a wrong digit instead of revealing anything', () {
      final session = start()
        ..select(firstEmpty)
        ..enter(wrongAt(firstEmpty));
      final before = [
        for (var index = 0; index < spec.cells; index++) session.digitAt(index),
      ];

      session.hint();

      expect(session.selected, firstEmpty);
      expect(session.isFlagged(firstEmpty), isTrue);
      expect(session.hints, 0, reason: 'pointing gives nothing away');
      expect(
        [
          for (var index = 0; index < spec.cells; index++)
            session.digitAt(index),
        ],
        before,
        reason: 'and changes no cell',
      );
    });

    test('points at the same cell twice rather than at the second mistake', () {
      // Deterministic, and the lowest index wins: a hint that walked to the
      // next mistake would let a child page through their errors without
      // fixing the first one.
      final second = record.clues.indexOf('.', firstEmpty + 1);
      final session = start()
        ..select(second)
        ..enter(wrongAt(second))
        ..select(firstEmpty)
        ..enter(wrongAt(firstEmpty));

      session
        ..hint()
        ..hint();

      expect(session.selected, firstEmpty);
      expect(session.hints, 0);
    });

    test('reveals the emptiest cell when technique has run out', () {
      // A board with no clues at all: no technique makes progress on one, which
      // is what `nextPlacement` returning null means (`technique_solver.dart`),
      // so this is the T4 path of `PLAN-phase-3.md` §4.6 without the seconds a
      // real Expert puzzle costs to generate. Every empty cell has the same
      // number of candidates, so the tie-break — the lowest index — is what
      // decides, and that is the property worth pinning.
      final session = SudokuSession.start(
        id: id,
        record: PuzzleRecord(
          clues: PuzzleRecord.emptyCell * spec.cells,
          solution: record.solution,
        ),
      );

      session.hint();

      expect(session.selected, 0);
      expect(session.digitAt(0), solutionAt(0));
      expect(session.hints, 1);
    });

    test('does nothing to a solved board', () {
      final session = start();
      for (var index = 0; index < spec.cells; index++) {
        if (session.isGiven(index)) continue;
        session
          ..select(index)
          ..enter(solutionAt(index));
      }

      session.hint();

      expect(session.hints, 0);
    });
  });

  group('mistake feedback', () {
    /// Fills every empty cell of [session] with the solution, except [wrong],
    /// which gets a digit the solution disagrees with.
    void fill(SudokuSession session, {required int wrong}) {
      for (var index = 0; index < spec.cells; index++) {
        if (session.isGiven(index)) continue;
        session
          ..select(index)
          ..enter(index == wrong ? wrongAt(index) : solutionAt(index));
      }
    }

    test('immediate flags a wrong digit as it is entered', () {
      final session = start()
        ..select(firstEmpty)
        ..enter(wrongAt(firstEmpty));

      expect(session.mistakeFeedback, MistakeFeedback.immediate);
      expect(session.isWrong(firstEmpty), isTrue);
      expect(session.isFlagged(firstEmpty), isTrue);
    });

    test('atCompletion says nothing until the grid is full', () {
      final session = SudokuSession.start(
        id: id,
        record: record,
        mistakeFeedback: MistakeFeedback.atCompletion,
      );

      session
        ..select(firstEmpty)
        ..enter(wrongAt(firstEmpty));
      expect(session.isWrong(firstEmpty), isTrue);
      expect(
        session.isFlagged(firstEmpty),
        isFalse,
        reason: 'the fact is known; the board has not said so',
      );

      fill(session, wrong: firstEmpty);

      expect(session.isFull, isTrue);
      expect(session.isSolved, isFalse);
      expect(
        session.isFlagged(firstEmpty),
        isTrue,
        reason: 'a full grid that is not solved has to say why',
      );
    });

    test('atCompletion still flags the cell a hint pointed at', () {
      // Otherwise the hint would select a cell in silence, which tells a child
      // nothing at all (`PLAN-phase-3.md` §4.6).
      final session =
          SudokuSession.start(
              id: id,
              record: record,
              mistakeFeedback: MistakeFeedback.atCompletion,
            )
            ..select(firstEmpty)
            ..enter(wrongAt(firstEmpty));
      expect(session.isFlagged(firstEmpty), isFalse);

      session.hint();

      expect(session.isFlagged(firstEmpty), isTrue);
    });

    test('counts a mistake in both modes, because the star depends on it', () {
      final session =
          SudokuSession.start(
              id: id,
              record: record,
              mistakeFeedback: MistakeFeedback.atCompletion,
            )
            ..select(firstEmpty)
            ..enter(wrongAt(firstEmpty));

      expect(session.mistakes, 1);
    });
  });

  group('saving and resuming', () {
    /// A board with entries, notes, a wrong digit and history on it.
    SudokuSession played() {
      final session = start();
      var entered = 0;
      for (var index = 0; index < spec.cells && entered < 12; index++) {
        if (session.isGiven(index)) continue;
        session.select(index);
        if (entered.isEven) {
          session.enter(entered == 4 ? wrongAt(index) : solutionAt(index));
        } else {
          session
            ..pencilMode = true
            ..enter(entered % spec.digits + 1)
            ..enter((entered + 3) % spec.digits + 1)
            ..pencilMode = false;
        }
        entered++;
      }
      return session
        ..undo()
        ..elapsed = const Duration(minutes: 3, seconds: 14);
    }

    test('a played board resumes to an identical model', () {
      final before = played();
      final saved = before.toSaved();

      final after = SudokuSession.resume(id: id, record: record, saved: saved);

      for (var index = 0; index < spec.cells; index++) {
        expect(
          after.digitAt(index),
          before.digitAt(index),
          reason: 'digit at cell $index',
        );
        expect(
          after.notesAt(index),
          before.notesAt(index),
          reason: 'notes at cell $index',
        );
        expect(
          after.isGiven(index),
          before.isGiven(index),
          reason: 'given at cell $index',
        );
        expect(
          after.isWrong(index),
          before.isWrong(index),
          reason: 'wrong at cell $index',
        );
      }
      expect(after.elapsed, before.elapsed);
      expect(after.hints, before.hints);
      expect(after.toSaved().undoStack, saved.undoStack);
      expect(after.toSaved(), saved);
    });

    test('the undo stack still walks the board back after a resume', () {
      final before = played();
      final after = SudokuSession.resume(
        id: id,
        record: record,
        saved: before.toSaved(),
      );

      while (before.canUndo) {
        before.undo();
        after.undo();
      }

      expect(after.toSaved().grid, before.toSaved().grid);
      expect(after.toSaved().notes, before.toSaved().notes);
    });

    test('carries the hint count, which nothing else restores', () {
      final saved = played().toSaved();

      final after = SudokuSession.resume(
        id: id,
        record: record,
        saved: PuzzleInProgress(
          grid: saved.grid,
          notes: saved.notes,
          elapsedMs: saved.elapsedMs,
          undoStack: saved.undoStack,
          hints: 3,
        ),
      );

      expect(after.hints, 3);
      expect(after.toSaved().hints, 3);
    });

    test('counts the wrong digits it resumes with as mistakes', () {
      final before = played();

      final after = SudokuSession.resume(
        id: id,
        record: record,
        saved: before.toSaved(),
      );

      expect(before.mistakes, 1);
      expect(after.mistakes, 1);
    });

    test('starts with nothing to redo', () {
      final before = played();
      expect(before.canRedo, isTrue);

      final after = SudokuSession.resume(
        id: id,
        record: record,
        saved: before.toSaved(),
      );

      expect(after.canRedo, isFalse);
      expect(after.canUndo, isTrue);
    });

    test('brings an over-long undo stack back inside the cap at once', () {
      // A hand-edited file, or one written by a build whose cap was larger.
      // Trimming a move at a time would leave the save over its size for the
      // next few hundred taps.
      final saved = played().toSaved();

      final after = SudokuSession.resume(
        id: id,
        record: record,
        saved: PuzzleInProgress(
          grid: saved.grid,
          undoStack: [
            for (var move = 0; move < undoStackCap + 5; move++) '0.0.$move',
          ],
        ),
      );

      expect(after.toSaved().undoStack, hasLength(undoStackCap));
      // The newest are the ones kept: the oldest five are what fell off.
      expect(after.toSaved().undoStack.last, '0.0.${undoStackCap + 4}');
    });

    test('rejects a truncated grid rather than decoding it', () {
      final saved = played().toSaved();

      expect(
        () => SudokuSession.resume(
          id: id,
          record: record,
          saved: PuzzleInProgress(
            grid: saved.grid.substring(0, saved.grid.length - 1),
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects a grid that disagrees with the puzzle it is resumed as', () {
      // The same length and the same alphabet: only a clue is missing, which is
      // what a save paired with the wrong id looks like.
      final saved = played().toSaved();

      expect(
        () => SudokuSession.resume(
          id: id,
          record: record,
          saved: PuzzleInProgress(
            grid: saved.grid.replaceRange(firstGiven, firstGiven + 1, '.'),
          ),
        ),
        throwsFormatException,
      );
    });

    test('rejects an undo entry that is not a move on this board', () {
      final saved = played().toSaved();

      expect(
        () => SudokuSession.resume(
          id: id,
          record: record,
          saved: PuzzleInProgress(
            grid: saved.grid,
            undoStack: ['${spec.cells}.1.0'],
          ),
        ),
        throwsFormatException,
      );
    });
  });
}
