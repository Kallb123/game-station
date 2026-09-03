// The whole of Snake, as plain Dart (`PLAN-phase-7-snake.md` §3, §4.1).
//
// No Flame, no widgets, no clock, and — unlike `invaders_sim.dart`, which
// imports `shared/game_rng.dart` — no import from `shared/` at all beyond
// `PadInput`: PR 3's rule for `model/` is that `PadInput` is its only outside
// import, so [_SnakeRng] below is a copy of `GameRng`'s xorshift32, not a
// share of it. That mirrors `game_rng.dart`'s own reason for copying rather
// than importing the engine's `Rng` — crossing a boundary that should not be
// crossed costs a few duplicated lines, not a dependency.
//
// `step()` advances by exactly one fixed step and nothing else advances it;
// the accumulator that decides how many times to call it for a frame lives in
// `snake_game.dart` (PR 4), the only place a wall-clock delta exists at all —
// exactly the split `invaders_sim.dart` draws.
//
// Every position here is a grid [Cell] in the 14 x 16 field (`PLAN.md` §4.1);
// the renderer scales cells to pixels, the simulation never does.
//
// Collisions are cell equality, evaluated once per **move** (not once per
// fixed step — see [_advance]), in a fixed order: wall or wrap, then the
// snake's own body, then the target under the head (`PLAN-phase-7-snake.md`
// §4.1). The order is part of the behaviour, so it is stated here and
// asserted by `snake_sim_test.dart` rather than left to whichever check was
// written first.

import 'package:flutter/foundation.dart';

import '../../shared/pad_input.dart';
import 'counting.dart';
import 'snake_rules.dart';

/// The virtual field every [Cell] is measured in, in grid cells — the same
/// 224 x 256-unit field Invaders letterboxes into, at 16 units a cell
/// (`PLAN-phase-7-snake.md` §4.2).
const int columns = 14;
const int rows = 16;
const double cellSize = 16;
const double fieldWidth = columns * cellSize;
const double fieldHeight = rows * cellSize;

/// The most [SnakeEvent]s [SnakeSim.drainEvents] holds before the oldest are
/// dropped — a sim stepped by a test that never drains must not grow this
/// without bound, the same guard `invaders_sim.dart`'s `maxBufferedEvents`
/// is.
const int maxBufferedEvents = 64;

/// One square of the grid. Value equality, so a body list and a target's cell
/// can be compared with `==` and searched with `List.contains`.
@immutable
class Cell {
  const Cell(this.col, this.row);

  final int col;
  final int row;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'Cell($col, $row)';
}

/// Which way the snake is heading, or which way a turn asks it to head.
enum SnakeDirection { up, down, left, right }

/// One target on the field: a cell, the number it is worth eating (`0` in
/// classic mode, where every target is interchangeable), and how many fixed
/// steps it has left flashing after being crossed out of order
/// (`PLAN-phase-7-snake.md` §4.1's "sets that target flashing").
@immutable
class SnakeTarget {
  const SnakeTarget({
    required this.cell,
    required this.value,
    this.flashTicks = 0,
  });

  final Cell cell;
  final int value;
  final int flashTicks;
}

/// Everything that happened during a [SnakeSim.step] call that the layer
/// above turns into a sound and a buzz (`PLAN-phase-7-snake.md` §4.10).
enum SnakeEvent {
  /// The next target was eaten.
  ate,

  /// A target that was not next was crossed — scenery, not a mistake
  /// (`PLAN-phase-7-snake.md` §1).
  notYet,

  /// A life was lost, to a wall or to the snake's own body.
  crashed,

  /// The level's last target was eaten and the bonus was scored.
  levelCleared,
}

/// One run of Snake. Construct with the rules for the mode being played, the
/// counting mode fixed for the run, and a seed; call [step] once per fixed
/// tick.
class SnakeSim {
  SnakeSim({required this.rules, required this.counting, required int seed})
    : _rng = _SnakeRng(seed) {
    _lives = rules.lives;
    _body = _startBody();
    _resetLevel();
  }

