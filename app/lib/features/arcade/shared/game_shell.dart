// The widget every arcade game plays inside (`PLAN-phase-4.md` §4.8): the
// HUD, pause, quit confirmation, the game-over card and the write to the
// save. `InvadersScreen` composes one `ArcadeGameController` and hands it
// here; a later game under `PLAN.md` §4.4 does the same and touches this
// file only if it needs a ninth member `ArcadeGameController` does not have.
//
// **Not `ScreenScaffold`**, the same measured exception the Sudoku play
// screen took (`PLAN-phase-3.md` §4.5): a 40 dp display heading costs a slice
// of a field that already gives up height to a 72 dp control pad below it.
// The frame keeps the same `SafeArea`, the same back control and the same
// tooltip, with the game's name moved into the header row beside the score.
//
// **Resuming from the background is not automatic.** `AppLifecycleListener`
// pauses on `inactive`/`paused` the way it always would, but coming back to
// `resumed` leaves the game paused rather than continuing it: a shooter that
// started moving aliens again the instant a tablet unlocked would drop the
// player back into the game before they had looked at the screen. The paused
// card is what they see either way, and *Resume* is the same explicit tap
// whether the pause came from backgrounding or from the button.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/save_data.dart' show HighScore, PadSide;
import '../../../core/ui/big_button.dart';
import '../../../core/ui/tokens.dart';
import 'arcade_controller.dart';
import 'on_screen_pad.dart';
import 'pad_input.dart';

/// What the paused card says. Public because the tests name the same string.
const String pausedTitle = 'Paused';

/// What the quit confirmation asks, and its two ways on
/// (`PLAN-phase-4.md` §4.8).
const String quitConfirmTitle = 'Stop playing?';
const String quitKeepPlayingLabel = 'Keep playing';
const String quitStopLabel = 'Stop';

/// What the game-over card says at the top (`PLAN.md` §4.1) — never "GAME
/// OVER", which is not a sentence a failure-averse child needs to read.
const String gameOverTitle = 'Good try! Play again?';

/// Shown in place of a top-five table with nothing in it yet.
const String noScoresYetMessage = 'No scores yet — have a go!';

/// The two ways on from the game-over card.
const String playAgainLabel = 'Play again';
const String backLabel = 'Back';

/// Wraps one [ArcadeGameController] with the shell every arcade game shares.
class GameShell extends StatefulWidget {
  const GameShell({
    required this.controller,
    required this.title,
    required this.gameId,
    required this.repository,
    required this.padSide,
    super.key,
  });

  /// The game being played.
  final ArcadeGameController controller;

  /// The game's name, shown in the header row.
  final String title;

  /// The key [ProgressRepository.recordArcadeResult] stores this game's
  /// progress under — `"invaders"` for the first one.
  final String gameId;

  /// Where a run's start and end are written.
  final ProgressRepository repository;

  /// Which side FIRE sits on, from the active profile.
  final PadSide padSide;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<bool> _padVisible = ValueNotifier(true);
  late final PadKeyboardMirror _keyboard = PadKeyboardMirror(
    input: widget.controller.input,
    padVisible: _padVisible,
  );
  late final AppLifecycleListener _lifecycle;

  bool _paused = false;

