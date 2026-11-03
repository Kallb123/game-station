// One Tracks puzzle being played: the connections laid so far, the "no track
// here" marks, and enough history to walk back out of it.
//
// It is a [ChangeNotifier] for the reasons `SudokuSession` is (`PLAN-phase-3.md`
// §3): a model that depends on a state library cannot be tested without it, and
// nothing here imports Flutter beyond `foundation.dart`, so the tests are plain
// `test()` calls and the whole file runs in milliseconds. It imports nothing
// from `ui/` or `skins/` either, which is the mechanism behind
// `PLAN-phase-9-tracks.md` §3's decision that a skin changes pixels and never
// rules; `import_boundary_test.dart` scans for it.
//
// **The board is one mask per cell, and a connection is a bit on each end.** A
// cell's own mask says everything about it, and every mutation here keeps the two
// halves of a connection together, which is why nothing outside this file writes
// a bit. There is one exception, and it is deliberate: a fixed piece starts with
// its full mask, so a bit that points at a free neighbour is an *open end*, left
// unanswered until the child lays that neighbour's half. Seeding the answer would
// complete cells the child never touched — a free cell between two fixed pieces
// is finished by their reciprocals alone — and opened 13% of 5x5 Easy puzzles
// already solved. So a bit on a fixed cell may be unanswered; a bit on a free
// cell never may, and the save codec therefore cannot check reciprocity: only
// the puzzle says which cells are fixed (`PLAN-phase-9-tracks.md` §4.11).
//
// **Rules, not the solution, decide when a board is solved** (§4.7): the stored
// solution is used for feedback (what is wrong, what a hint lays) and nowhere
// else, so a corrupt cached solution cannot refuse a correct board.

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/save_data.dart';
import 'tracks_session_codec.dart';

/// What a mutation did, for the screen above to turn into a sound
/// (`PLAN-phase-9-tracks.md` §4.10). [TracksSession.takeEvent] clears the slot
/// it comes from, so an event plays once and only once.
enum TracksEvent {
  /// A connection was laid.
  laid,

  /// A connection was laid that the solution does not hold, on a profile that
  /// flags mistakes immediately.
  laidWrong,

  /// A stroke ran into a cell that already has two connections, or slid off the
  /// edge of the grid. A soft bump, never an error (§4.7).
  refused,

  /// A connection was lifted: by retracing, or by a tap on a track cell.
  lifted,

  /// A "no track here" mark was toggled, on or off.
  marked,

  /// A hint fired. Pointing at a mistake already on the board and laying a
  /// piece are the same event, because both tell a child the same thing: look
  /// here.
  hinted,

  /// An undo or a redo changed the board back.
  restored,

  /// The move that completed the track. Replaces whichever of the above the
  /// move would otherwise have been, so a finishing stroke is one sound, not
  /// two 20 ms apart.
  solved,
}

/// A puzzle in play (`PLAN-phase-9-tracks.md` §4.7).
///
/// Built either [start]ed from a generated puzzle or [resume]d from what a
/// previous run stored; the two produce the same object, so a resumed puzzle is
/// not a special case anywhere above this class.
class TracksSession extends ChangeNotifier {
  /// A fresh puzzle: the fixed pieces and nothing else, the clock at zero.
  ///
  /// A fixed piece's bits that point at free cells are open ends, not answered
  /// by the neighbour (see the file header), so the board opens unsolved.
  ///
  /// Throws an [ArgumentError] when [solution] is not one mask per cell or
  /// [clues] belong to a different grid than [id].
  factory TracksSession.start({
    required TracksPuzzleId id,
    required TracksClues clues,
    required List<int> solution,
    MistakeFeedback mistakeFeedback = MistakeFeedback.immediate,
  }) {
    _checkArguments(id, clues, solution);
    return TracksSession._(
      id: id,
      clues: clues,
      solution: solution,
      cells: [...clues.fixed],
      marks: List<bool>.filled(id.spec.cells, false),
      mistakeFeedback: mistakeFeedback,
    );
  }

