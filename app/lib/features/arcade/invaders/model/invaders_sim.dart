// The whole of Invaders, as plain Dart (`PLAN-phase-4.md` §3, §4.1).
//
// No Flame, no widgets, no clock: `step()` advances by exactly [fixedStep]
// and nothing else advances it, so a test can call it a thousand times with
// no widget tree and no ticker. `invaders_game.dart` (PR 4) is the only place
// a wall-clock delta exists at all — it owns the accumulator that decides how
// many times to call [step] for a given frame, which is what makes the same
// run play identically at 60 Hz and 144 Hz (`invaders_sim_equivalence_test.dart`).
//
// Every position here is in the virtual field's own units — [fieldWidth] by
// [fieldHeight], the original cabinet's resolution — so a phone and a tablet
// run the same game; the renderer scales the field, not the simulation.
//
// Collision is axis-aligned rectangle overlap, evaluated once per fixed step
// in a fixed order: shots against aliens and the UFO, shots against bunkers,
// shots against the player, the block against the player's row. The order is
// part of the behaviour (`PLAN.md` §4.1), so `_resolveCollisions` states it
// rather than leaving it to whichever check was written first.
//
// Nine of the methods below also append an [InvadersEvent] beside the
// mutation they already make, for `invaders_game.dart` (PR 4) to turn into a
// sound after draining them with [InvadersSim.drainEvents]
// (`PLAN-phase-5.md` §3.3, §4.4). Nothing here reads its own events back, so
// the sim stays exactly as testable — and as clock-free, RNG-free and
// Flutter-free — as it was before this phase.

import 'package:flutter/foundation.dart';

import '../../shared/game_rng.dart';
import '../../shared/pad_input.dart';
import 'invaders_rules.dart';

/// The virtual field every position in the simulation is measured in.
const double fieldWidth = 224;
const double fieldHeight = 256;

/// Columns in the alien block. Only the row count varies between
/// [InvadersRules.normal] and [InvadersRules.easy]; the block is always this
/// wide.
const int alienColumns = 11;

/// An alien's own drawn size, matching `sprites.dart`'s `alienFront` et al.
const double alienWidth = 16;
const double alienHeight = 8;

/// The centre-to-centre spacing between two aliens, one column or one row
/// apart. Wider than the sprite itself, which is what leaves a visible gap.
const double alienColumnPitch = 16;
const double alienRowPitch = 16;

const double playerWidth = 16;
const double playerHeight = 8;
const double playerY = fieldHeight - 24;

const double shotWidth = 2;
const double shotHeight = 6;

const double ufoWidth = 16;
const double ufoHeight = 8;
const double ufoY = 16;

/// One block of a bunker's grid, in field units.
const double bunkerBlockSize = 2;
const int bunkerColumns = 22;
const int bunkerRows = 16;
const double bunkerY = fieldHeight - 96;
const int bunkerCount = 4;

const double _alienStepDistance = 4;
const double _playerSpeed = 60;
const double _playerFireCooldown = 0.35;
const double _playerRespawnDelay = 1.5;
const double _playerShotSpeed = 200;
const double _alienShotSpeed = 90;
const int _erosionRadius = 3;
const double _ufoSpeed = 40;
const double _ufoInterval = 25;
const double _ufoJitter = 5;
const List<int> _ufoScores = [50, 100, 150, 200, 250, 300];
const int _bonusLifeThreshold = 10000;

/// Tolerance for a "has this timer run out" check. Forty-two subtractions of
/// [InvadersSim.fixedStep] (itself not exact in binary floating point) from
/// a cooldown like 0.35 s do not necessarily land on exactly zero, so every
/// timer expiry in this file compares against this instead of a bare zero.
const double _timerEpsilon = 1e-9;

/// Everything that happened during a [InvadersSim.step] call that the layer
/// above turns into a sound (`PLAN-phase-5.md` §4.4). Named after what the
/// simulation itself calls things — `AlienBlock`, `Ufo` — not after the play
/// field, so an event name greps to the method that emits it rather than to
/// nothing.
enum InvadersEvent {
  /// The player fired.
  playerShot,

  /// The player was hit — the last life or not.
  playerKilled,

  /// An alien fired.
  alienShot,

