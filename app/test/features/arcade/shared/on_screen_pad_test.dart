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

  /// Pumps [OnScreenPad] in [Axis.vertical] beside [child], the way
  /// `GameShell` places it in landscape (`PLAN-phase-5.md` §4.8).
  Future<ValueNotifier<PadInput>> pumpVerticalPad(
    WidgetTester tester, {
    PadSide side = PadSide.right,
    Widget child = const ColoredBox(color: Color(0xFF000000)),
  }) async {
    final input = ValueNotifier(PadInput.none);
    addTearDown(input.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: SafeArea(
          child: OnScreenPad(
            input: input,
            side: side,
            haptics: const SilentHaptics(),
            axis: Axis.vertical,
            child: child,
          ),
        ),
      ),
      theme: AppTheme.day(),
    );
    return input;
  }

  /// Pumps [OnScreenPad] with [PadLayout.dPad], the way `GameShell` will once
  /// Snake wires it up (`PLAN-phase-7-snake.md` §4.6) — this file only checks
  /// the layout itself, since no game reaches it yet in this pull request.
  Future<ValueNotifier<PadInput>> pumpDPad(
    WidgetTester tester, {
    PadSide side = PadSide.right,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final input = ValueNotifier(PadInput.none);
    addTearDown(input.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: OnScreenPad(
              input: input,
              side: side,
              haptics: const SilentHaptics(),
              layout: PadLayout.dPad,
            ),
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
  final up = find.byKey(OnScreenPad.upKey);
  final down = find.byKey(OnScreenPad.downKey);

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
    expect(haptics.calls, ['tap']);

    await gesture.up();
    await tester.pump();
    expect(haptics.calls, [
      'tap',
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

  group('the vertical axis, beside a landscape field', () {
    testWidgets('every button still clears the 72 dp floor', (tester) async {
      // The tightest of the three sweep sizes (`PLAN-phase-5.md` §4.8) —
      // the one a fixed-size button most easily loses its floor on.
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpVerticalPad(tester);

      for (final button in [left, right, fire]) {
        expect(
          tester.getSize(button).shortestSide,
          greaterThanOrEqualTo(AppTapTargets.primary),
          reason: '$button',
        );
      }
    });

    testWidgets(
      'movement and FIRE sit at opposite edges, with the field between them',
      (tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpVerticalPad(tester);

        final screenWidth = tester.getSize(find.byType(Scaffold)).width;

        expect(tester.getCenter(left).dx, lessThan(screenWidth * 0.25));
        expect(tester.getCenter(fire).dx, greaterThan(screenWidth * 0.75));
      },
    );

    testWidgets('padSide.left puts FIRE on the left of LEFT and RIGHT', (
      tester,
    ) async {
      await pumpVerticalPad(tester, side: PadSide.left);

      expect(tester.getCenter(fire).dx, lessThan(tester.getCenter(left).dx));
    });
  });

  group('PadLayout.dPad', () {
    testWidgets('draws four 72 dp buttons and no FIRE', (tester) async {
      await pumpDPad(tester);

      expect(fire, findsNothing);
      for (final button in [up, down, left, right]) {
        expect(
          tester.getSize(button).shortestSide,
          greaterThanOrEqualTo(AppTapTargets.primary),
          reason: '$button',
        );
      }
    });

    testWidgets('each button releases on up, on cancel and on a move '
        'outside its bounds', (tester) async {
      final input = await pumpDPad(tester);

      final upGesture = await tester.startGesture(tester.getCenter(up));
      await tester.pump();
      expect(input.value.up, isTrue);
      await upGesture.up();
      await tester.pump();
      expect(input.value.up, isFalse, reason: 'released on pointer up');

      final downGesture = await tester.startGesture(tester.getCenter(down));
      await tester.pump();
      expect(input.value.down, isTrue);
      await downGesture.cancel();
      expect(input.value.down, isFalse, reason: 'released on pointer cancel');

      final leftGesture = await tester.startGesture(tester.getCenter(left));
      await tester.pump();
      expect(input.value.left, isTrue);
      await leftGesture.moveTo(Offset.zero);
      await tester.pump();
      expect(
        input.value.left,
        isFalse,
        reason: 'released on a move outside its bounds',
      );
    });

    testWidgets('two simultaneous pointers hold two directions at once', (
      tester,
    ) async {
      final input = await pumpDPad(tester);

      final upFinger = await tester.startGesture(tester.getCenter(up));
      final rightFinger = await tester.startGesture(tester.getCenter(right));
      await tester.pump();

      expect(input.value.up, isTrue);
      expect(input.value.right, isTrue);
      expect(input.value.down, isFalse);
      expect(input.value.left, isFalse);

      await upFinger.up();
      await rightFinger.up();
    });

    testWidgets(
      "a tap in the corner where Up's and Right's 72 dp squares overlap "
      'resolves to Up, not whichever button paints on top',
      (tester) async {
        // The compact diamond keeps the four drawn *circles* apart but not
        // their 72 dp bounding squares, which still overlap by design in
        // each adjacent pair's inward corner — without a hit-test clip
        // matching the drawn circle, a tap there would silently resolve to
        // whichever button is later in the underlying `Stack`, dropping the
        // turn a child actually pressed.
        final input = await pumpDPad(tester);

        // `_dPadReach` (52.92) minus half of `AppTapTargets.primary` (36) is
        // 16.92 dp, the exact corner where the two squares' boundaries meet
        // — on the edge itself, not reliably inside either square's
        // hit-test region. One more dp on each axis moves inside both
        // squares' interiors while staying inside Up's circle (about 25 dp
        // from its centre, against a 36 dp radius) and outside Right's
        // (about 50 dp from its centre).
        final probe = tester.getCenter(up) + const Offset(17.92, 17.92);

        final gesture = await tester.startGesture(probe);
        await tester.pump();
        expect(input.value.up, isTrue, reason: '$probe is inside Up\'s circle');
        expect(
          input.value.right,
          isFalse,
          reason: '$probe is outside Right\'s circle',
        );
        await gesture.up();
      },
    );

    testWidgets('no button intersects a 34 dp bottom safe-area inset', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpDPad(tester, padding: const EdgeInsets.only(bottom: 34));

      for (final button in [up, down, left, right]) {
        expect(
          tester.getBottomLeft(button).dy,
          lessThanOrEqualTo(640 - 34),
          reason: '$button',
        );
      }
    });

    testWidgets('the lateral layout is unchanged', (tester) async {
      // `layout` defaults to `PadLayout.lateral`, so a call site that never
      // heard of `PadLayout` still gets today's pad — the same assertion
      // `padSide.left puts FIRE on the left of LEFT and RIGHT` above makes,
      // repeated here explicitly against the default rather than a named
      // layout (`PLAN-phase-7-snake.md` §4.7's "nothing; the default is
      // today's pad").
      await pumpPad(tester);

      expect(find.byKey(OnScreenPad.fireKey), findsOneWidget);
      expect(find.byKey(OnScreenPad.upKey), findsNothing);
      expect(find.byKey(OnScreenPad.downKey), findsNothing);
    });
  });
}