  /// The puzzle as [saved] left it.
  ///
  /// Throws a [FormatException] when [saved] does not describe a board of this
  /// puzzle: it does not decode, a cell has more than two connections, a
  /// connection is not reciprocated or leaves the grid other than through a
  /// port, a fixed cell's mask is not the puzzle's, or a mark sits on a track
  /// cell. A connection the neighbour does not return is refused unless it is a
  /// fixed piece's open end, which is the one place the board is not symmetric
  /// (see the file header) and why the save codec leaves reciprocity to this
  /// check. The fixed-piece and mark checks catch a save paired with the wrong
  /// puzzle, where every length still checks out. The caller's answer to all of them is the same and it is
  /// not an error message in front of a child (`AGENTS.md`): drop the entry and
  /// start the puzzle fresh.
  ///
  /// **An undo stack that does not hold up is dropped on its own and the board
  /// kept** (`PLAN-phase-9-tracks.md` §4.11): losing the history is a smaller
  /// cost than losing a child's half-finished track. Each entry is checked by
  /// restoring it, newest first, and validating the board that results with the
  /// same function the saved board went through — an entry that decodes but
  /// would put an impossible board back is as bad as one that does not decode.
  ///
  /// The redo stack is not restored, because it is not stored.
  factory TracksSession.resume({
    required TracksPuzzleId id,
    required TracksClues clues,
    required List<int> solution,
    required TracksInProgress saved,
    MistakeFeedback mistakeFeedback = MistakeFeedback.immediate,
  }) {
    _checkArguments(id, clues, solution);
    final spec = id.spec;
    final cells = decodeTracksCells(spec, saved.cells);
    final marks = decodeTracksMarks(spec, saved.marks);

    final problem = _boardProblem(spec, clues, cells, marks);
    if (problem != null) throw FormatException(problem, saved.cells);

    return TracksSession._(
      id: id,
      clues: clues,
      solution: solution,
      cells: cells,
      marks: marks,
      undoStack: _validUndoStack(spec, clues, cells, marks, saved.undoStack),
      elapsed: Duration(milliseconds: saved.elapsedMs),
      hints: saved.hints,
      mistakeFeedback: mistakeFeedback,
    );
  }

  TracksSession._({
    required this.id,
    required this.clues,
    required List<int> solution,
    required this._cells,
    required this._marks,
    this.mistakeFeedback = MistakeFeedback.immediate,
    this.elapsed = Duration.zero,
    this._hints = 0,
    List<TracksMove> undoStack = const [],
  }) : _solution = List.unmodifiable(solution),
       _undo = _capped(undoStack) {
    _cellsView = UnmodifiableListView(_cells);
    // Wrong connections already on the board count as mistakes made, because
    // they are the only evidence a save carries: `TracksInProgress` has no
    // mistake field, and starting a resumed puzzle at zero would let a
    // force-quit launder a wrong connection into a clean star. A mistake that
    // was corrected before the quit is lost — the price of not widening the
    // schema for a counter, as for Sudoku (`PLAN-phase-3.md` §4.4). Counted per
    // connection, not per bit: a connection has a bit on both ends, so only
    // each cell's east and south bits are looked at, and port bits are always
    // in the solution.
    for (var cell = 0; cell < _cells.length; cell++) {
      for (final side in const [TrackSide.east, TrackSide.south]) {
        if (_cells[cell] & side != 0 && _solution[cell] & side == 0) {
          _mistakes++;
        }
      }
    }
  }

  /// Which puzzle this is. The board is a pure function of it, so this is what
  /// the save stores and what a resume is keyed by.
  final TracksPuzzleId id;

  /// The counts, ports and fixed pieces the puzzle was generated with.
  final TracksClues clues;

  /// When a wrong connection is drawn as one (`PLAN-phase-9-tracks.md` §4.7).
  ///
  /// Read once, when the session is built, as `SudokuSession` does: nothing
  /// reachable from a puzzle in play changes the profile, so a board cannot
  /// outlive the answer it started with.
  final MistakeFeedback mistakeFeedback;

  /// Time on the clock.
  ///
  /// A plain field the screen writes, because the model has no clock to read. It
  /// deliberately does **not** notify listeners: it changes once a second, and
  /// notifying would repaint the board every second to move a clock.
  Duration elapsed;

  /// The grid's shape.
  TracksSpec get spec => id.spec;

  final List<int> _solution;

  final List<int> _cells;
  late final List<int> _cellsView;
  final List<bool> _marks;

  /// States to restore, oldest first.
  final List<TracksMove> _undo;

  /// The states undone, newest last. Never stored; cleared by a new move.
  final List<TracksMove> _redo = [];

  int _mistakes = 0;
  int _hints;
  int? _pointedAt;
  TracksEvent? _event;

  /// The cells a move in progress has touched, as they were before it. One
  /// stroke, tap or hint fills this and then [_commit]s it as one undo entry.
  final Map<int, TracksCellState> _before = {};

