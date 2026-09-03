// `/arcade/snake` (`PLAN-phase-7-snake.md` §6, PR 4). Reachable, until PR 5
// deletes it, from a temporary button on `/arcade` beside the Invaders card
// — `arcade_menu_screen.dart` names the same PR at that button.
//
// Thin on purpose, the same shape `invaders_screen.dart` is: everything about
// *playing* a run is `GameShell`'s. This screen's only job is to build the
// one `SnakeGame` for this run from the active profile's options and hand it
// to the shell, reading `arcadeEasyMode` and `snakeCounting` once, when the
// run starts, exactly as `InvadersScreen` reads `arcadeEasyMode` and
// `arcadeAutoFire` (`PLAN-phase-4.md` §4.10).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/haptics.dart';
import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/storage/save_data.dart';
import '../../../core/ui/tokens.dart';
import '../shared/game_shell.dart';
import '../shared/on_screen_pad.dart' show PadLayout;
import '../shared/pad_input.dart';
import 'model/counting.dart' as model show SnakeCounting;
import 'model/snake_rules.dart';
import 'model/snake_sim.dart';
import 'snake_game.dart';

/// The key [ProgressRepository.recordArcadeResult] and
/// [ProgressRepository.startArcadeGame] store this game's progress under
/// (`PLAN-phase-7-snake.md` §4.8, §4.9).
const String snakeGameId = 'snake';

/// Translates the profile's stored choice into the model's own enum of the
/// same name and shape — the meeting point `snake_sim.dart`'s header names:
/// `model/` stays free of every import but `PadInput` so its tests need no
/// Flutter beyond `foundation.dart`, which rules out importing
/// `core/storage/save_data.dart`'s `SnakeCounting` from there.
model.SnakeCounting _toModelCounting(SnakeCounting counting) =>
    switch (counting) {
      SnakeCounting.off => model.SnakeCounting.off,
      SnakeCounting.ones => model.SnakeCounting.ones,
      SnakeCounting.twos => model.SnakeCounting.twos,
    };

class SnakeScreen extends ConsumerStatefulWidget {
  const SnakeScreen({super.key});

  @override
  ConsumerState<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends ConsumerState<SnakeScreen> {
  late final ProgressRepository _repository;
  late final DateTime Function() _now;
  late final Profile _profile;
  SnakeGame? _game;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(progressRepositoryProvider);
    _now = ref.read(nowProvider);
    _profile = _repository.activeProfile;
  }

  @override
  void dispose() {
    _game?.input.dispose();
    super.dispose();
  }

  int _seed() => _now().millisecondsSinceEpoch & 0xFFFFFFFF;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context).brightness);
    final game = _game ??= SnakeGame(
      sim: SnakeSim(
        rules: _profile.arcadeEasyMode ? SnakeRules.easy : SnakeRules.normal,
        counting: _toModelCounting(_profile.snakeCounting),
        seed: _seed(),
      ),
      seed: _seed,
      input: ValueNotifier(PadInput.none),
      color: palette.arcade,
    );
    // Kept live rather than only set at construction, the same reason
    // `InvadersScreen` keeps it live: under `ThemeMode.system` the device can
    // switch brightness while this screen stays open.
    game.color = palette.arcade;

    // `padSide` alone is watched rather than read with the rest of `_profile`
    // at start, the same reason `InvadersScreen` watches it: it is the one
    // option `OnScreenPad` draws from on every build, where the rules and the
    // counting mode only ever mattered at the moment this run's `sim` was
    // built.
    final padSide = ref.watch(activeProfileProvider).padSide;

    return GameShell(
      controller: game,
      title: 'Snake',
      gameId: snakeGameId,
      repository: _repository,
      padSide: padSide,
      haptics: ref.read(appHapticsProvider),
      // Snake counts levels, not waves (`PLAN-phase-7-snake.md` §4.7).
      waveLabel: 'Level',
      padLayout: PadLayout.dPad,
    );
  }
}
