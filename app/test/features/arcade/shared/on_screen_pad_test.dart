// `OnScreenPad`'s own rules (`PLAN-phase-4.md` §1, §4.6): move and fire
// together from two fingers, a slide leaving LEFT held, `onPointerCancel`
// leaving LEFT held, a second finger on FIRE never touching LEFT's state, the
// 72 dp floor, the handedness swap, and clearing a bottom safe-area inset.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/save_data.dart' show PadSide;
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

import '../../../core/recording_haptics.dart';
import '../../../core/ui/ui_harness.dart';

void main() {
  /// Pumps [OnScreenPad] at the bottom of a [SafeArea], the way the play
  /// screen places it, and returns the notifier it writes to.
  Future<ValueNotifier<PadInput>> pumpPad(
    WidgetTester tester, {
    PadSide side = PadSide.right,
    EdgeInsets padding = EdgeInsets.zero,
    AppHaptics haptics = const SilentHaptics(),
  }) async {
    final input = ValueNotifier(PadInput.none);
    addTearDown(input.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: OnScreenPad(input: input, side: side, haptics: haptics),
          ),
        ),
      ),
      theme: AppTheme.day(),
      padding: padding,
    );
    return input;
  }

  final left = find.byKey(OnScreenPad.leftKey);
  final right = find.byKey(OnScreenPad.rightKey);
  final fire = find.byKey(OnScreenPad.fireKey);

  testWidgets('two fingers move and fire in the same frame', (tester) async {
    final input = await pumpPad(tester);

    final leftFinger = await tester.startGesture(tester.getCenter(left));
    final fireFinger = await tester.startGesture(tester.getCenter(fire));
    await tester.pump();

    expect(input.value.left, isTrue);
    expect(input.value.fire, isTrue);
    expect(input.value.right, isFalse);

    await leftFinger.up();
    await fireFinger.up();
  });

  testWidgets('a pointer that slides off LEFT clears it', (tester) async {
    final input = await pumpPad(tester);

    final gesture = await tester.startGesture(tester.getCenter(left));
    await tester.pump();
    expect(input.value.left, isTrue);

    // Flutter keeps routing moves to whichever widget the pointer went down
    // on, wherever it slides to (`PLAN-phase-4.md` §1) — the top-left corner
    // is outside every button in this layout.
    await gesture.moveTo(Offset.zero);
    await tester.pump();

    expect(input.value.left, isFalse);
  });

  testWidgets('onPointerCancel clears LEFT', (tester) async {
    final input = await pumpPad(tester);

    final gesture = await tester.startGesture(tester.getCenter(left));
    await tester.pump();
    expect(input.value.left, isTrue);

    await gesture.cancel();

    expect(input.value.left, isFalse);
  });

  testWidgets('a second finger on FIRE does not release LEFT', (tester) async {
    final input = await pumpPad(tester);

    final leftFinger = await tester.startGesture(tester.getCenter(left));
    await tester.pump();
    final fireFinger = await tester.startGesture(tester.getCenter(fire));
    await tester.pump();

    await fireFinger.up();
    await tester.pump();

    expect(
      input.value.left,
      isTrue,
      reason: 'releasing FIRE must not touch LEFT',
    );
    expect(input.value.fire, isFalse);

    await leftFinger.up();
  });

  testWidgets('a press buzzes once; the release does not double it', (
    tester,
  ) async {
    final haptics = RecordingHaptics();
    final input = await pumpPad(tester, haptics: haptics);

    final gesture = await tester.startGesture(tester.getCenter(left));
    await tester.pump();
    expect(haptics.calls, ['selectionClick']);

    await gesture.up();
    await tester.pump();
    expect(haptics.calls, [
      'selectionClick',
    ], reason: 'a release must not double the press buzz');
    expect(input.value.left, isFalse);
  });

  testWidgets('every button clears the 72 dp floor', (tester) async {
    await pumpPad(tester);

    for (final button in [left, right, fire]) {
      expect(
        tester.getSize(button).shortestSide,
        greaterThanOrEqualTo(AppTapTargets.primary),
        reason: '$button',
      );
    }
  });

  testWidgets('padSide.left puts FIRE on the left of LEFT and RIGHT', (
    tester,
  ) async {
    await pumpPad(tester, side: PadSide.left);

    expect(tester.getCenter(fire).dx, lessThan(tester.getCenter(left).dx));
  });

  testWidgets(
    'movement and FIRE sit at opposite edges, not side by side in the middle',
    (tester) async {
      // A `Row` sizes to its content by default — without a full-width
      // wrapper this regresses to both groups sitting together in the middle
      // of the screen, which the dx-ordering check above would not catch.
      await usePhoneSurface(tester);
      await pumpPad(tester);

      final screenWidth = tester.getSize(find.byType(Scaffold)).width;

      expect(tester.getCenter(left).dx, lessThan(screenWidth * 0.25));
      expect(tester.getCenter(fire).dx, greaterThan(screenWidth * 0.75));
    },
  );

  testWidgets('no button intersects a 34 dp bottom safe-area inset', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await pumpPad(tester, padding: const EdgeInsets.only(bottom: 34));

    for (final button in [left, right, fire]) {
      expect(
        tester.getBottomLeft(button).dy,
        lessThanOrEqualTo(640 - 34),
        reason: '$button',
      );
    }
  });
}