  /// An alien was destroyed.
  alienKilled,

  /// The alien block stepped sideways or down.
  alienStep,

  /// The UFO appeared.
  ufoAppeared,

  /// The UFO crossed the field without being hit.
  ufoLeft,

  /// The UFO was destroyed.
  ufoKilled,

  /// The last alien of a wave died and the next wave began.
  waveCleared,

  /// The 10,000-point bonus life was awarded.
  extraLife,
}

/// The most [InvadersEvent]s [InvadersSim.drainEvents] holds before the
/// oldest are dropped — a sim stepped by a test that never drains, or a frame
/// that drops a backlog of steps at once (`maxStepsPerFrame` in
/// `invaders_game.dart`), must not grow this without bound.
const int maxBufferedEvents = 64;

/// The player: position, whether it is currently on screen, and the two
/// timers that gate firing again and reappearing after a hit.
@immutable
class Player {
  const Player({
    required this.x,
    required this.alive,
    required this.respawnTimer,
    required this.fireCooldown,
  });

  final double x;
  final bool alive;
  final double respawnTimer;
  final double fireCooldown;

  static const double y = playerY;
  static const double width = playerWidth;
  static const double height = playerHeight;
}

/// One shot in flight, moving straight up if [fromPlayer] or straight down
/// otherwise — Invaders aims by choosing a column, not a bearing.
@immutable
class Shot {
  const Shot({required this.x, required this.y, required this.fromPlayer});

  final double x;
  final double y;
  final bool fromPlayer;

  static const double width = shotWidth;
  static const double height = shotHeight;
}

/// The alien block: its top-left corner, which way it is marching, the timer
/// until its next sideways step, and which of its cells are still alive.
///
/// [aliveRows] has one entry per row, each a bitmask of [alienColumns] bits —
/// one int per row rather than one flat bitmask over every cell, because a
/// flat mask needs up to 55 bits for [InvadersRules.normal] and this app's
/// own convention (`game_rng.dart`) keeps bitwise arithmetic inside 32 bits:
/// shifts and masks are 32-bit-only once compiled to JavaScript, which is
/// exactly the "a web target added later" risk `PLAN.md` §8 names. 11 bits a
/// row never comes close.
@immutable
class AlienBlock {
  const AlienBlock({
    required this.originX,
    required this.originY,
    required this.rows,
    required this.direction,
    required this.stepTimer,
    required this.aliveRows,
  });

  final double originX;
  final double originY;
  final int rows;

  /// +1 marching right, -1 marching left.
  final int direction;

  /// Seconds until the block's next sideways step.
  final double stepTimer;

  final List<int> aliveRows;

  bool isAliveAt(int row, int col) => (aliveRows[row] >> col) & 1 == 1;

  bool get isEmpty => aliveRows.every((row) => row == 0);

  double get width => alienColumns * alienColumnPitch;
  double get height => rows * alienRowPitch;

  /// The row index of the lowest surviving alien (row 0 is the top), or
  /// `null` if the block is empty.
  ///
  /// Used for the invasion check instead of [height]: [height] is the
  /// original box the wave started with, so once the bottom row or two are
  /// wiped out it keeps describing space nothing occupies any more, and the
  /// block would be ruled to have reached the player before any surviving
  /// alien actually has.
  int? get lastAliveRow {
    for (var row = rows - 1; row >= 0; row--) {
      if (aliveRows[row] != 0) return row;
    }
    return null;
  }

  /// The leftmost column with a surviving alien, or `null` if the block is
  /// empty. Used for the wall check so a column wiped out at the marching
  /// edge shrinks the box the formation bounces off, rather than the
  /// formation reversing against a column that is no longer there.
  int? get firstAliveColumn {
    for (var col = 0; col < alienColumns; col++) {
      for (var row = 0; row < rows; row++) {
        if (isAliveAt(row, col)) return col;
      }
    }
    return null;
  }

  /// The rightmost column with a surviving alien, or `null` if the block is
  /// empty. See [firstAliveColumn].
  int? get lastAliveColumn {
    for (var col = alienColumns - 1; col >= 0; col--) {
      for (var row = 0; row < rows; row++) {
        if (isAliveAt(row, col)) return col;
      }
    }
    return null;
  }

