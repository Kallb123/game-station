// One puzzle being played: the digits, the pencil marks, what is selected, and
// enough history to walk back out of it.
//
// It is a [ChangeNotifier] rather than a Riverpod type, matching
// `ProgressRepository`: a model that already depends on the state library
// cannot be tested without it, and the grid subscribes per cell rather than
// rebuilding eighty-one of them per keystroke (`PLAN-phase-3.md` §3, §4.5).
// Nothing here imports Flutter beyond `foundation.dart`, so its tests are plain
// `test()` calls with no `pumpWidget` and the whole file runs in milliseconds.
//
// **The session holds its own list of digits rather than a `SudokuBoard`.**
// `SudokuBoard.place` refuses a digit that repeats one in its row, column or
// box, and `SudokuBoard.fromClues` throws on one, so a board holding a child's
// wrong digit cannot be built at all (`PLAN-phase-3.md` §4.3). A `SudokuBoard`
// is constructed only where one is needed — in [SudokuSession.hint] — and only
// once every entered digit is known to match the solution.

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/save_data.dart';
import '../data/puzzle_record.dart';
import 'session_codec.dart';

/// What a mutation did, for the screen above to turn into a sound
/// (`PLAN-phase-5.md` §4.3). [SudokuSession.takeEvent] clears the slot it
/// comes from, so an event plays once and only once.
enum SudokuEvent {
  /// A digit was entered, on a profile that does not say whether it was right
  /// until the grid is full.
  placed,

  /// A digit was entered, and it was right, on a profile that flags mistakes
  /// immediately.
  placedCorrect,

  /// A digit was entered, and it was wrong, on a profile that flags mistakes
  /// immediately.
  placedWrong,

  /// A pencil mark was toggled, on or off.
  noted,

  /// A cell was cleared.
  erased,

  /// A hint fired — pointing at a mistake already on the board and revealing
  /// a cell are the same event, because both tell a child the same thing:
  /// look here.
  hinted,

  /// An undo or a redo changed the board back.
  restored,

  /// The move that filled the last cell the solution agrees with. Replaces
  /// whichever of the above the move would otherwise have been, so a
  /// finishing digit is one sound, not two 20 ms apart.
  solved,
}

/// A puzzle in play (`PLAN-phase-3.md` §4.3).
///
/// Built either [start]ed from a generated puzzle or [resume]d from what a
/// previous run stored, and the two produce the same object: everything the
/// board draws comes from here, so a resumed puzzle is not a special case
/// anywhere above this class.
class SudokuSession extends ChangeNotifier {
  /// A fresh puzzle: the clues, nothing entered, the clock at zero.
  factory SudokuSession.start({
    required PuzzleId id,
    required PuzzleRecord record,
    MistakeFeedback mistakeFeedback = MistakeFeedback.immediate,
  }) {
    final clues = decodeGrid(id.spec, record.clues);
    return SudokuSession._(
      id: id,
      clues: clues,
      solution: decodeGrid(id.spec, record.solution),
      // A copy, not the clue list itself: the board is played on, and a session
      // whose givens moved with its entries would call every cell a given.
      digits: [...clues],
      notes: List<int>.filled(id.spec.cells, 0),
      mistakeFeedback: mistakeFeedback,
    );
  }

  /// The puzzle as [saved] left it.
  ///
  /// Throws a [FormatException] when [saved] does not describe a board of this
  /// puzzle: a wrong length, a character that is not a digit of this size, an
  /// undo entry naming a cell outside the grid, or a grid that contradicts a
  /// clue — the last of which catches a save paired with the wrong id, where
  /// every length still checks out. The caller's answer to all of them is the
  /// same and it is not an error message in front of a child (`AGENTS.md`):
  /// drop the entry and start the puzzle fresh.
  ///
  /// The redo stack is not restored, because it is not stored: `undoStack` is
  /// the schema's only history field (`PLAN.md` §5.2), and a redo stack after a
  /// restart is not something a child reaches for.
  factory SudokuSession.resume({
    required PuzzleId id,
    required PuzzleRecord record,
    required PuzzleInProgress saved,
    MistakeFeedback mistakeFeedback = MistakeFeedback.immediate,
  }) {
    final spec = id.spec;
    final clues = decodeGrid(spec, record.clues);
    final digits = decodeGrid(spec, saved.grid);
    for (var index = 0; index < spec.cells; index++) {
      if (clues[index] != 0 && digits[index] != clues[index]) {
        throw FormatException(
          'the saved grid disagrees with the clue at cell $index',
          saved.grid,
          index,
        );
      }
    }

    return SudokuSession._(
      id: id,
      clues: clues,
      solution: decodeGrid(spec, record.solution),
      digits: digits,
      notes: decodeNotes(spec, saved.notes),
      undoStack: [
        for (final move in saved.undoStack) SudokuMove.decode(spec, move),
      ],
      elapsed: Duration(milliseconds: saved.elapsedMs),
      hints: saved.hints,
      mistakeFeedback: mistakeFeedback,
    );
  }

