// `/arcade/invaders` (`PLAN-phase-4.md` §6, PR 4): a `GameWidget` over
// `InvadersGame`, reachable for now from a temporary button on `/arcade`
// that PR 7 deletes once the real menu card exists (`arcade_menu_screen.dart`).
//
// Input here is a keyboard-only stand-in for `OnScreenPad` and its keyboard
// mirror, both PR 5 (`PLAN-phase-4.md` §4.6): arrows or A/D to move, space to
// fire. It drives `InvadersGame` through the same `PadInput` the pad will
// use, so nothing here changes when PR 5 lands — only this screen's `Focus`
// handling is replaced by the shared widget.
//
// This screen does not yet write anything to the save (`recordArcadeResult`
// is `GameShell`'s, PR 6) and does not yet offer easy mode or auto-fire
// (the arcade menu's toggles, PR 7): it always starts one normal-mode run.

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../shared/pad_input.dart';
import 'invaders_game.dart';
import 'model/invaders_rules.dart';
import 'model/invaders_sim.dart';

/// The keys this screen's temporary keyboard handling answers to.
///
/// Not `const`: `LogicalKeyboardKey` overrides `==`, which the analyzer
/// refuses in a const set literal.
final Set<LogicalKeyboardKey> _leftKeys = {
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.keyA,
};
final Set<LogicalKeyboardKey> _rightKeys = {
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.keyD,
};
final Set<LogicalKeyboardKey> _fireKeys = {LogicalKeyboardKey.space};

class InvadersScreen extends ConsumerStatefulWidget {
  const InvadersScreen({super.key});

  @override
  ConsumerState<InvadersScreen> createState() => _InvadersScreenState();
}

class _InvadersScreenState extends ConsumerState<InvadersScreen> {
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<PadInput> _input = ValueNotifier(PadInput.none);

  late final InvadersSim _sim;
  InvadersGame? _game;

  bool _left = false;
  bool _right = false;
  bool _fire = false;

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
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final matched =
        _leftKeys.contains(key) ||
        _rightKeys.contains(key) ||
        _fireKeys.contains(key);
    if (!matched) return KeyEventResult.ignored;

    final held = event is! KeyUpEvent;
    if (_leftKeys.contains(key)) _left = held;
    if (_rightKeys.contains(key)) _right = held;
    if (_fireKeys.contains(key)) _fire = held;
    _input.value = PadInput(left: _left, right: _right, fire: _fire);
    return KeyEventResult.handled;
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

    return ScreenScaffold(
      title: 'Invaders',
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        // `GameWidget` requests its own focus by default (`autofocus: true`),
        // which would win it away from the `Focus` above the moment this
        // screen builds — leaving `_handleKey` never called. Declining that
        // here is what lets the outer node keep it.
        child: GameWidget(game: game, autofocus: false),
      ),
    );
  }
}