  /// The open stroke's path, or null when no finger is down.
  List<_Step>? _path;

  /// What the current [strokeTo] call did so far, merged by priority.
  TracksEvent? _callEvent;
  bool _callChanged = false;

  /// What the last mutation did, for the screen above to turn into a sound.
  /// Cleared by the read: an event is played once.
  TracksEvent? takeEvent() {
    final event = _event;
    _event = null;
    return event;
  }

  /// The connection masks, row-major, port bits included: the start cell holds
  /// [TrackSide.west] when joined to the start port and the goal cell
  /// [TrackSide.south] when joined to the goal port. Never modified by a caller.
  List<int> get cells => _cellsView;

  /// The connection mask of the cell at [cell].
  int maskAt(int cell) => _cells[cell];

  /// Whether the cell at [cell] carries a "no track here" mark. A mark only ever
  /// sits on a cell with no connection.
  bool isMarked(int cell) => _marks[cell];

  /// Whether the cell at [cell] came with the puzzle as a fixed piece.
  bool isFixed(int cell) => clues.fixed[cell] != 0;

  /// The bits of the cell at [cell] that can never be lifted: the whole mask of
  /// a fixed piece, port bit included, and nothing on a free cell.
  ///
  /// A free cell's half of a join into a fixed piece is the child's to lay and
  /// to lift, so it is not here. The painter tells the piece's own bits, and an
  /// open end that nothing answers yet, from laid track
  /// (`PLAN-phase-9-tracks.md` §4.8) by asking the model which bits these are.
  int fixedSides(int cell) => clues.fixed[cell];

  /// Whether a stroke is open: a finger is down.
  bool get isStroking => _path != null;

  /// Whether [undo] and [redo] have anything to do.
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// How many wrong connections have been laid, counting any already on the
  /// board when a saved puzzle was resumed (see the constructor).
  ///
  /// Counted when a stroke ends, not as each connection is laid: a wrong
  /// connection laid and retraced within one stroke is a fast swipe's overshoot
  /// and costs nothing. Never decremented, because lifting a wrong connection
  /// fixes the board, not the history; this is what `SolvedPuzzle.mistakes`
  /// stores and what decides the clean star.
  int get mistakes => _mistakes;

  /// How many hints have laid a piece. Pointing at a mistake is free and not
  /// counted. Carried into the `SolvedPuzzle`, where any at all clears the
  /// clean star.
  int get hints => _hints;

  /// The cell a hint pointed at, or null.
  ///
  /// Flagged whatever [mistakeFeedback] says (see [flaggedSides]): a child who
  /// asks for help and is shown nothing has been told nothing. Not stored; a
  /// hint given before a force-quit is not something to bring back.
  int? get pointedAt => _pointedAt;

  /// How many cells of [row] hold a connection.
  int placedInRow(int row) {
    var count = 0;
    for (var column = 0; column < spec.side; column++) {
      if (_cells[spec.indexAt(row, column)] != 0) count++;
    }
    return count;
  }

  /// How many cells of [column] hold a connection.
  int placedInColumn(int column) {
    var count = 0;
    for (var row = 0; row < spec.side; row++) {
      if (_cells[spec.indexAt(row, column)] != 0) count++;
    }
    return count;
  }

  /// The bits of the cell at [cell] that the solution does not hold: the fact.
  /// [flaggedSides] is whether the board says so yet.
  int wrongSides(int cell) => _cells[cell] & ~_solution[cell] & _allSides;

  /// The wrong bits of the cell at [cell] that the board *draws* as wrong
  /// (`PLAN-phase-9-tracks.md` §4.7).
  ///
  /// Under [MistakeFeedback.immediate], all of them. Under
  /// [MistakeFeedback.atCompletion], none until the track is joined start to
  /// goal but the counts or a stray piece say it is not finished — the moment
  /// a child who asked not to be interrupted needs to be told why nothing
  /// happened — and until then only the cell a hint pointed at.
  int flaggedSides(int cell) {
    final wrong = wrongSides(cell);
    if (wrong == 0) return 0;
    if (mistakeFeedback == MistakeFeedback.immediate ||
        cell == _pointedAt ||
        (isJoined && !isSolved)) {
      return wrong;
    }
    return 0;
  }

  /// Whether the track runs unbroken from the start port to the goal port.
  bool get isJoined => _joinedLength() > 0;