  SudokuSession._({
    required this.id,
    required this._clues,
    required this._solution,
    required this._digits,
    required this._notes,
    this.mistakeFeedback = MistakeFeedback.immediate,
    this.elapsed = Duration.zero,
    this._hints = 0,
    List<SudokuMove> undoStack = const [],
  }) : _undo = _capped(undoStack) {
    // Wrong digits already on the board are counted as mistakes made, because
    // they are the only evidence a save carries: `PuzzleInProgress` has no
    // mistake field, and starting a resumed puzzle at zero would let a
    // force-quit launder a wrong digit into a clean star. A mistake that was
    // corrected before the quit is lost, which is the price of not widening the
    // schema for a counter (`PLAN-phase-3.md` §4.4).
    for (var index = 0; index < _digits.length; index++) {
      if (isWrong(index)) _mistakes++;
    }
  }

  /// Which puzzle this is. The board is a pure function of it, so this is what
  /// the save stores and what a resume is keyed by.
  final PuzzleId id;

  /// When a wrong digit is drawn as one (`PLAN-phase-3.md` §4.6).
  ///
  /// Read once, when the session is built, rather than watched: it is a field
  /// on the profile, and nothing reachable from a puzzle in play changes either
  /// the setting or the profile, so a board cannot outlive the answer it
  /// started with.
  final MistakeFeedback mistakeFeedback;

  /// Time on the clock.
  ///
  /// A plain field the screen writes, because the model has no clock to read: a
  /// session that called `DateTime.now` could not be tested without waiting.
  /// Writing it deliberately does **not** notify listeners — it changes once a
  /// second, and the widget that draws the clock is the one that set it, so
  /// notifying would repaint the whole board every second to move one digit.
  Duration elapsed;

  /// The grid's shape, for a widget that draws boxes from it.
  SudokuSpec get spec => id.spec;

  final List<int> _clues;
  final List<int> _solution;
  final List<int> _digits;
  final List<int> _notes;

  /// Cell states to restore, oldest first (`SudokuMove`).
  final List<SudokuMove> _undo;

  /// The states undone, newest last. Never stored; cleared by a new move.
  final List<SudokuMove> _redo = [];

  int? _selected;
  bool _pencilMode = false;
  int _mistakes = 0;
  int _hints;

  /// What the last mutation did, for [takeEvent].
  SudokuEvent? _event;

  /// The wrong cell a [hint] pointed at, or null when none has.
  ///
  /// Flagged whatever [mistakeFeedback] says (see [isFlagged]): a child who
  /// asks for help and gets a cell selected in silence has been told nothing.
  /// Not stored — the schema has no field for it, and a hint given before a
  /// force-quit is not something to bring back.
  int? _pointedAt;

  /// What the last mutation did, for the screen above to turn into a sound
  /// (`PLAN-phase-5.md` §4.3). Cleared by the read: an event is played once.
  SudokuEvent? takeEvent() {
    final event = _event;
    _event = null;
    return event;
  }

  /// The digit in the cell at [index], or 0 when it is empty.
  int digitAt(int index) => _digits[index];

  /// Whether the cell at [index] came with the puzzle, and so cannot be
  /// changed.
  bool isGiven(int index) => _clues[index] != 0;

  /// The pencil marks on the cell at [index], as a bitmask where bit `d - 1`
  /// stands for digit `d`.
  int notesAt(int index) => _notes[index];