  /// The tuning this run plays with — [SnakeRules.normal] or
  /// [SnakeRules.easy].
  final SnakeRules rules;

  /// What this run counts, fixed for its whole life (`PLAN-phase-7-snake.md`
  /// §3).
  final SnakeCounting counting;

  final _SnakeRng _rng;

  int _score = 0;
  int _lives = 0;
  int _level = 1;
  int _eaten = 0;
  int _eatenThisLevel = 0;
  int _longest = 0;
  int _growthPending = 0;
  int _moveTicks = 0;
  bool _isOver = false;
  bool _isRespawning = false;
  int _respawnTimer = 0;

  late List<Cell> _body;
  SnakeDirection _heading = SnakeDirection.right;
  final List<SnakeDirection> _turnQueue = [];
  PadInput _prevInput = PadInput.none;

  List<int> _sequence = const [];
  late List<SnakeTarget> _targets;

  /// Oldest first; drained by [drainEvents]. See [maxBufferedEvents].
  final List<SnakeEvent> _events = [];

  int get score => _score;
  int get lives => _lives;

  /// 1, 2, 3 … the HUD's "Level", `ArcadeResult.wave`.
  int get level => _level;

  /// Targets eaten this run, for `ArcadeGameProgress.totalKills`.
  int get eaten => _eaten;

  /// The longest the body has been at any point this run, for
  /// `ArcadeGameProgress.bestLength` — not the length at game over, which a
  /// crash can shrink nothing from but a bad final approach could still end
  /// below a peak reached earlier.
  int get longest => _longest;

  bool get isOver => _isOver;

  /// Head first.
  List<Cell> get body => List<Cell>.unmodifiable(_body);

  SnakeDirection get heading => _heading;

  /// One in classic mode, up to `rules.visibleTargets` in counting mode.
  List<SnakeTarget> get targets => List<SnakeTarget>.unmodifiable(_targets);

  /// The number to eat next; `0` in classic mode.
  int get nextValue =>
      counting == SnakeCounting.off ? 0 : _sequence[_eatenThisLevel];

  /// The short pause after a crash, before the snake reappears.
  bool get isRespawning => _isRespawning;

  /// Advances the run by exactly one fixed step. Nothing else advances it:
  /// the accumulator deciding how many times to call this for a frame lives
  /// in `snake_game.dart`, not here.
  void step(PadInput input) {
    if (_isOver) return;
    _tickFlashes();

    if (_isRespawning) {
      _prevInput = input;
      _respawnTimer -= 1;
      if (_respawnTimer <= 0) _finishRespawn();
      return;
    }

    // A turn is edge-detected against every fixed step, independent of the
    // move interval below — that is what lets a corner be rounded by two
    // presses inside one interval (`PLAN-phase-7-snake.md` §4.1) while a
    // button held for the whole interval still queues only once.
    _maybeEnqueueTurn(input);
    _prevInput = input;

    _moveTicks += 1;
    if (_moveTicks < rules.moveTicksAt(_level, _eatenThisLevel)) return;
    _moveTicks = 0;
    _advance();
  }

  /// Everything that happened since the last drain, oldest first. Capped at
  /// [maxBufferedEvents] with the oldest dropped, so a sim stepped without
  /// ever being drained cannot grow this without bound.
  List<SnakeEvent> drainEvents() {
    final events = List<SnakeEvent>.unmodifiable(_events);
    _events.clear();
    return events;
  }

  void _emit(SnakeEvent event) {
    _events.add(event);
    if (_events.length > maxBufferedEvents) _events.removeAt(0);
  }

  // --- Turning -------------------------------------------------------