  AlienBlock copyWith({
    double? originX,
    double? originY,
    int? direction,
    double? stepTimer,
    List<int>? aliveRows,
  }) => AlienBlock(
    originX: originX ?? this.originX,
    originY: originY ?? this.originY,
    rows: rows,
    direction: direction ?? this.direction,
    stepTimer: stepTimer ?? this.stepTimer,
    aliveRows: aliveRows ?? this.aliveRows,
  );
}

/// One of the four bunkers: its left edge, and its block grid — [bunkerRows]
/// entries, each a bitmask of [bunkerColumns] bits, row 0 at the top.
@immutable
class Bunker {
  const Bunker({required this.x, required this.blocks});

  final double x;
  final List<int> blocks;

  static const double y = bunkerY;
  static const double width = bunkerColumns * bunkerBlockSize;
  static const double height = bunkerRows * bunkerBlockSize;
}

/// The UFO, while it is crossing the field.
@immutable
class Ufo {
  const Ufo({required this.x, required this.direction, required this.score});

  final double x;
  final int direction;
  final int score;

  static const double y = ufoY;
  static const double width = ufoWidth;
  static const double height = ufoHeight;
}

/// One run of Invaders. Construct with the rules for the mode being played
/// and a seed for its [GameRng]; call [step] once per fixed tick.
class InvadersSim {
  InvadersSim({required this.rules, required int seed, this.autoFire = false})
    : _rng = GameRng(seed) {
    _lives = rules.lives;
    _player = const Player(
      x: (fieldWidth - playerWidth) / 2,
      alive: true,
      respawnTimer: 0,
      fireCooldown: 0,
    );
    _aliens = _newWave(1);
    _bunkers = _newBunkers();
    _alienFireTimer = rules.fireIntervalForWave(1);
    _ufoTimer = _scheduleUfo();
  }

  /// The tuning this run plays with — [InvadersRules.normal] or
  /// [InvadersRules.easy].
  final InvadersRules rules;

  /// Whether the player fires on its own whenever the cooldown allows
  /// (`PLAN.md` §4.1), rather than only when [PadInput.fire] is held. A
  /// profile setting, not a difficulty, so it is a constructor flag rather
  /// than a field on [InvadersRules].
  final bool autoFire;

  /// Every fixed step is exactly this many seconds — 1/120 s
  /// (`PLAN-phase-4.md` §4.2). It divides 60 Hz exactly and halves the
  /// judder 1/60 s would leave at 144 Hz.
  static const double fixedStep = 1 / 120;

  final GameRng _rng;

  int _score = 0;
  int _lives = 0;
  int _wave = 1;
  int _kills = 0;
  bool _isOver = false;
  int _nextBonusLifeScore = _bonusLifeThreshold;

  late Player _player;
  late AlienBlock _aliens;
  List<Shot> _shots = const [];
  late List<Bunker> _bunkers;
  Ufo? _ufo;
  late double _alienFireTimer;
  late double _ufoTimer;

  /// Oldest first; drained by [drainEvents]. See [maxBufferedEvents].
  final List<InvadersEvent> _events = [];

  int get score => _score;
  int get lives => _lives;
  int get wave => _wave;
  int get kills => _kills;
  bool get isOver => _isOver;

  Player get player => _player;
  AlienBlock get aliens => _aliens;
  List<Shot> get shots => _shots;
  List<Bunker> get bunkers => _bunkers;
  Ufo? get ufo => _ufo;

  /// Advances the run by exactly [fixedStep]. Nothing else advances it: the
  /// accumulator deciding how many times to call this for a frame lives in
  /// `invaders_game.dart`, not here (`PLAN-phase-4.md` §3).
  void step(PadInput input) {
    if (_isOver) return;
    _updatePlayer(input);
    _advanceAliens();
    _advanceUfo();
    _maybeFireAlien();
    _advanceShots();
    _resolveCollisions();
    _checkWaveClear();
  }

  /// Everything that happened since the last drain, oldest first. Capped at
  /// [maxBufferedEvents] with the oldest dropped, so a sim stepped without
  /// ever being drained cannot grow this without bound.
  List<InvadersEvent> drainEvents() {
    final events = List<InvadersEvent>.unmodifiable(_events);
    _events.clear();
    return events;
  }