  /// Whether the board satisfies the rules of `PLAN-phase-9-tracks.md` §4.3:
  /// one track from start to goal, no second fragment or loop beside it, and
  /// every row and column holding exactly the number of cells its clue gives.
  ///
  /// Never a comparison with the solution: uniqueness makes the two the same
  /// thing, and checking rules means a corrupt stored solution cannot refuse a
  /// correct board (§4.7).
  bool get isSolved {
    final length = _joinedLength();
    if (length == 0) return false;

    var placed = 0;
    for (final mask in _cells) {
      if (mask != 0) placed++;
    }
    // Every placed cell was visited by the walk, so there is no loop or second
    // fragment elsewhere.
    if (placed != length) return false;

    for (var line = 0; line < spec.side; line++) {
      if (placedInRow(line) != clues.rowCounts[line]) return false;
      if (placedInColumn(line) != clues.columnCounts[line]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------- strokes

  /// Finger down at ([row], [column]).
  ///
  /// The position may be a cell, the start port `(startRow, -1)`, the goal port
  /// `(side, goalColumn)`, or anywhere else: a stroke that begins off the board
  /// is allowed, because a finger that slides in from the margin is how a child
  /// reaches a port. Strokes are addressed by coordinates rather than a cell
  /// index because the ports sit outside the grid and a jump has to be walked
  /// (`PLAN-phase-9-tracks.md` §4.7).
  ///
  /// Ends an open stroke first.
  void beginStroke(int row, int column) {
    endStroke();
    _before.clear();
    _path = [_Step(row, column, laid: false)];
  }

  /// The finger is now at ([row], [column]).
  ///
  /// A position that is not next to the finger's last one is walked one cell at
  /// a time, so a fast swipe lays a path rather than nothing: along the dominant
  /// axis first, then the other, and on a tie (a perfect diagonal) first along
  /// the axis of the stroke's previous step, or across columns if it has not
  /// stepped yet. The axis order is fixed for the whole jump, which is what
  /// makes it an L rather than a staircase. Does nothing without an open stroke.
  void strokeTo(int row, int column) {
    final path = _path;
    if (path == null) return;

    final from = path.last;
    var deltaRow = row - from.row;
    var deltaColumn = column - from.column;
    if (deltaRow == 0 && deltaColumn == 0) return;

    final bool rowsFirst;
    if (deltaRow.abs() != deltaColumn.abs()) {
      rowsFirst = deltaRow.abs() > deltaColumn.abs();
    } else if (path.length >= 2) {
      rowsFirst = path.last.row != path[path.length - 2].row;
    } else {
      rowsFirst = false;
    }

    _callEvent = null;
    _callChanged = false;
    void walk({required bool rows}) {
      while (rows ? deltaRow != 0 : deltaColumn != 0) {
        final stepRow = rows ? deltaRow.sign : 0;
        final stepColumn = rows ? 0 : deltaColumn.sign;
        _step(path, path.last.row + stepRow, path.last.column + stepColumn);
        if (rows) {
          deltaRow -= stepRow;
        } else {
          deltaColumn -= stepColumn;
        }
      }
    }

    walk(rows: rowsFirst);
    walk(rows: !rowsFirst);

    var event = _callEvent;
    // Only a call that changed the board can have finished it; a refused bump
    // after the last connection is not a second finish.
    if (_callChanged && isSolved) event = TracksEvent.solved;
    if (event != null) _event = event;
    if (_callChanged || event != null) notifyListeners();
  }

  /// Finger up. Closes the stroke as one undo entry, if it changed anything, and
  /// counts the wrong connections it left on the board.
  ///
  /// A stroke that changed nothing, including one retraced in full, pushes
  /// nothing and leaves the redo stack alone. Does nothing without an open
  /// stroke.
  void endStroke() {
    final path = _path;
    if (path == null) return;
    _path = null;

    // The path holds exactly the connections this stroke laid and still has:
    // a retrace pops its step, so an overshoot that was walked back is not in
    // it, and nothing else can lift a connection mid-stroke because every other
    // operation ends the stroke first.
    for (var i = 1; i < path.length; i++) {
      if (path[i].laid && !_inSolution(path[i - 1], path[i])) _mistakes++;
    }
    if (_commit()) notifyListeners();
  }

  /// One step of the stroke, `path.last` to the adjacent ([row], [column])
  /// (`PLAN-phase-9-tracks.md` §4.7).
  void _step(List<_Step> path, int row, int column) {
    final from = path.last;

    // 1. Retrace: back onto the position before this one lifts what the step
    // just left laid. Any number of cells, because the path remembers them all.
    if (path.length >= 2 &&
        path[path.length - 2].row == row &&
        path[path.length - 2].column == column) {
      final popped = path.removeLast();
      if (popped.laid) {
        _lift(from, path.last);
        _callChanged = true;
        _merge(TracksEvent.lifted);
      }
      return;
    }

    final fromCell = _cellAt(from.row, from.column);
    final toCell = _cellAt(row, column);
    final to = _Step(row, column, laid: false);

    // 2. Off the board. The cursor follows the finger even when nothing is laid,
    // so the finger coming back in lays from where it re-enters. Only a finger
    // that was on the board makes a bump: one already in the margin has
    // nothing left to refuse.
    if (!_isValid(from.row, from.column) || !_isValid(row, column)) {
      path.add(to);
      if (_isValid(from.row, from.column)) _merge(TracksEvent.refused);
      return;
    }

    // 3. Already joined — every in-grid end holds its bit: a fixed piece's
    // closed side, an earlier stroke, a port bit already set. A fixed piece's
    // open end is not joined until the free cell answers it. A stroke runs along
    // existing track without disturbing it.
    if (_joined(from, to)) {
      path.add(to);
      return;
    }

    // 4. A cell with two connections takes no third, but only an end that still
    // lacks its bit is asked to take one: a free cell stroking into a fixed
    // piece's open end lays its own half and the piece, already holding that
    // bit, is not asked. Fixed cells always have two, so every other side of
    // one is refused. A port has no cell and no limit.
    if (_full(fromCell, from, to) || _full(toCell, to, from)) {
      path.add(to);
      _merge(TracksEvent.refused);
      return;
    }

    // 5. Lay.
    _lay(from, to);
    path.add(_Step(row, column, laid: true));
    _callChanged = true;
    _merge(
      mistakeFeedback == MistakeFeedback.immediate && !_inSolution(from, to)
          ? TracksEvent.laidWrong
          : TracksEvent.laid,
    );
  }

  /// Keeps the higher-priority of the call's event so far and [event]:
  /// `solved` > `laidWrong` > `refused` > `laid` > `lifted`.
  void _merge(TracksEvent event) {
    final current = _callEvent;
    if (current == null || _priority(event) > _priority(current)) {
      _callEvent = event;
    }
  }

  static int _priority(TracksEvent event) => switch (event) {
    TracksEvent.solved => 5,
    TracksEvent.laidWrong => 4,
    TracksEvent.refused => 3,
    TracksEvent.laid => 2,
    _ => 1,
  };

  // ------------------------------------------------------------------ taps

  /// Lifts every connection of the cell at [cell] that is not fixed, port bit
  /// included, and the matching half on each neighbour: one undo entry. Does
  /// nothing, and records nothing, when no connection can be lifted.
  void clearCell(int cell) {
    endStroke();
    final liftable = _cells[cell] & ~clues.fixed[cell];
    if (liftable == 0) return;

    _before.clear();
    for (final side in TrackSide.all) {
      if (liftable & side == 0) continue;
      _touch(cell);
      _cells[cell] &= ~side;
      final neighbour = _neighbour(cell, side);
      if (neighbour != null) {
        _touch(neighbour);
        _cells[neighbour] &=
            ~(TrackSide.opposite(side) & ~clues.fixed[neighbour]);
      }
    }
    _commit();
    _event = TracksEvent.lifted;
    notifyListeners();
  }

  /// Toggles the "no track here" mark on the cell at [cell]: one undo entry.
  /// Does nothing on a cell that holds a connection, fixed cells included, since
  /// a mark says the cell is empty.
  void toggleMark(int cell) {
    endStroke();
    if (_cells[cell] != 0) return;

    _before.clear();
    _touch(cell);
    _marks[cell] = !_marks[cell];
    _commit();
    _event = TracksEvent.marked;
    notifyListeners();
  }

  // ------------------------------------------------------- undo, redo, hint

  /// Puts back what the last move changed. The mistake count does not come back
  /// down: it counts wrong connections ever laid, and undoing one does not
  /// unmake it.
  void undo() => _restoreFrom(_undo, _redo);

  /// Puts back what [undo] took away.
  void redo() => _restoreFrom(_redo, _undo);

  /// Helps, as `PLAN-phase-9-tracks.md` §4.13 describes.
  ///
  /// 1. **A wrong connection already on the board is pointed at**, lowest cell
  ///    first so the same board gives the same hint. It is free and records
  ///    nothing, because it gives nothing away. It is also what keeps step 2
  ///    safe: with no wrong bit on the board, laying a solution piece cannot
  ///    push a neighbour past two connections.
  /// 2. **Otherwise the deduction solver picks the cell**, so a child could have
  ///    worked it out.
  /// 3. **Otherwise the lowest cell that differs from the solution**, so a
  ///    hint button never does nothing on the board that needed it most.
  ///
  /// The piece laid is the solution's even when the solver chose the cell, which
  /// is what makes "a hint is never wrong" true by construction. It is an
  /// ordinary laid piece — liftable and undoable — rather than a fixed one:
  /// `TracksInProgress` has no field to remember which cells were hinted, so a
  /// fixed hint would turn back into a loose piece on the next launch, which
  /// is worse than never being fixed (a deviation from §4.13's "drawn as
  /// fixed").
  void hint() {
    endStroke();
    if (isSolved) return;

    for (var cell = 0; cell < _cells.length; cell++) {
      if (wrongSides(cell) != 0) {
        _pointedAt = cell;
        _event = TracksEvent.hinted;
        notifyListeners();
        return;
      }
    }

    final step = nextTracksStep(clues, _cells);
    int? target;
    if (step != null && _cells[step.cell] != _solution[step.cell]) {
      target = step.cell;
    } else {
      for (var cell = 0; cell < _cells.length; cell++) {
        if (_solution[cell] != 0 && _cells[cell] != _solution[cell]) {
          target = cell;
          break;
        }
      }
    }
    if (target == null) return;

    _before.clear();
    _touch(target);
    _cells[target] = _solution[target];
    _marks[target] = false;
    for (final side in TrackSide.all) {
      if (_solution[target] & side == 0) continue;
      final neighbour = _neighbour(target, side);
      if (neighbour == null) continue;
      _touch(neighbour);
      _cells[neighbour] |= TrackSide.opposite(side);
      _marks[neighbour] = false;
    }
    _commit();
    _hints++;
    _event = isSolved ? TracksEvent.solved : TracksEvent.hinted;
    notifyListeners();
  }

  void _restoreFrom(List<TracksMove> from, List<TracksMove> to) {
    endStroke();
    if (from.isEmpty) return;

    final move = from.removeLast();
    to.add(
      TracksMove([
        for (final state in move.cells)
          TracksCellState(
            index: state.index,
            mask: _cells[state.index],
            marked: _marks[state.index],
          ),
      ]),
    );
    for (final state in move.cells) {
      _cells[state.index] = state.mask;
      _marks[state.index] = state.marked;
    }
    // A redo can put the finishing move back, and the screen starts the
    // journey on `solved` whichever way the board got there.
    _event = isSolved ? TracksEvent.solved : TracksEvent.restored;
    notifyListeners();
  }

  // ----------------------------------------------------------------- saving

  /// This session as the save file stores it.
  TracksInProgress toSaved() => TracksInProgress(
    cells: encodeTracksCells(spec, _cells),
    marks: encodeTracksMarks(spec, _marks),
    elapsedMs: elapsed.inMilliseconds,
    undoStack: [for (final move in _undo) move.encode()],
    hints: _hints,
  );

  // ---------------------------------------------------------------- helpers

  /// [moves] with only the newest [tracksUndoStackCap] kept.
  ///
  /// Applied when a session is built as well as when a move is recorded, so a
  /// file holding a longer stack is brought back inside the cap at once.
  static List<TracksMove> _capped(List<TracksMove> moves) =>
      moves.length <= tracksUndoStackCap
      ? [...moves]
      : moves.sublist(moves.length - tracksUndoStackCap);

  /// Remembers the state of the cell at [cell], once per move, so [_commit] can
  /// say what it was before.
  void _touch(int cell) {
    _before.putIfAbsent(
      cell,
      () => TracksCellState(
        index: cell,
        mask: _cells[cell],
        marked: _marks[cell],
      ),
    );
  }

  /// Pushes the cells [_touch]ed since the move began as one undo entry, if any
  /// of them now differs from before, and forks history: a new move drops the
  /// redo stack. Returns whether it pushed.
  bool _commit() {
    final changed = <TracksCellState>[
      for (final state in _before.values)
        if (_cells[state.index] != state.mask ||
            _marks[state.index] != state.marked)
          state,
    ]..sort((a, b) => a.index.compareTo(b.index));
    _before.clear();
    if (changed.isEmpty) return false;

    _redo.clear();
    _undo.add(TracksMove(changed));
    // Oldest first out. A cap that dropped the newest would make undo stop
    // working at the end a child is actually using.
    if (_undo.length > tracksUndoStackCap) _undo.removeAt(0);
    return true;
  }

  /// Whether ([row], [column]) is a cell or one of the two ports.
  bool _isValid(int row, int column) =>
      _cellAt(row, column) != null ||
      (row == clues.startRow && column == -1) ||
      (row == spec.side && column == clues.goalColumn);

  int? _cellAt(int row, int column) =>
      row >= 0 && row < spec.side && column >= 0 && column < spec.side
      ? spec.indexAt(row, column)
      : null;

  int? _neighbour(int cell, int side) => _neighbourOf(spec, cell, side);

  static int? _neighbourOf(TracksSpec spec, int cell, int side) {
    final row =
        spec.rowOf(cell) +
        (side == TrackSide.south ? 1 : 0) -
        (side == TrackSide.north ? 1 : 0);
    final column =
        spec.columnOf(cell) +
        (side == TrackSide.east ? 1 : 0) -
        (side == TrackSide.west ? 1 : 0);
    if (row < 0 || row >= spec.side || column < 0 || column >= spec.side) {
      return null;
    }
    return spec.indexAt(row, column);
  }

  /// The side of [a] that faces the adjacent [b].
  static int _facing(_Step a, _Step b) {
    if (b.row < a.row) return TrackSide.north;
    if (b.row > a.row) return TrackSide.south;
    return b.column > a.column ? TrackSide.east : TrackSide.west;
  }

  /// Whether the adjacent positions [a] and [b] are joined: every in-grid end
  /// holds its bit. Both are asked because a fixed piece's open end holds its
  /// bit without the free cell beside it answering; a port step has one end.
  bool _joined(_Step a, _Step b) {
    for (final (end, other) in [(a, b), (b, a)]) {
      final cell = _cellAt(end.row, end.column);
      if (cell != null && _cells[cell] & _facing(end, other) == 0) return false;
    }
    return true;
  }

  /// Whether [cell], one end of the step from [end] to [other], must refuse the
  /// connection: it lacks the bit and already has two.
  bool _full(int? cell, _Step end, _Step other) =>
      cell != null &&
      _cells[cell] & _facing(end, other) == 0 &&
      _bitCount(_cells[cell]) >= 2;

  bool _inSolution(_Step a, _Step b) {
    final cell = _cellAt(a.row, a.column);
    if (cell != null) return _solution[cell] & _facing(a, b) != 0;
    final other = _cellAt(b.row, b.column)!;
    return _solution[other] & _facing(b, a) != 0;
  }

  /// Sets the bit on each in-grid end of the connection that lacks it, clearing
  /// marks: a mark said "no track here" and there now is. A fixed piece's open
  /// end already holds its bit, so only the free cell's half is laid.
  void _lay(_Step a, _Step b) {
    for (final (end, other) in [(a, b), (b, a)]) {
      final cell = _cellAt(end.row, end.column);
      if (cell == null) continue;
      _touch(cell);
      _cells[cell] |= _facing(end, other);
      _marks[cell] = false;
    }
  }

  /// Clears the bit on each in-grid end of the connection, except a fixed
  /// piece's own, which is not the stroke's to lift. Only a retrace lifts this
  /// way, so a cell that is back to how the stroke found it gets its mark back
  /// too: dragging across a marked cell and straight back is no move.
  void _lift(_Step a, _Step b) {
    for (final (end, other) in [(a, b), (b, a)]) {
      final cell = _cellAt(end.row, end.column);
      if (cell == null) continue;
      _touch(cell);
      _cells[cell] &= ~(_facing(end, other) & ~clues.fixed[cell]);
      final before = _before[cell]!;
      if (_cells[cell] == before.mask) _marks[cell] = before.marked;
    }
  }

  /// How many cells the track visits from the start port to the goal port, or 0
  /// when it does not run unbroken between them.
  ///
  /// Each cell on the way must hold exactly two bits, one of which is the side
  /// the walk came in by, and the cell it leaves into must hold the reciprocal
  /// bit. The step budget is the cell count, so a loop that never reaches the
  /// goal ends the walk instead of spinning.
  int _joinedLength() {
    var cell = clues.startCell;
    if (_cells[cell] & TrackSide.west == 0) return 0;

    var cameIn = TrackSide.west;
    for (var visited = 1; visited <= _cells.length; visited++) {
      final mask = _cells[cell];
      if (_bitCount(mask) != 2) return 0;
      final out = mask & ~cameIn;
      if (cell == clues.goalCell && out == TrackSide.south) return visited;

      final next = _neighbour(cell, out);
      if (next == null) return 0;
      cameIn = TrackSide.opposite(out);
      if (_cells[next] & cameIn == 0) return 0;
      cell = next;
    }
    return 0;
  }

  static void _checkArguments(
    TracksPuzzleId id,
    TracksClues clues,
    List<int> solution,
  ) {
    if (clues.spec != id.spec) {
      throw ArgumentError.value(
        clues.spec,
        'clues',
        'are for a different grid than ${id.spec.label}',
      );
    }
    if (solution.length != id.spec.cells) {
      throw ArgumentError.value(
        solution.length,
        'solution',
        'expected one mask per cell of ${id.spec.label} (${id.spec.cells})',
      );
    }
  }

  /// Why [cells] and [marks] are not a board of this puzzle, or null when they
  /// are. One function for the saved board and for every board the undo replay
  /// reaches, so the two can never disagree about what a valid board is.
  ///
  /// The board invariant: every cell holds at most two bits; every fixed cell
  /// holds exactly [TracksClues.fixed]; no bit leaves the grid but the start
  /// cell's west and the goal cell's south; and every interior bit is answered
  /// by its neighbour, except a bit on a fixed cell pointing at a free one, which
  /// is an open end (see the file header). A free cell's bit is never excused,
  /// which is what makes a free cell pointing at a fixed cell's closed side an
  /// invalid board rather than a half-laid one.
  static String? _boardProblem(
    TracksSpec spec,
    TracksClues clues,
    List<int> cells,
    List<bool> marks,
  ) {
    final last = spec.side - 1;
    for (var cell = 0; cell < spec.cells; cell++) {
      final mask = cells[cell];
      final row = spec.rowOf(cell);
      final column = spec.columnOf(cell);
      final fixed = clues.fixed[cell] != 0;

      if (_bitCount(mask) > 2) return 'cell $cell has more than two bits';
      if (fixed && mask != clues.fixed[cell]) {
        return 'cell $cell is not its fixed piece';
      }
      if (marks[cell] && mask != 0) return 'cell $cell is marked and laid';

      // A bit leaving the grid is legal only through a port.
      if (mask & TrackSide.north != 0 && row == 0) {
        return 'cell $cell points off the north edge';
      }
      if (mask & TrackSide.east != 0 && column == last) {
        return 'cell $cell points off the east edge';
      }
      if (mask & TrackSide.west != 0 &&
          column == 0 &&
          cell != clues.startCell) {
        return 'cell $cell points off the west edge away from the start port';
      }
      if (mask & TrackSide.south != 0 &&
          row == last &&
          cell != clues.goalCell) {
        return 'cell $cell points off the south edge away from the goal port';
      }

      for (final side in TrackSide.all) {
        if (mask & side == 0) continue;
        final other = _neighbourOf(spec, cell, side);
        if (other == null) continue;
        if (cells[other] & TrackSide.opposite(side) != 0) continue;
        // Unanswered: only a fixed piece's open end onto a free cell.
        if (fixed && clues.fixed[other] == 0) continue;
        return 'cell $cell connects to a cell that does not connect back';
      }
    }
    return null;
  }

  /// The stack in [encoded], or empty when any entry fails to decode or
  /// restoring it newest-first would put an invalid board back.
  static List<TracksMove> _validUndoStack(
    TracksSpec spec,
    TracksClues clues,
    List<int> savedCells,
    List<bool> savedMarks,
    List<String> encoded,
  ) {
    try {
      final moves = [for (final text in encoded) TracksMove.decode(spec, text)];
      final cells = [...savedCells];
      final marks = [...savedMarks];
      for (final move in moves.reversed) {
        for (final state in move.cells) {
          cells[state.index] = state.mask;
          marks[state.index] = state.marked;
        }
        if (_boardProblem(spec, clues, cells, marks) != null) {
          return const [];
        }
      }
      return moves;
    } on FormatException {
      return const [];
    }
  }
}

/// One position on a stroke's path, and whether arriving at it laid a
/// connection (so that retracing it knows to lift one).
class _Step {
  _Step(this.row, this.column, {required this.laid});

  final int row;
  final int column;
  final bool laid;
}

const int _allSides = 15;

int _bitCount(int mask) {
  var count = 0;
  for (var bits = mask; bits != 0; bits >>= 1) {
    count += bits & 1;
  }
  return count;
}