  /// Whether [digit] is on the board as many times as a solved puzzle holds
  /// it — once per row, so [SudokuSpec.digits] times.
  ///
  /// What the keypad greys a digit out for. A raw count of what is on the
  /// board, given or entered, right or wrong: this is the one place the board
  /// is not asked whether a digit is *correct*, because a child playing under
  /// [MistakeFeedback.atCompletion] has asked not to be told that, and a
  /// keypad that greyed out only correct digits would tell them anyway.
  bool isDigitComplete(int digit) {
    var count = 0;
    for (final placed in _digits) {
      if (placed == digit) count++;
    }
    return count >= spec.digits;
  }

  /// Whether the cell at [index] holds a digit that is not the puzzle's.
  ///
  /// Computed against the stored solution rather than against the cell's peers,
  /// so a digit that is wrong but not yet contradictory is caught. This is the
  /// fact; [isFlagged] is whether the board says so yet.
  bool isWrong(int index) =>
      _digits[index] != 0 && _digits[index] != _solution[index];

  /// Whether the cell at [index] is *drawn* as a mistake
  /// (`PLAN-phase-3.md` §4.6).
  ///
  /// Under [MistakeFeedback.immediate] that is every wrong digit, as soon as it
  /// is entered. Under [MistakeFeedback.atCompletion] nothing is flagged until
  /// the grid is full — at which point being told is the only way a child finds
  /// out why the puzzle has not finished — and until then only the cell a
  /// [hint] pointed at.
  bool isFlagged(int index) =>
      isWrong(index) &&
      (mistakeFeedback == MistakeFeedback.immediate ||
          isFull ||
          index == _pointedAt);

  /// The selected cell, or null when nothing is selected.
  int? get selected => _selected;

  /// Whether [enter] writes a pencil mark instead of a digit.
  bool get pencilMode => _pencilMode;

  set pencilMode(bool value) {
    if (_pencilMode == value) return;
    _pencilMode = value;
    notifyListeners();
  }

  /// Whether [undo] and [redo] have anything to do — what the keypad's two
  /// buttons are enabled by.
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Whether every cell holds the digit the solution puts there.
  bool get isSolved {
    for (var index = 0; index < _digits.length; index++) {
      if (_digits[index] != _solution[index]) return false;
    }
    return true;
  }

  /// Whether every cell holds a digit, right or wrong.
  ///
  /// The difference from [isSolved] is what [MistakeFeedback.atCompletion]
  /// turns on: a full grid that is not solved is exactly the moment a child who
  /// asked not to be interrupted needs to be told.
  bool get isFull {
    for (final digit in _digits) {
      if (digit == 0) return false;
    }
    return true;
  }

  /// How many wrong digits have been entered, including any that were already
  /// on the board when a saved puzzle was resumed (see the constructor).
  ///
  /// Never decremented: correcting a wrong digit fixes the grid, not the
  /// history, and this is what `SolvedPuzzle.mistakes` stores and what decides
  /// the clean star.
  int get mistakes => _mistakes;

  /// How many cells a [hint] has given away. Restored from the save and carried
  /// into the `SolvedPuzzle`, where any at all clears the clean star
  /// (`PLAN.md` §3.7).
  int get hints => _hints;

  /// How much of the child's own share of the board is filled in, from `0` to
  /// `1`.
  ///
  /// Counted over the cells the puzzle did not already answer — a given asks
  /// nothing of the child, so counting it would start every puzzle short of
  /// empty and never reach `1` at a board only the givens fill in one corner
  /// of. A cell counts as filled whether or not it agrees with the solution:
  /// this is progress through the grid, not correctness, which [isWrong]
  /// already answers elsewhere. `1` for a puzzle with no blanks at all, rather
  /// than a division by zero.
  double get progress {
    var blanks = 0;
    var filled = 0;
    for (var index = 0; index < _digits.length; index++) {
      if (isGiven(index)) continue;
      blanks++;
      if (_digits[index] != 0) filled++;
    }
    return blanks == 0 ? 1 : filled / blanks;
  }