  void _emit(InvadersEvent event) {
    _events.add(event);
    if (_events.length > maxBufferedEvents) _events.removeAt(0);
  }

  // --- Player -----------------------------------------------------------

  void _updatePlayer(PadInput input) {
    final cooldown = (_player.fireCooldown - fixedStep).clamp(
      0.0,
      double.infinity,
    );

    if (!_player.alive) {
      final respawnTimer = _player.respawnTimer - fixedStep;
      _player = respawnTimer <= _timerEpsilon
          ? const Player(
              x: (fieldWidth - playerWidth) / 2,
              alive: true,
              respawnTimer: 0,
              fireCooldown: 0,
            )
          : Player(
              x: _player.x,
              alive: false,
              respawnTimer: respawnTimer,
              fireCooldown: 0,
            );
      return;
    }

    var x = _player.x;
    if (input.left && !input.right) {
      x -= _playerSpeed * fixedStep;
    } else if (input.right && !input.left) {
      x += _playerSpeed * fixedStep;
    }
    x = x.clamp(0, fieldWidth - playerWidth);

    var nextCooldown = cooldown;
    if ((input.fire || autoFire) && cooldown <= _timerEpsilon) {
      _shots = [
        ..._shots,
        Shot(
          x: x + playerWidth / 2 - shotWidth / 2,
          y: playerY,
          fromPlayer: true,
        ),
      ];
      nextCooldown = _playerFireCooldown;
      _emit(InvadersEvent.playerShot);
    }

    _player = Player(
      x: x,
      alive: true,
      respawnTimer: 0,
      fireCooldown: nextCooldown,
    );
  }

  // --- Alien block --------------------------------------------------------

  void _advanceAliens() {
    final remaining = _aliens.stepTimer - fixedStep;
    if (remaining > _timerEpsilon) {
      _aliens = _aliens.copyWith(stepTimer: remaining);
      return;
    }

    final movingRight = _aliens.direction > 0;
    final nextOriginX =
        _aliens.originX +
        (movingRight ? _alienStepDistance : -_alienStepDistance);

    // The wall check uses the surviving columns' own bounding box, not the
    // full 11-column grid: once a column at the marching edge is wiped out,
    // there is no alien left to hit the wall, so the box the formation
    // bounces off shrinks and it takes longer to reach the real edge.
    final firstCol = _aliens.firstAliveColumn ?? 0;
    final lastCol = _aliens.lastAliveColumn ?? (alienColumns - 1);
    final hitsWall = movingRight
        ? nextOriginX + (lastCol + 1) * alienColumnPitch > fieldWidth
        : nextOriginX + firstCol * alienColumnPitch < 0;

    final interval = _currentStepInterval();
    _aliens = hitsWall
        ? _aliens.copyWith(
            direction: -_aliens.direction,
            originY: _aliens.originY + alienRowPitch,
            stepTimer: interval,
          )
        : _aliens.copyWith(originX: nextOriginX, stepTimer: interval);
    _emit(InvadersEvent.alienStep);
  }

  double _currentStepInterval() {
    final base = rules.baseStepForWave(_wave);
    final total = _aliens.rows * alienColumns;
    final alive = _aliens.aliveRows.fold<int>(
      0,
      (sum, row) => sum + _popcount(row),
    );
    if (alive == 0) return base;
    return (base * alive / total).clamp(rules.minStep, base);
  }

  AlienBlock _newWave(int wave) {
    final rows = rules.alienRows;
    final width = alienColumns * alienColumnPitch;
    return AlienBlock(
      originX: (fieldWidth - width) / 2,
      originY: 24 + (wave - 1) * alienRowPitch,
      rows: rows,
      direction: 1,
      stepTimer: rules.baseStepForWave(wave),
      aliveRows: List<int>.filled(rows, (1 << alienColumns) - 1),
    );
  }

  void _checkWaveClear() {
    if (_isOver || !_aliens.isEmpty) return;
    _wave += 1;
    _aliens = _newWave(_wave);
    _alienFireTimer = rules.fireIntervalForWave(_wave);
    _emit(InvadersEvent.waveCleared);
  }