  void _maybeEnqueueTurn(PadInput input) {
    final requested = _newlyHeldDirection(input);
    if (requested == null || _turnQueue.length >= 2) return;
    final effectiveHeading = _turnQueue.isEmpty ? _heading : _turnQueue.last;
    if (_isReversal(requested, effectiveHeading)) return;
    _turnQueue.add(requested);
  }

  SnakeDirection? _newlyHeldDirection(PadInput input) {
    if (input.up && !_prevInput.up) return SnakeDirection.up;
    if (input.down && !_prevInput.down) return SnakeDirection.down;
    if (input.left && !_prevInput.left) return SnakeDirection.left;
    if (input.right && !_prevInput.right) return SnakeDirection.right;
    return null;
  }

  bool _isReversal(SnakeDirection a, SnakeDirection b) =>
      (a == SnakeDirection.up && b == SnakeDirection.down) ||
      (a == SnakeDirection.down && b == SnakeDirection.up) ||
      (a == SnakeDirection.left && b == SnakeDirection.right) ||
      (a == SnakeDirection.right && b == SnakeDirection.left);

  // --- Movement --------------------------------------------------------

  /// Moves the snake one cell, in the collision order
  /// `PLAN-phase-7-snake.md` §4.1 states: wall or wrap, then the snake's own
  /// body, then the target under the head. Called once per move interval,
  /// never once per fixed step — which is what makes a decoy fire `notYet`
  /// once per entry rather than once per tick spent sitting on it.
  void _advance() {
    _heading = _turnQueue.isEmpty ? _heading : _turnQueue.removeAt(0);

    final stepped = _stepCell(_body.first, _heading);
    final head = _resolveEdge(stepped);
    if (head == null) {
      _crash();
      return;
    }
    if (_bodyBlocks(head)) {
      _crash();
      return;
    }

    final hitIndex = _targets.indexWhere((target) => target.cell == head);
    final ateNext = hitIndex != -1 && _targets[hitIndex].value == nextValue;

    _body = [head, ..._body];
    if (_growthPending > 0) {
      _growthPending -= 1;
    } else {
      _body.removeLast();
    }
    if (_body.length > _longest) _longest = _body.length;

    if (hitIndex == -1) return;
    if (!ateNext) {
      _flashTarget(hitIndex);
      return;
    }
    _eatNext();
  }

  Cell _stepCell(Cell from, SnakeDirection direction) => switch (direction) {
    SnakeDirection.up => Cell(from.col, from.row - 1),
    SnakeDirection.down => Cell(from.col, from.row + 1),
    SnakeDirection.left => Cell(from.col - 1, from.row),
    SnakeDirection.right => Cell(from.col + 1, from.row),
  };

  /// Wraps an out-of-bounds cell when [SnakeRules.wrapWalls] is true, or
  /// signals a crash (`null`) when it is false.
  Cell? _resolveEdge(Cell cell) {
    final inBounds =
        cell.col >= 0 && cell.col < columns && cell.row >= 0 && cell.row < rows;
    if (inBounds) return cell;
    if (!rules.wrapWalls) return null;
    return Cell(cell.col % columns, cell.row % rows);
  }

  /// Whether [head] lands on the snake's own body. The tail cell is excluded
  /// when the tail is about to move away this same move — no growth pending
  /// — because that cell will be empty by the time the head arrives.
  bool _bodyBlocks(Cell head) {
    final tailWillMove = _growthPending == 0;
    final segments = tailWillMove ? _body.sublist(0, _body.length - 1) : _body;
    return segments.contains(head);
  }

  void _crash() {
    _lives -= 1;
    _emit(SnakeEvent.crashed);
    if (_lives <= 0) {
      _isOver = true;
      return;
    }
    // Score, level, the counting position and the targets on the field all
    // survive: only the snake itself resets, and only once the pause ends
    // (`_finishRespawn`) — `PLAN-phase-7-snake.md` §4.1.
    _isRespawning = true;
    _respawnTimer = rules.respawnTicks;
  }

