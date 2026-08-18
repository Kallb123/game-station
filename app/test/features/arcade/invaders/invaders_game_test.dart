// `InvadersGame`'s accumulator, pause behaviour and event-to-sound mapping
// (`PLAN-phase-4.md` §4.2, §4.5; `PLAN-phase-5.md` §4.4, PR 4). The sim's own
// logic — the alien march, scoring, collisions, which method emits which
// `InvadersEvent` — is `invaders_sim_test.dart`'s and
// `invaders_sim_equivalence_test.dart`'s; this file exercises the
// frame-to-fixed-step arithmetic `InvadersGame` adds on top, through the
// `debugStepsDone` seam, and the drain-and-play step that turns a drained
// event into a `RecordingAudio` call.
//
// These are plain `test()` calls driving `update(dt)` directly rather than a
// pumped `GameWidget`: a real Flame ticker's frame timing is not something a
// test controls, and the arithmetic under test does not need one — the same
// reasoning `invaders_sim_equivalence_test.dart` gives for stepping its sim
// by hand instead of through a widget. `invaders_screen_test.dart` is where a
// `GameWidget` actually gets pumped, to check that it renders at all.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/app_audio.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_game.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_rules.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_sim.dart';
import 'package:zibo_games/features/arcade/shared/arcade_controller.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

import '../../../core/audio/recording_audio.dart';

InvadersGame _newGame({AppAudio audio = const SilentAudio()}) => InvadersGame(
  sim: InvadersSim(rules: InvadersRules.normal, seed: 1),
  seed: () => 1,
  input: ValueNotifier(PadInput.none),
  color: Colors.green,
  audio: audio,
);

void main() {
  test('a frame worth exactly one fixed step advances the sim by one', () {
    final game = _newGame();

    game.update(InvadersSim.fixedStep);

    expect(game.debugStepsDone, 1);
  });

  test('60 Hz and 144 Hz frame sequences reach the same step count', () {
    final at60Hz = _newGame();
    final at144Hz = _newGame();

    // The same 600-frames-of-1/60-s and 1440-frames-of-1/144-s sequences
    // `invaders_sim_equivalence_test.dart` uses for its ten seconds of play —
    // not an arbitrary round number: that file's header explains why 1440
    // additions of 1/144 land a hair under 10.0 s in binary floating point
    // where 600 additions of 1/60 land on exactly 10.0 s, so a shorter,
    // "rounder" pair of sequences can disagree by one step where these are
    // proven not to.
    for (var frame = 0; frame < 600; frame++) {
      at60Hz.update(1 / 60);
    }
    for (var frame = 0; frame < 1440; frame++) {
      at144Hz.update(1 / 144);
    }

    // Ten seconds is 1200 fixed steps (10 s / (1/120 s)) — the same
    // equivalence `invaders_sim_equivalence_test.dart` checks on the sim
    // itself, checked here on the accumulator that feeds it.
    expect(at60Hz.debugStepsDone, 1200);
    expect(at144Hz.debugStepsDone, 1200);
  });

  test(
    'a stalled frame is clamped to maxStepsPerFrame rather than caught up',
    () {
      final game = _newGame();

      // Half a second is 60 fixed steps' worth of time — the clamp must stop
      // at 8 and drop the other 52 rather than run all 60 in one frame
      // (`PLAN-phase-4.md` §4.2).
      game.update(0.5);

      expect(game.debugStepsDone, maxStepsPerFrame);
    },
  );

  test('a dropped backlog is not made up on the next frame', () {
    final game = _newGame();

    game.update(0.5); // clamped to 8 steps, the other 52 steps' worth dropped
    game.update(InvadersSim.fixedStep); // one ordinary frame

    expect(game.debugStepsDone, maxStepsPerFrame + 1);
  });

  test(
    'pauseEngine stops steps and resumeEngine does not replay the pause',
    () {
      final game = _newGame();

      game.update(InvadersSim.fixedStep);
      final stepsBeforePause = game.debugStepsDone;

      game.pauseEngine();
      // Stands in for the wall-clock time a backgrounded app misses — however
      // large, it must not turn into fixed steps while paused, and must not be
      // replayed once resumed either.
      game.update(5.0);
      expect(
        game.debugStepsDone,
        stepsBeforePause,
        reason: 'no steps while paused',
      );

      game.resumeEngine();
      game.update(InvadersSim.fixedStep);
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
    game.update(InvadersSim.fixedStep);
    expect(game.debugStepsDone, 0, reason: 'no steps while paused');

    game.resume();
    game.update(InvadersSim.fixedStep);
    expect(game.debugStepsDone, 1);
  });

  test('hud reflects the sim after a step', () {
    final game = _newGame();

    expect(game.hud.value, ArcadeHud(score: 0, lives: game.sim.lives, wave: 1));

    game.update(InvadersSim.fixedStep);

    expect(
      game.hud.value,
      ArcadeHud(
        score: game.sim.score,
        lives: game.sim.lives,
        wave: game.sim.wave,
      ),
    );
  });

  test('restart begins a fresh run with a new sim', () {
    final game = _newGame();
    final firstRun = game.sim;

    game.update(InvadersSim.fixedStep);
    final stepsBeforeRestart = game.debugStepsDone;
    game.pauseEngine(); // stands in for the game-over pause `GameShell` applies
    game.restart();

    expect(identical(game.sim, firstRun), isFalse);
    expect(game.isOver.value, isFalse);
    expect(game.hud.value, ArcadeHud(score: 0, lives: game.sim.lives, wave: 1));
    expect(game.paused, isFalse, reason: 'restart resumes the engine');

    game.update(InvadersSim.fixedStep);
    expect(
      game.debugStepsDone,
      stepsBeforeRestart + 1,
      reason:
          'the accumulator was reset, not carrying a backlog into the '
          'new run',
    );
  });

  group('events turn into sounds', () {
    test('a player shot plays its motif', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio);

      game.input.value = const PadInput(fire: true);
      game.update(InvadersSim.fixedStep);

      expect(audio.played, [Motif.arcadePlayerShoot]);
    });

    test('the alien block stepping plays its motif', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio);

      game.sim.debugSetAlienTimer(0);
      game.update(InvadersSim.fixedStep);

      expect(audio.played, [Motif.arcadeAlienMove]);
    });

    test('the UFO appearing starts its loop, leaving stops it', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio);

      game.sim.debugSetUfoTimer(0);
      game.update(InvadersSim.fixedStep);
      expect(audio.looping, {Motif.arcadeUfoLoop});

      // Drive it off the field's right edge, where it entered.
      while (game.sim.ufo != null) {
        game.update(InvadersSim.fixedStep);
      }
      expect(audio.looping, isEmpty);
    });

    test('pause silences everything, including a loop still playing', () {
      final audio = RecordingAudio();
      final game = _newGame(audio: audio);

      game.sim.debugSetUfoTimer(0);
      game.update(InvadersSim.fixedStep);
      expect(audio.looping, isNotEmpty);

      game.pause();

      expect(audio.looping, isEmpty);
    });

    test('sound off silences every motif', () {
      final audio = RecordingAudio()
        ..applySettings(const AppSettings(sound: false));
      final game = _newGame(audio: audio);

      game.input.value = const PadInput(fire: true);
      game.sim.debugSetAlienTimer(0);
      game.update(InvadersSim.fixedStep);

      expect(audio.played, isEmpty);
      expect(audio.looping, isEmpty);
    });
  });
}