  /// Selects the cell at [index], or nothing when it is null.
  ///
  /// A given is selectable: tapping one highlights its digit everywhere, which
  /// is how a child finds the last 7 (`PLAN-phase-3.md` §4.5). It is [enter]
  /// and [erase] that refuse to change it.
  void select(int? index) {
    if (index != null && (index < 0 || index >= _digits.length)) {
      throw RangeError.range(index, 0, _digits.length - 1, 'index');
    }
    if (_selected == index) return;
    _selected = index;
    notifyListeners();
  }

  /// Puts [digit] in the selected cell, or toggles it as a pencil mark when
  /// [pencilMode] is on.
  ///
  /// Does nothing when nothing is selected, when the selected cell is a given,
  /// when it already holds [digit], or when a pencil mark is asked for on a
  /// cell that holds a digit — a note under a digit is invisible, so writing
  /// one would spend an undo entry on nothing a child can see.
  void enter(int digit) {
    if (digit < 1 || digit > spec.digits) {
      throw RangeError.range(digit, 1, spec.digits, 'digit');
    }

    final index = _selected;
    if (index == null || isGiven(index)) return;

    if (_pencilMode) {
      if (_digits[index] != 0) return;
      _record(index);
      _notes[index] ^= 1 << (digit - 1);
      _emit(SudokuEvent.noted);
    } else {
      if (_digits[index] == digit) return;
      _record(index);
      _digits[index] = digit;
      // The marks were about which digit went here, and one has.
      _notes[index] = 0;
      final correct = digit == _solution[index];
      if (!correct) _mistakes++;
      _emit(
        mistakeFeedback == MistakeFeedback.immediate
            ? (correct ? SudokuEvent.placedCorrect : SudokuEvent.placedWrong)
            : SudokuEvent.placed,
      );
    }
    notifyListeners();
  }

  /// Empties the selected cell, digit and pencil marks alike.
  ///
  /// Does nothing when nothing is selected, when the selected cell is a given,
  /// or when it is already empty.
  void erase() {
    final index = _selected;
    if (index == null || isGiven(index)) return;
    if (_digits[index] == 0 && _notes[index] == 0) return;

    _record(index);
    _digits[index] = 0;
    _notes[index] = 0;
    _emit(SudokuEvent.erased);
    notifyListeners();
  }

  /// Puts the last changed cell back the way it was.
  ///
  /// The mistake count does not come back down: it counts wrong digits ever
  /// entered, and undoing one does not unmake it.
  void undo() => _step(from: _undo, to: _redo);

  /// Puts back what [undo] took away.
  void redo() => _step(from: _redo, to: _undo);

  /// Helps, in the three steps of `PLAN-phase-3.md` §4.6.
  ///
  /// 1. **A wrong digit already on the board is pointed at** rather than a new
  ///    cell revealed. A child whose grid already contradicts itself needs the
  ///    contradiction shown, not another digit — and it does not count as a
  ///    hint, because it gives nothing away. It is also what keeps step 2 safe:
  ///    no `SudokuBoard` is ever built from a grid that cannot hold one (§4.3).
  /// 2. **Otherwise the technique solver decides a cell.** That is a cell a
  ///    child could have worked out, which is what makes it a hint rather than
  ///    an answer, and the step carries the technique's name for a later phase
  ///    to explain with.
  /// 3. **Otherwise the empty cell with the fewest candidates is revealed**
  ///    from the stored solution. This is the T4 board where technique has run
  ///    out (`PLAN.md` §3.4), and a hint button that did nothing there would be
  ///    a broken button on exactly the puzzle that needed it.
  ///
  /// The digit written is always the solution's, even when a technique chose
  /// the cell: the two agree — the puzzle has one completion, and the board the
  /// solver is given is a subset of it — and taking the solution's is what
  /// makes "a hint is never wrong" true by construction rather than by trusting
  /// the solver.
  ///
  /// A hint is an ordinary move: it goes on the undo stack, and undoing it
  /// leaves the count where it is, as a corrected mistake does.
  void hint() {
    if (isSolved) return;

    final wrong = _firstWrong();
    if (wrong != null) {
      _pointedAt = wrong;
      // Not through [select]: re-pointing at the cell already selected still
      // has to repaint it, and [select] returns early on a selection that has
      // not moved.
      _selected = wrong;
      _emit(SudokuEvent.hinted);
      notifyListeners();
      return;
    }

    // Safe because of the step above: every entered digit matches the solution,
    // so this grid is a subset of a legal one and `fromClues` cannot throw.
    final board = SudokuBoard.fromClues(spec, encodeGrid(spec, _digits));
    final index = nextPlacement(board)?.index ?? _fewestCandidates(board);
    if (index == null) return;

    _record(index);
    _digits[index] = _solution[index];
    // The marks were about which digit went here, and one has — the same
    // reasoning as [enter].
    _notes[index] = 0;
    _hints++;
    _selected = index;
    _emit(SudokuEvent.hinted);
    notifyListeners();
  }