  /// Whether this run's [ArcadeGameController.result] has already been
  /// written. Set on game over and on a confirmed quit alike, and cleared by
  /// [_restart] — without it, a rebuild between game over and the next tap
  /// would write the same run twice.
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame rather than called here directly: `initState` runs
    // while Riverpod's `ProgressRepository` provider is still building the
    // tree beneath it, and a provider refuses a mutation made during its own
    // build for the same reason `sudoku_play_screen.dart`'s last save
    // belongs to the pop rather than to `dispose` — two widgets in the same
    // frame must not see different states.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.repository.startArcadeGame(widget.gameId);
    });
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
    widget.controller.isOver.addListener(_onGameOverChanged);
  }

  @override
  void dispose() {
    widget.controller.isOver.removeListener(_onGameOverChanged);
    _lifecycle.dispose();
    _focusNode.dispose();
    _padVisible.dispose();
    super.dispose();
  }

  void _onGameOverChanged() {
    if (!widget.controller.isOver.value) return;
    _record();
    if (mounted) setState(() {});
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _setPaused(true);
  }

  void _setPaused(bool value) {
    if (_paused == value) return;
    setState(() => _paused = value);
    if (value) {
      widget.controller.pause();
    } else {
      widget.controller.resume();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.escape)) {
      _setPaused(!_paused);
      return KeyEventResult.handled;
    }
    return _keyboard.handleKey(node, event);
  }

  /// Writes the run so far, once. A zero-point run is dropped by
  /// [ProgressRepository.recordArcadeResult] itself, so nothing here needs to
  /// check the score first.
  void _record() {
    if (_recorded) return;
    _recorded = true;
    widget.repository.recordArcadeResult(
      widget.gameId,
      widget.controller.result,
    );
    if (!widget.repository.isDisposed) unawaited(widget.repository.flush());
  }

  Future<void> _confirmQuit() async {
    // The run already ended and was written by [_onGameOverChanged]; leaving
    // the game-over card is not a run being abandoned, so it needs no
    // confirmation.
    if (widget.controller.isOver.value) {
      Navigator.of(context).pop();
      return;
    }

    final wasPaused = _paused;
    _setPaused(true);
    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(quitConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(quitKeepPlayingLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(quitStopLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (shouldQuit ?? false) {
      _record();
      Navigator.of(context).pop();
      return;
    }
    _setPaused(wasPaused);
  }

  void _restart() {
    widget.repository.startArcadeGame(widget.gameId);
    setState(() {
      _recorded = false;
      _paused = false;
    });
    widget.controller.restart();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmQuit());
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(theme),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _body(theme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final isOver = widget.controller.isOver.value;

    // The HUD gets its own row, full width, rather than squeezing in beside
    // the title and the two icon buttons: "Score 12340   ♥♥♥ 3   Wave 7" is
    // long enough that sharing a row with them overflows well before 200%
    // text scale does anything to the title.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _confirmQuit,
              icon: const Icon(Icons.arrow_back, size: AppIconSizes.large),
              tooltip: 'Back',
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              onPressed: isOver ? null : () => _setPaused(!_paused),
              icon: Icon(
                _paused ? Icons.play_arrow : Icons.pause,
                size: AppIconSizes.large,
              ),
              tooltip: _paused ? 'Resume' : 'Pause',
            ),
          ],
        ),
        ValueListenableBuilder<ArcadeHud>(
          valueListenable: widget.controller.hud,
          builder: (context, hud, _) => _HudText(hud: hud),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    final isOver = widget.controller.isOver.value;
    final blocked = _paused || isOver;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: _handleKey,
                // `GameWidget` requests its own focus by default, which
                // would win it away from the node above the moment this
                // screen builds — declining that in `InvadersGame.buildView`
                // is what lets this one keep it (`invaders_screen.dart`'s PR
                // 4/5 comment recorded the same reasoning).
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _padVisible.value = true,
                  child: widget.controller.buildView(context),
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _padVisible,
              builder: (context, visible, _) => visible
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: OnScreenPad(
                        input: widget.controller.input,
                        side: widget.padSide,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        // Sits over the field and the pad alike, the same reason phase 3's
        // completion card has one (`PLAN-phase-3.md` §4.6): a tap reaching
        // FIRE behind a paused or finished game would drive a run the player
        // can no longer see.
        if (blocked) ...[
          ModalBarrier(
            color: theme.colorScheme.scrim.withValues(alpha: 0.4),
            dismissible: false,
          ),
          isOver ? _gameOverCard(theme) : _pausedCard(theme),
        ],
      ],
    );
  }

  Widget _pausedCard(ThemeData theme) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(pausedTitle, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: AppSpacing.lg),
            BigButton(
              icon: Icons.play_arrow,
              label: 'Resume',
              onPressed: () => _setPaused(false),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _gameOverCard(ThemeData theme) {
    final result = widget.controller.result;
    final scores =
        widget.repository.activeProfile.arcade.games[widget.gameId]?.highScores
            .where((score) => score.easy == result.easy)
            .toList() ??
        const <HighScore>[];

    return Center(
      // Scrolls rather than clips, the same reason the completion card does
      // (`PLAN-phase-3.md` §4.6): a title, two numbers, five scores and two
      // buttons are taller than a small phone at 200% text scale.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      gameOverTitle,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Score ${result.score} · Wave ${result.wave}',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (scores.isEmpty)
                    Text(
                      noScoresYetMessage,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    )
                  else
                    for (var i = 0; i < scores.length; i++)
                      Text(
                        '${i + 1}. ${scores[i].score}',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                  const SizedBox(height: AppSpacing.xl),
                  BigButton(
                    icon: Icons.replay,
                    label: playAgainLabel,
                    onPressed: _restart,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  BigButton(
                    icon: Icons.arrow_back,
                    label: backLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Score, lives and wave, merged into one line a screen reader says as one
/// thing rather than three (`PLAN.md` §4.3's HUD, `PLAN-phase-4.md` §4.8).
///
/// Lives are drawn as glyphs *and* a number: a count that is only a row of
/// icons is unreadable at a glance past four (`PLAN-phase-4.md` §4.8).
class _HudText extends StatelessWidget {
  const _HudText({required this.hud});

  final ArcadeHud hud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lives = '♥' * hud.lives;

    return Semantics(
      label: 'Score ${hud.score}, ${hud.lives} lives, wave ${hud.wave}',
      child: ExcludeSemantics(
        child: Text(
          'Score ${hud.score}   $lives ${hud.lives}   Wave ${hud.wave}',
          style: theme.textTheme.bodyLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
