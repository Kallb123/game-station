// `SnakeGame`'s accumulator, pause behaviour and the `ArcadeHud`/`ArcadeResult`
// translation from `SnakeSim` state (`PLAN-phase-7-snake.md` §4.2, §4.5, §4.7,
// PR 4). The sim's own logic — movement, growth, collisions, the counting
// sequence — is `snake_sim_test.dart`'s and `snake_sim_equivalence_test.dart`'s;
// this file exercises the frame-to-fixed-step arithmetic `SnakeGame` adds on
// top, through the `debugStepsDone` seam, and the numeral extent
// `snake_game.dart` computes for the render pass.
//
// These are plain `test()` calls driving `update(dt)` directly, the same
// reasoning `invaders_game_test.dart` gives for its own: a real Flame
// ticker's frame timing is not something a test controls, and the arithmetic
// under test does not need one. `snake_screen_test.dart` is where a
// `GameWidget` actually gets pumped.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/app_audio.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/save_data.dart' hide SnakeCounting;
import 'package:zibo_games/features/arcade/shared/arcade_controller.dart';
import 'package:zibo_games/features/arcade/shared/fixed_step.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';
import 'package:zibo_games/features/arcade/snake/model/counting.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_rules.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';
import 'package:zibo_games/features/arcade/snake/snake_game.dart';

import '../../../core/audio/recording_audio.dart';
import '../../../core/recording_haptics.dart';

SnakeGame _newGame({
  SnakeRules rules = SnakeRules.normal,
  SnakeCounting counting = SnakeCounting.ones,
  int seed = 1,
  AppAudio audio = const SilentAudio(),
  AppHaptics haptics = const SilentHaptics(),
}) => SnakeGame(
  sim: SnakeSim(rules: rules, counting: counting, seed: seed),
  seed: () => seed,
  input: ValueNotifier(PadInput.none),
  color: Colors.green,
  audio: audio,
  haptics: haptics,
);