  // --- Alien fire ---------------------------------------------------------

  void _maybeFireAlien() {
    _alienFireTimer -= fixedStep;
    if (_alienFireTimer > _timerEpsilon) return;

    final aliveAlienShots = _shots.where((shot) => !shot.fromPlayer).length;
    if (aliveAlienShots >= rules.maxAlienShots) {
      _alienFireTimer = 0;
      return;
    }

    final columns = <int>[
      for (var col = 0; col < alienColumns; col++)
        if (_lowestAliveRow(col) != null) col,
    ];
    _alienFireTimer = rules.fireIntervalForWave(_wave);
    if (columns.isEmpty) return;

    final col = _rng.pick(columns);
    final row = _lowestAliveRow(col)!;
    final x =
        _aliens.originX +
        col * alienColumnPitch +
        alienColumnPitch / 2 -
        shotWidth / 2;
    final y = _aliens.originY + row * alienRowPitch + alienHeight;
    _shots = [..._shots, Shot(x: x, y: y, fromPlayer: false)];
    _emit(InvadersEvent.alienShot);
  }

  int? _lowestAliveRow(int col) {
    for (var row = _aliens.rows - 1; row >= 0; row--) {
      if (_aliens.isAliveAt(row, col)) return row;
    }
    return null;
  }

  // --- UFO ------------------------------------------------------------

  void _advanceUfo() {
    final ufo = _ufo;
    if (ufo == null) {
      _ufoTimer -= fixedStep;
      if (_ufoTimer <= _timerEpsilon) {
        _ufo = Ufo(x: fieldWidth, direction: -1, score: _rng.pick(_ufoScores));
        _emit(InvadersEvent.ufoAppeared);
      }
      return;
    }

    final x = ufo.x + ufo.direction * _ufoSpeed * fixedStep;
    if (x + ufoWidth < 0 || x > fieldWidth) {
      _ufo = null;
      _ufoTimer = _scheduleUfo();
      _emit(InvadersEvent.ufoLeft);
    } else {
      _ufo = Ufo(x: x, direction: ufo.direction, score: ufo.score);
    }
  }

  double _scheduleUfo() =>
      _ufoInterval + (_rng.nextDouble() * 2 - 1) * _ufoJitter;

  // --- Shots ------------------------------------------------------------

  void _advanceShots() {
    final next = <Shot>[];
    for (final shot in _shots) {
      final dy = shot.fromPlayer
          ? -_playerShotSpeed * fixedStep
          : _alienShotSpeed * fixedStep;
      final y = shot.y + dy;
      if (y + shotHeight < 0 || y > fieldHeight) continue;
      next.add(Shot(x: shot.x, y: y, fromPlayer: shot.fromPlayer));
    }
    _shots = next;
  }

  // --- Collisions, in the order `PLAN.md` §4.1 states --------------------

  void _resolveCollisions() {
    _resolveShotsVsAliens();
    _resolveShotsVsBunkers();
    _resolveShotsVsPlayer();
    _resolveBlockVsPlayerRow();
  }

  void _resolveShotsVsAliens() {
    final remaining = <Shot>[];
    final aliveRows = List<int>.of(_aliens.aliveRows);
    var changed = false;
    var ufo = _ufo;

    for (final shot in _shots) {
      if (!shot.fromPlayer) {
        remaining.add(shot);
        continue;
      }

      if (ufo != null && _hitsUfo(shot, ufo)) {
        _score += ufo.score;
        _kills += 1;
        _maybeAwardBonusLife();
        ufo = null;
        _emit(InvadersEvent.ufoKilled);
        continue;
      }

      final hit = _alienHitBy(shot, aliveRows);
      if (hit == null) {
        remaining.add(shot);
        continue;
      }
      aliveRows[hit.row] &= ~(1 << hit.col);
      changed = true;
      _score += _pointsForRow(hit.row);
      _kills += 1;
      _maybeAwardBonusLife();
      _emit(InvadersEvent.alienKilled);
    }

    _shots = remaining;
    _ufo = ufo;
    if (changed) _aliens = _aliens.copyWith(aliveRows: aliveRows);
  }