  void _finishRespawn() {
    _isRespawning = false;
    _heading = SnakeDirection.right;
    _turnQueue.clear();
    _moveTicks = 0;
    _body = _startBody();
  }

  List<Cell> _startBody() {
    final headCol = columns ~/ 2;
    final row = rows ~/ 2;
    return [for (var i = 0; i < rules.startLength; i++) Cell(headCol - i, row)];
  }

  // --- Targets -----------------------------------------------------------

  void _eatNext() {
    _score += rules.pointsPerTarget;
    _eaten += 1;
    _growthPending += rules.growPerTarget;
    _emit(SnakeEvent.ate);

    _eatenThisLevel += 1;
    if (_eatenThisLevel >= rules.targetsPerLevel) {
      _score += rules.levelBonus;
      _level += 1;
      _eatenThisLevel = 0;
      _emit(SnakeEvent.levelCleared);
      _resetLevel();
    } else {
      _spawnTargets();
    }
  }

  void _flashTarget(int index) {
    final target = _targets[index];
    _targets = List<SnakeTarget>.of(_targets)
      ..[index] = SnakeTarget(
        cell: target.cell,
        value: target.value,
        flashTicks: rules.flashTicks,
      );
    _emit(SnakeEvent.notYet);
  }

  void _tickFlashes() {
    if (_targets.every((target) => target.flashTicks == 0)) return;
    _targets = [
      for (final target in _targets)
        target.flashTicks == 0
            ? target
            : SnakeTarget(
                cell: target.cell,
                value: target.value,
                flashTicks: target.flashTicks - 1,
              ),
    ];
  }

  /// Rebuilds the counting sequence for [_level] (skipped in classic mode,
  /// which has none) and spawns a fresh set of targets for it. Called at
  /// construction and on every level clear.
  void _resetLevel() {
    if (counting != SnakeCounting.off) {
      _sequence = sequenceForLevel(counting, _level, rules.targetsPerLevel);
    }
    _spawnTargets();
  }

  /// Places the next target, plus decoys in counting mode, on freshly chosen
  /// free cells. Regenerated wholesale on every eat and every level clear,
  /// rather than only replacing the eaten target: simpler to reason about
  /// and to test than tracking which decoys survive an eat, at no cost to
  /// `PLAN-phase-7-snake.md` §4.3's design — only the next value is ever
  /// edible, so where a decoy happened to sit a moment before it was
  /// replaced is not part of the game.
  void _spawnTargets() {
    final free = _freeCells();
    if (counting == SnakeCounting.off) {
      _targets = [_placeTarget(free, value: 0)];
      return;
    }

    final next = _sequence[_eatenThisLevel];
    final pool = List<int>.of(_sequence.sublist(_eatenThisLevel + 1));
    final decoyCount = (rules.visibleTargets - 1).clamp(0, pool.length);
    final decoys = <int>[];
    for (var i = 0; i < decoyCount; i++) {
      final index = _rng.nextInt(pool.length);
      decoys.add(pool.removeAt(index));
    }

    _targets = [
      _placeTarget(free, value: next),
      for (final value in decoys) _placeTarget(free, value: value),
    ];
  }

  /// Picks a uniformly random cell from [free] — removing it, so a later
  /// call in the same batch cannot pick the same cell twice — and returns a
  /// target there worth [value].
  SnakeTarget _placeTarget(List<Cell> free, {required int value}) {
    final index = _rng.nextInt(free.length);
    final cell = free.removeAt(index);
    return SnakeTarget(cell: cell, value: value);
  }

  /// Every cell not occupied by the snake, in row-major order — a scan
  /// rather than rejection sampling, because a nearly full board makes
  /// rejection unbounded, and a list rather than a `Set` iterated for
  /// placement order, because `PLAN.md` §3.1's determinism rule is a habit
  /// this repository keeps everywhere (`PLAN-phase-7-snake.md` §4.3).
  List<Cell> _freeCells() {
    final occupied = _body.toSet();
    return [
      for (var row = 0; row < rows; row++)
        for (var col = 0; col < columns; col++)
          if (!occupied.contains(Cell(col, row))) Cell(col, row),
    ];
  }