  /// This session as the save file stores it.
  PuzzleInProgress toSaved() => PuzzleInProgress(
    grid: encodeGrid(spec, _digits),
    notes: encodeNotes(spec, _notes),
    elapsedMs: elapsed.inMilliseconds,
    undoStack: [for (final move in _undo) move.encode()],
    hints: _hints,
  );

  /// [moves] with only the newest [undoStackCap] kept.
  ///
  /// Applied when a session is built as well as when a move is recorded, so a
  /// file holding a longer stack — a hand edit, or a build whose cap was larger
  /// — is brought back inside the cap at once rather than one entry per move.
  static List<SudokuMove> _capped(List<SudokuMove> moves) =>
      moves.length <= undoStackCap
      ? [...moves]
      : moves.sublist(moves.length - undoStackCap);

  /// Remembers the state of the cell at [index] so a later [undo] can restore
  /// it, and drops the redo stack: history forks at a new move.
  void _record(int index) {
    _redo.clear();
    _undo.add(_stateOf(index));
    // Oldest first out. A cap that dropped the newest would make undo stop
    // working at the end a child is actually using.
    if (_undo.length > undoStackCap) _undo.removeAt(0);
  }

  void _step({required List<SudokuMove> from, required List<SudokuMove> to}) {
    if (from.isEmpty) return;

    final move = from.removeLast();
    to.add(_stateOf(move.index));
    _digits[move.index] = move.digit;
    _notes[move.index] = move.notes;
    // The cell that moved is selected, so a child watching the board sees which
    // one changed rather than hunting for it.
    _selected = move.index;
    _emit(SudokuEvent.restored);
    notifyListeners();
  }

  SudokuMove _stateOf(int index) =>
      SudokuMove(index: index, digit: _digits[index], notes: _notes[index]);

  /// Records [event] as what this mutation did — or [SudokuEvent.solved]
  /// instead, when the mutation just left every cell agreeing with the
  /// solution. Checked after the mutation rather than before, so the same
  /// digit that finishes the grid plays the trumpet instead of its own tick
  /// (`PLAN-phase-5.md` §4.3).
  void _emit(SudokuEvent event) {
    _event = isSolved ? SudokuEvent.solved : event;
  }

  /// The lowest-numbered cell holding a digit the solution disagrees with, or
  /// null when there is none. Lowest rather than nearest the selection, so the
  /// same board always produces the same hint.
  int? _firstWrong() {
    for (var index = 0; index < _digits.length; index++) {
      if (isWrong(index)) return index;
    }
    return null;
  }

  /// The empty cell of [board] that the fewest digits could legally go in, or
  /// null when it has no empty cell.
  ///
  /// The closest thing to a deduction left once technique has run out: it is
  /// the cell a search would branch on first, so it is the one whose answer
  /// unlocks the most. Ties go to the lowest index, which is what makes a hint
  /// a pure function of the board rather than of the order cells were visited
  /// in.
  int? _fewestCandidates(SudokuBoard board) {
    int? found;
    var fewest = spec.digits + 1;

    for (var index = 0; index < _digits.length; index++) {
      if (board.digitAt(index) != 0) continue;
      final candidates = _bitCount(board.candidateMask(index));
      if (candidates < fewest) {
        fewest = candidates;
        found = index;
      }
    }
    return found;
  }
}

/// How many digits [mask] holds.
///
/// The engine's own mask helpers are not exported — they are how a puzzle is
/// built rather than anything the app has a question for (`puzzle_engine.dart`)
/// — and this is the one count the app needs.
int _bitCount(int mask) {
  var count = 0;
  for (var bits = mask; bits != 0; bits >>= 1) {
    count += bits & 1;
  }
  return count;
}
