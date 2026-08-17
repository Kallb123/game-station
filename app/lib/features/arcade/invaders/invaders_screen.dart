// `/arcade/invaders` (`PLAN-phase-4.md` §6, PR 4 through PR 6), reachable for
// now from a temporary button on `/arcade` that PR 7 deletes once the real
// menu card exists (`arcade_menu_screen.dart`).
//
// Thin on purpose: everything about *playing* a run — the HUD, pause, quit
// confirmation, the game-over card and the write to the save — is
// `GameShell`'s (`shared/game_shell.dart`). This screen's only job is to
// build the one `InvadersGame` for this run from the active profile's
// options and hand it to the shell, the way `PLAN-phase-4.md` §4.10 says a
// run's options are read once, when it starts, rather than watched for a
// change nothing on this screen can make.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/storage/save_data.dart';
import '../../../core/ui/tokens.dart';
import '../shared/game_shell.dart';
import '../shared/pad_input.dart';
import 'invaders_game.dart';
import 'model/invaders_rules.dart';
import 'model/invaders_sim.dart';

/// The key [ProgressRepository.recordArcadeResult] and
/// [ProgressRepository.startArcadeGame] store this game's progress under
/// (`PLAN-phase-4.md` §4.9, §5.2).
const String invadersGameId = 'invaders';

class InvadersScreen extends ConsumerStatefulWidget {
  const InvadersScreen({super.key});

  @override
  ConsumerState<InvadersScreen> createState() => _InvadersScreenState();
}

class _InvadersScreenState extends ConsumerState<InvadersScreen> {
  late final ProgressRepository _repository;
  late final DateTime Function() _now;
  late final Profile _profile;
  InvadersGame? _game;

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
    final game = _game ??= InvadersGame(
      sim: InvadersSim(
        rules: _profile.arcadeEasyMode
            ? InvadersRules.easy
            : InvadersRules.normal,
        seed: _seed(),
        autoFire: _profile.arcadeAutoFire,
      ),
      seed: _seed,
      input: ValueNotifier(PadInput.none),
      color: palette.arcade,
    );
    // Kept live rather than only set at construction: under `ThemeMode.system`
    // the device can switch brightness while this screen stays open, and
    // `InvadersGame` is built once but this widget can rebuild many times.
    game.color = palette.arcade;

    // `padSide` alone is watched rather than read with the rest of `_profile`
    // at start: it is the one option `OnScreenPad` draws from on every
    // build, so a child who swaps hands from the settings screen and comes
    // straight back sees it change, where `arcadeEasyMode` and
    // `arcadeAutoFire` only ever mattered at the moment this run's `sim` was
    // built.
    final padSide = ref.watch(activeProfileProvider).padSide;

    return GameShell(
      controller: game,
      title: 'Invaders',
      gameId: invadersGameId,
      repository: _repository,
      padSide: padSide,
    );
  }
}