  // --- Test seams ------------------------------------------------------

  /// Replaces the body directly, head first, and optionally the heading.
  ///
  /// `@visibleForTesting`: reaching a specific shape — two cells from a
  /// wall, or a body arranged so the next move turns into its own neck —
  /// through real play would make a collision test about navigating there
  /// rather than about the collision rule itself, the same reasoning
  /// `invaders_sim.dart`'s `debugSetAliveRows` gives.
  @visibleForTesting
  void debugSetBody(List<Cell> body, {SnakeDirection? heading}) {
    _body = List<Cell>.of(body);
    if (heading != null) _heading = heading;
  }

  /// Replaces the current targets directly.
  ///
  /// `@visibleForTesting`: growth, decoy and level-clear tests need a
  /// target of a specific value under a specific cell, which the real
  /// RNG-driven placement would make about the seed rather than about the
  /// rule under test.
  @visibleForTesting
  void debugSetTargets(List<SnakeTarget> targets) {
    _targets = List<SnakeTarget>.of(targets);
  }

  /// Sets the move-tick counter so the very next [step] performs a move,
  /// regardless of how many ticks [SnakeRules.moveTicksAt] currently asks
  /// for — so a test can force one move without stepping through its whole
  /// interval first.
  @visibleForTesting
  void debugForceMoveNext() {
    _moveTicks = rules.moveTicksAt(_level, _eatenThisLevel) - 1;
  }
}

/// The mask that keeps every intermediate a 32-bit word.
const int _mask32 = 0xFFFFFFFF;

/// 2^32, as a literal: `1 << 32` is 0 on the web, where shifts are 32-bit.
const int _uint32Size = 4294967296;

/// `(a * b) & _mask32`, computed in halves so it stays exact on the web —
/// copied from `shared/game_rng.dart`'s `_mul32` rather than imported, for
/// the reason this file's header gives.
int _mul32(int a, int b) {
  final low = (a & 0xFFFF) * b;
  final high = ((a >> 16) * b) & 0xFFFF;
  return (low + (high << 16)) & _mask32;
}

/// The seeded source behind target and decoy placement — a copy of
/// `shared/game_rng.dart`'s `GameRng`, not an import of it, so that
/// `model/`'s only outside import stays `PadInput`
/// (`PLAN-phase-7-snake.md` PR 3). See that file for why xorshift32 seeded by
/// one round of SplitMix32, rather than `dart:math`'s `Random`, is what keeps
/// a run replayable from its seed.
class _SnakeRng {
  _SnakeRng(int seed) : _state = _seedFrom(seed);

  int _state;

  static int _seedFrom(int seed) {
    var z = (seed + 0x9E3779B9) & _mask32;
    z = _mul32(z ^ (z >> 16), 0x21F0AAAD);
    z = _mul32(z ^ (z >> 15), 0x735A2D97);
    z = (z ^ (z >> 15)) & _mask32;
    return z == 0 ? 1 : z;
  }

  int nextUint32() {
    var x = _state;
    x = (x ^ (x << 13)) & _mask32;
    x ^= x >> 17;
    x = (x ^ (x << 5)) & _mask32;
    _state = x;
    return x;
  }

  /// A uniform value in `0..bound-1`, where `bound` is in `1..2^32`.
  int nextInt(int bound) {
    if (bound < 1 || bound > _uint32Size) {
      throw RangeError.range(bound, 1, _uint32Size, 'bound');
    }
    if (bound == 1) return 0;
    final limit = _uint32Size - (_uint32Size % bound);
    while (true) {
      final draw = nextUint32();
      if (draw < limit) return draw % bound;
    }
  }
}