  ({int row, int col})? _alienHitBy(Shot shot, List<int> aliveRows) {
    final shotLeft = shot.x;
    final shotRight = shot.x + shotWidth;
    final shotTop = shot.y;
    final shotBottom = shot.y + shotHeight;

    for (var row = 0; row < _aliens.rows; row++) {
      final alienTop = _aliens.originY + row * alienRowPitch;
      final alienBottom = alienTop + alienHeight;
      if (shotBottom < alienTop || shotTop > alienBottom) continue;

      for (var col = 0; col < alienColumns; col++) {
        if ((aliveRows[row] >> col) & 1 == 0) continue;
        final alienLeft = _aliens.originX + col * alienColumnPitch;
        final alienRight = alienLeft + alienWidth;
        if (shotRight < alienLeft || shotLeft > alienRight) continue;
        return (row: row, col: col);
      }
    }
    return null;
  }

  bool _hitsUfo(Shot shot, Ufo ufo) =>
      shot.x + shotWidth >= ufo.x &&
      shot.x <= ufo.x + ufoWidth &&
      shot.y + shotHeight >= Ufo.y &&
      shot.y <= Ufo.y + ufoHeight;

  int _pointsForRow(int row) {
    final distanceFromFront = _aliens.rows - 1 - row;
    if (distanceFromFront <= 0) return 10;
    if (distanceFromFront <= 2) return 20;
    return 30;
  }

  void _resolveShotsVsBunkers() {
    final bunkers = List<Bunker>.of(_bunkers);
    final remaining = <Shot>[];

    for (final shot in _shots) {
      var absorbed = false;
      for (var i = 0; i < bunkers.length; i++) {
        final hit = _blockHit(shot, bunkers[i]);
        if (hit == null) continue;
        bunkers[i] = _erode(bunkers[i], hit.row, hit.col);
        absorbed = true;
        break;
      }
      if (!absorbed) remaining.add(shot);
    }

    _bunkers = bunkers;
    _shots = remaining;
  }

  ({int row, int col})? _blockHit(Shot shot, Bunker bunker) {
    final shotCenterX = shot.x + shotWidth / 2;
    final shotCenterY = shot.y + shotHeight / 2;
    if (shotCenterX < bunker.x || shotCenterX >= bunker.x + Bunker.width) {
      return null;
    }
    if (shotCenterY < Bunker.y || shotCenterY >= Bunker.y + Bunker.height) {
      return null;
    }
    final col = ((shotCenterX - bunker.x) / bunkerBlockSize).floor();
    final row = ((shotCenterY - Bunker.y) / bunkerBlockSize).floor();
    if ((bunker.blocks[row] >> col) & 1 == 0) return null;
    return (row: row, col: col);
  }

  Bunker _erode(Bunker bunker, int row, int col) {
    final blocks = List<int>.of(bunker.blocks);
    for (var r = 0; r < bunkerRows; r++) {
      final dr = r - row;
      for (var c = 0; c < bunkerColumns; c++) {
        final dc = c - col;
        if (dr * dr + dc * dc <= _erosionRadius * _erosionRadius) {
          blocks[r] &= ~(1 << c);
        }
      }
    }
    return Bunker(x: bunker.x, blocks: blocks);
  }

  void _resolveShotsVsPlayer() {
    if (!_player.alive) return;
    final playerLeft = _player.x;
    final playerRight = _player.x + playerWidth;
    const playerTop = playerY;
    const playerBottom = playerY + playerHeight;

    final remaining = <Shot>[];
    var hit = false;
    for (final shot in _shots) {
      if (shot.fromPlayer) {
        remaining.add(shot);
        continue;
      }
      final overlaps =
          shot.x + shotWidth >= playerLeft &&
          shot.x <= playerRight &&
          shot.y + shotHeight >= playerTop &&
          shot.y <= playerBottom;
      if (overlaps) {
        // Every alien shot overlapping the player this tick is consumed, not
        // only the first — several can plausibly land in the same tick when
        // `maxAlienShots` is above 1, and a shot that overlapped the player
        // should not pass through it.
        hit = true;
      } else {
        remaining.add(shot);
      }
    }
    _shots = remaining;

    if (!hit) return;
    _lives -= 1;
    _player = _lives <= 0
        ? Player(x: _player.x, alive: false, respawnTimer: 0, fireCooldown: 0)
        : Player(
            x: _player.x,
            alive: false,
            respawnTimer: _playerRespawnDelay,
            fireCooldown: 0,
          );
    if (_lives <= 0) _isOver = true;
    _emit(InvadersEvent.playerKilled);
  }