void main() {
  test('a frame worth exactly one fixed step advances the sim by one', () {
    final game = _newGame();

    game.update(fixedStep);

    expect(game.debugStepsDone, 1);
  });

  test('60 Hz and 144 Hz frame sequences reach the same step count', () {
    final at60Hz = _newGame();
    final at144Hz = _newGame();

    // The same 600-frames-of-1/60-s and 1440-frames-of-1/144-s sequences
    // `invaders_game_test.dart` uses, for the same reason: not an arbitrary
    // round number, but the pair proven not to disagree by one step in
    // binary floating point (`invaders_sim_equivalence_test.dart`'s header).
    for (var frame = 0; frame < 600; frame++) {
      at60Hz.update(1 / 60);
    }
    for (var frame = 0; frame < 1440; frame++) {
      at144Hz.update(1 / 144);
    }

    expect(at60Hz.debugStepsDone, 1200);
    expect(at144Hz.debugStepsDone, 1200);
  });

  test(
    'a stalled frame is clamped to maxStepsPerFrame rather than caught up',
    () {
      final game = _newGame();

      game.update(0.5);

      expect(game.debugStepsDone, maxStepsPerFrame);
    },
  );

  test('a dropped backlog is not made up on the next frame', () {
    final game = _newGame();

    game.update(0.5); // clamped to 8 steps, the other steps' worth dropped
    game.update(fixedStep); // one ordinary frame

    expect(game.debugStepsDone, maxStepsPerFrame + 1);
  });

  test(
    'pauseEngine stops steps and resumeEngine does not replay the pause',
    () {
      final game = _newGame();

      game.update(fixedStep);
      final stepsBeforePause = game.debugStepsDone;

      game.pauseEngine();
      // Stands in for the wall-clock time a backgrounded app misses.
      game.update(5.0);
      expect(
        game.debugStepsDone,
        stepsBeforePause,
        reason: 'no steps while paused',
      );

      game.resumeEngine();
      game.update(fixedStep);
      expect(
        game.debugStepsDone,
        stepsBeforePause + 1,
        reason: 'the paused interval was discarded, not queued',
      );
    },
  );

  test('pause and resume, the ArcadeGameController members, reach the same '
      'engine as pauseEngine and resumeEngine', () {
    final game = _newGame();

    game.pause();
    game.update(fixedStep);
    expect(game.debugStepsDone, 0, reason: 'no steps while paused');

    game.resume();
    game.update(fixedStep);
    expect(game.debugStepsDone, 1);
  });

  group('the HUD note', () {
    test('reads "Next 1" for a fresh ones-counting run', () {
      final game = _newGame(counting: SnakeCounting.ones);

      expect(game.hud.value.note, 'Next 1');
      expect(game.hud.value.wave, 1, reason: 'the run starts at level 1');
    });

    test('reads "Next 2" for a fresh twos-counting run', () {
      final game = _newGame(counting: SnakeCounting.twos);

      expect(game.hud.value.note, 'Next 2');
    });

    test('is empty in classic mode', () {
      final game = _newGame(counting: SnakeCounting.off);

      expect(game.hud.value.note, '');
    });

    test('reflects the sim after a step', () {
      final game = _newGame();

      game.update(fixedStep);

      expect(
        game.hud.value,
        ArcadeHud(
          score: game.sim.score,
          lives: game.sim.lives,
          wave: game.sim.level,
          note: 'Next ${game.sim.nextValue}',
        ),
      );
    });
  });

  test('restart begins a fresh run with a new sim', () {
    final game = _newGame();
    final firstRun = game.sim;

    game.update(fixedStep);
    final stepsBeforeRestart = game.debugStepsDone;
    game.pauseEngine(); // stands in for the game-over pause `GameShell` applies
    game.restart();

    expect(identical(game.sim, firstRun), isFalse);
    expect(game.isOver.value, isFalse);
    expect(game.hud.value.score, 0);
    expect(game.hud.value.wave, 1);
    expect(game.paused, isFalse, reason: 'restart resumes the engine');

    game.update(fixedStep);
    expect(
      game.debugStepsDone,
      stepsBeforeRestart + 1,
      reason:
          'the accumulator was reset, not carrying a backlog into the '
          'new run',
    );
  });

  group('result', () {
    test('reports the counting mode and the longest length reached', () {
      final game = _newGame(counting: SnakeCounting.twos);

      expect(game.result.counting, isTrue);
      expect(game.result.length, game.sim.longest);
      expect(game.result.wave, game.sim.level);
      expect(game.result.kills, game.sim.eaten);
    });

    test('counting is false in classic mode', () {
      final game = _newGame(counting: SnakeCounting.off);

      expect(game.result.counting, isFalse);
    });

    test('easy is true for a run built with SnakeRules.easy', () {
      final game = _newGame(rules: SnakeRules.easy);

      expect(game.result.easy, isTrue);
    });
  });

  group('numeralExtent stays inside the cell', () {
    for (final value in [7, 42, 200]) {
      test('$value', () {
        final extent = numeralExtent(value);

        expect(extent.left, greaterThanOrEqualTo(0));
        expect(extent.top, greaterThanOrEqualTo(0));
        expect(extent.right, lessThanOrEqualTo(cellSize));
        expect(extent.bottom, lessThanOrEqualTo(cellSize));
      });
    }
  });

  group('events turn into sounds', () {
    test('eating the next target plays snakeEat', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio, counting: SnakeCounting.ones);

      game.sim.debugSetBody([const Cell(5, 5)], heading: SnakeDirection.right);
      game.sim.debugSetTargets([
        SnakeTarget(cell: const Cell(6, 5), value: game.sim.nextValue),
      ]);
      game.sim.debugForceMoveNext();
      game.update(fixedStep);

      expect(audio.played, [Motif.snakeEat]);
    });

    test('a decoy crossed plays snakeNotYet once, not once per tick spent '
        'sitting on it', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio, counting: SnakeCounting.ones);

      game.sim.debugSetBody([const Cell(5, 5)], heading: SnakeDirection.right);
      // A value other than `nextValue`, so this is a decoy rather than the
      // target the sequence is waiting for.
      game.sim.debugSetTargets([
        SnakeTarget(cell: const Cell(6, 5), value: game.sim.nextValue + 1),
      ]);
      game.sim.debugForceMoveNext();
      game.update(fixedStep); // crosses onto the decoy

      expect(audio.played, [Motif.snakeNotYet]);

      // The head stays on that cell for the rest of this move interval —
      // `_advance` runs again only once `moveTicksAt` ticks have passed
      // (`snake_sim.dart`'s own comment on why `notYet` fires on entering
      // a cell, not on every step inside it) — so nothing more should
      // play while it sits there.
      final ticksLeft = game.sim.rules.moveTicksAt(game.sim.level, 0) - 1;
      for (var i = 0; i < ticksLeft; i++) {
        game.update(fixedStep);
      }

      expect(audio.played, [
        Motif.snakeNotYet,
      ], reason: 'one sound, not one per tick spent on the decoy');
    });

    test('a crash plays snakeCrash and buzzes haptics', () {
      final audio = RecordingAudio();
      final haptics = RecordingHaptics();
      final game = _newGame(audio: audio, haptics: haptics);

      game.sim.debugSetBody([
        Cell(columns - 1, 5),
      ], heading: SnakeDirection.right);
      game.sim.debugForceMoveNext();
      game.update(fixedStep);

      expect(audio.played, [Motif.snakeCrash]);
      expect(haptics.calls, ['impact']);
    });

    test('clearing a level plays snakeLevelClear after the final snakeEat, '
        'and buzzes haptics', () {
      final audio = RecordingAudio();
      final haptics = RecordingHaptics();
      final game = _newGame(
        audio: audio,
        haptics: haptics,
        counting: SnakeCounting.ones,
      );

      for (var i = 0; i < SnakeRules.normal.targetsPerLevel; i++) {
        game.sim.debugSetBody([
          const Cell(5, 5),
        ], heading: SnakeDirection.right);
        game.sim.debugSetTargets([
          SnakeTarget(cell: const Cell(6, 5), value: game.sim.nextValue),
        ]);
        game.sim.debugForceMoveNext();
        // `resumeEngine` zeroes the accumulator (`snake_game.dart`'s own
        // doc on why), which is what makes one `fixedStep`-sized `update`
        // advance the sim by exactly one tick on every iteration —
        // otherwise floating-point drift across ten calls occasionally
        // carries a leftover into a call that then advances by zero or
        // two, decoupling this loop's debug state from the tick that
        // actually consumes it.
        game.resumeEngine();
        game.update(fixedStep);
      }

      expect(audio.played, [
        ...List.filled(SnakeRules.normal.targetsPerLevel, Motif.snakeEat),
        Motif.snakeLevelClear,
      ]);
      expect(haptics.calls, ['impact']);
    });

    test('a muted profile plays nothing', () {
      final audio = RecordingAudio()
        ..applySettings(const AppSettings(sound: false));
      final game = _newGame(audio: audio, counting: SnakeCounting.ones);

      game.sim.debugSetBody([const Cell(5, 5)], heading: SnakeDirection.right);
      game.sim.debugSetTargets([
        SnakeTarget(cell: const Cell(6, 5), value: game.sim.nextValue),
      ]);
      game.sim.debugForceMoveNext();
      game.update(fixedStep);

      expect(audio.played, isEmpty);
    });
  });

  test('isOver flips once the last life is lost', () {
    final game = _newGame(rules: SnakeRules.normal); // 3 lives, no wrapping

    // Crashes all three lives against the right wall through the same debug
    // seams `snake_sim_test.dart` uses for the same reason: reaching a wall
    // through real play would make this test about navigating there rather
    // than about what `SnakeGame` does once the run ends.
    for (var life = 0; life < 3; life++) {
      game.sim.debugSetBody([
        Cell(columns - 1, 5),
      ], heading: SnakeDirection.right);
      game.sim.debugForceMoveNext();
      game.update(fixedStep);

      if (life < 2) {
        // Waits out the respawn pause before the next crash can register.
        for (var i = 0; i < game.sim.rules.respawnTicks + 1; i++) {
          game.update(fixedStep);
        }
      }
    }

    expect(game.isOver.value, isTrue);
  });
}
