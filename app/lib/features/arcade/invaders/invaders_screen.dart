// `/arcade/invaders` (`PLAN-phase-4.md` §6, PR 4 and PR 5), reachable for now
// from a temporary button on `/arcade` that PR 7 deletes once the real menu
// card exists (`arcade_menu_screen.dart`).
//
// The field and `OnScreenPad` sit in a `Column`, the composition
// `GameShell` (PR 6) will own once it exists — until then this screen does it
// directly, the way it stood in for `GameShell` at PR 4 too. The keyboard
// mirror hides the pad on its first key and this screen's `Listener` over the
// field brings it back on the next touch (`PLAN-phase-4.md` §4.6): a
// touchscreen PC gets both.
//
// This screen does not yet write anything to the save (`recordArcadeResult`
// is `GameShell`'s, PR 6) and does not yet offer easy mode or auto-fire
// (the arcade menu's toggles, PR 7): it always starts one normal-mode run.
// `padSide` is read from the active profile even so, since PR 1 already
// stores it and a hard-coded side would be a regression the moment PR 7 wires
// the toggle that changes it.

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/storage/providers.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../shared/on_screen_pad.dart';
import '../shared/pad_input.dart';
import 'invaders_game.dart';
import 'model/invaders_rules.dart';
import 'model/invaders_sim.dart';

class InvadersScreen extends ConsumerStatefulWidget {
  const InvadersScreen({super.key});

  @override
  ConsumerState<InvadersScreen> createState() => _InvadersScreenState();
}

class _InvadersScreenState extends ConsumerState<InvadersScreen> {
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<PadInput> _input = ValueNotifier(PadInput.none);
  final ValueNotifier<bool> _padVisible = ValueNotifier(true);
  late final PadKeyboardMirror _keyboard = PadKeyboardMirror(
    input: _input,
    padVisible: _padVisible,
  );

  late final InvadersSim _sim;
  InvadersGame? _game;

  @override
  void initState() {
    super.initState();
    final now = ref.read(nowProvider)();
    final seed = now.millisecondsSinceEpoch & 0xFFFFFFFF;
    _sim = InvadersSim(rules: InvadersRules.normal, seed: seed);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _input.dispose();
    _padVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(Theme.of(context).brightness);
    final game = _game ??= InvadersGame(
      sim: _sim,
      input: _input,
      color: palette.arcade,
    );
    // Kept live rather than only set at construction: under `ThemeMode.system`
    // the device can switch brightness while this screen stays open, and
    // `InvadersGame` is built once but this widget can rebuild many times.
    game.color = palette.arcade;

    final padSide = ref.watch(activeProfileProvider).padSide;

    return ScreenScaffold(
      title: 'Invaders',
      child: Column(
        children: [
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _keyboard.handleKey,
              // `GameWidget` requests its own focus by default
              // (`autofocus: true`), which would win it away from the `Focus`
              // above the moment this screen builds — leaving the keyboard
              // mirror never called. Declining that here is what lets the
              // outer node keep it.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _padVisible.value = true,
                child: GameWidget(game: game, autofocus: false),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _padVisible,
            builder: (context, visible, _) => visible
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: OnScreenPad(input: _input, side: padSide),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