  void _resolveBlockVsPlayerRow() {
    if (_isOver || _aliens.isEmpty) return;
    final lastAliveRow = _aliens.lastAliveRow;
    if (lastAliveRow == null) return;
    final blockBottom =
        _aliens.originY + lastAliveRow * alienRowPitch + alienHeight;
    if (blockBottom >= playerY) {
      _isOver = true;
      _emit(InvadersEvent.playerKilled);
    }
  }

  void _maybeAwardBonusLife() {
    while (_score >= _nextBonusLifeScore) {
      _lives += 1;
      _nextBonusLifeScore += _bonusLifeThreshold;
      _emit(InvadersEvent.extraLife);
    }
  }

  // --- Bunkers -------------------------------------------------------

  List<Bunker> _newBunkers() {
    final spacing = fieldWidth / bunkerCount;
    return [
      for (var i = 0; i < bunkerCount; i++)
        Bunker(
          x: spacing * i + (spacing - Bunker.width) / 2,
          blocks: List<int>.filled(bunkerRows, (1 << bunkerColumns) - 1),
        ),
    ];
  }

  // --- Test seams ------------------------------------------------------

  /// Replaces the alien block's per-row alive bitmasks directly.
  ///
  /// `@visibleForTesting`: reaching a specific alive count (to check the
  /// march-interval formula) or an empty block (to check wave clear) through
  /// real play means scripting a shot into a precise alien on a precise
  /// tick, which would make those tests about aiming rather than about the
  /// formula or the clear condition. `invaders_sim_test.dart` uses this to
  /// set up the state directly; the collision path that produces it is
  /// covered separately by the tests that fire through it for real.
  @visibleForTesting
  void debugSetAliveRows(List<int> aliveRows) {
    _aliens = _aliens.copyWith(aliveRows: aliveRows);
  }

  /// Sets the alien block's march timer directly, so a test can force the
  /// next [step] to include a march instead of waiting out the interval.
  @visibleForTesting
  void debugSetAlienTimer(double seconds) {
    _aliens = _aliens.copyWith(stepTimer: seconds);
  }

  /// Sets the alien fire timer directly, so a test can force the next [step]
  /// to fire an alien shot instead of waiting out the interval.
  @visibleForTesting
  void debugSetAlienFireTimer(double seconds) {
    _alienFireTimer = seconds;
  }

  /// Sets the UFO's arrival timer directly, so a test can force the next
  /// [step] to spawn it instead of waiting out `_ufoInterval`.
  @visibleForTesting
  void debugSetUfoTimer(double seconds) {
    _ufoTimer = seconds;
  }

  /// Replaces the UFO directly, present or absent, so a test can place it
  /// exactly where a shot will be rather than waiting out its transit or
  /// chasing it into alignment.
  @visibleForTesting
  void debugSetUfo(Ufo? ufo) {
    _ufo = ufo;
  }

  /// Ends the run immediately, as if the last life had just been lost,
  /// without a real collision. For a test that only needs [isOver] to become
  /// true and does not care how — `invaders_game_test.dart`'s check that
  /// [InvadersGame] silences a loop still playing when the run ends, which a
  /// real collision would answer just as well but far less directly.
  @visibleForTesting
  void debugEndGame() {
    _isOver = true;
  }

  /// Adds [points] to the score and grants any bonus life it crosses, the
  /// same way a kill does.
  ///
  /// `@visibleForTesting`: landing on an exact score through real kills means
  /// finding a combination of 10s, 20s and 30s that sums to exactly 10,000,
  /// which would make the bonus-life test about arithmetic on point values
  /// rather than about the threshold rule itself.
  @visibleForTesting
  void debugAwardScore(int points) {
    _score += points;
    _maybeAwardBonusLife();
  }
}

int _popcount(int mask) {
  var count = 0;
  var value = mask;
  while (value != 0) {
    value &= value - 1;
    count++;
  }
  return count;
}
