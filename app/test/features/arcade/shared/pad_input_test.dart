// `PadKeyboardMirror`'s own rules (`PLAN-phase-4.md` §4.6,
// `PLAN-phase-7-snake.md` §4.6): arrows or WASD hold the four directions,
// space holds fire, several directions can be held together, an unmapped key
// is ignored, and the first key it handles hides the pad.
//
// `OnScreenPad`'s own multi-touch and safe-area rules are
// `on_screen_pad_test.dart`'s; `invaders_screen_test.dart` covers the
// hide-on-keyboard, show-on-touch cycle end to end through a real screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

void main() {
  late ValueNotifier<PadInput> input;
  late ValueNotifier<bool> padVisible;
  late PadKeyboardMirror mirror;

  Future<void> pumpMirror(WidgetTester tester) async {
    input = ValueNotifier(PadInput.none);
    padVisible = ValueNotifier(true);
    mirror = PadKeyboardMirror(input: input, padVisible: padVisible);
    addTearDown(input.dispose);
    addTearDown(padVisible.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: mirror.handleKey,
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('arrow keys and WASD hold the matching direction', (
    tester,
  ) async {
    await pumpMirror(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    expect(input.value.left, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(input.value.left, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    expect(input.value.right, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(input.value.right, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(input.value.fire, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(input.value.fire, isFalse);
  });

  testWidgets('arrow keys and WS hold up and down', (tester) async {
    await pumpMirror(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    expect(input.value.up, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    expect(input.value.up, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    expect(input.value.down, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    expect(input.value.down, isFalse);
  });

  testWidgets('holding two directions reports both at once', (tester) async {
    await pumpMirror(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);

    expect(input.value.left, isTrue);
    expect(input.value.right, isTrue);
  });

  testWidgets('four directions can all be held at once', (tester) async {
    await pumpMirror(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);

    expect(input.value.up, isTrue);
    expect(input.value.down, isTrue);
    expect(input.value.left, isTrue);
    expect(input.value.right, isTrue);
  });

  testWidgets('an unmapped key is ignored', (tester) async {
    await pumpMirror(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);

    expect(input.value.left, isFalse);
    expect(input.value.right, isFalse);
    expect(input.value.fire, isFalse);
  });

  testWidgets('the first handled key hides the pad', (tester) async {
    await pumpMirror(tester);
    expect(padVisible.value, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);

    expect(padVisible.value, isFalse);
  });
}
