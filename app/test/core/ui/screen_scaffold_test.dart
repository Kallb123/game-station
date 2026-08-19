import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/screen_scaffold.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('shows its title and content', (tester) async {
    await pumpApp(
      tester,
      const ScreenScaffold(title: 'Settings', child: Text('body')),
      theme: AppTheme.day(),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('hides the back control when there is nothing to pop', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const ScreenScaffold(title: 'Home', child: SizedBox.shrink()),
      theme: AppTheme.day(),
    );

    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  // `canPop` answers for whatever the navigator's stack looks like when this
  // widget happens to rebuild, which is not necessarily "just now" — the home
  // screen can sit mounted underneath another route and be rebuilt by an
  // unrelated provider change while that route makes `canPop` true, then
  // never rebuild again once the route above is popped and the honest answer
  // goes back to false (`screen_scaffold.dart`). `hideBack` is the home
  // screen's way out of that: it must hide the control even where `canPop`
  // alone would show it.
  testWidgets(
    'hideBack hides the control even where there is something to pop',
    (tester) async {
      await pumpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScreenScaffold(
                      title: 'Home',
                      hideBack: true,
                      child: SizedBox.shrink(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        theme: AppTheme.day(),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    },
  );

  testWidgets('pops the route when the back control is used', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ScreenScaffold(
                    title: 'Profiles',
                    child: SizedBox.shrink(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      theme: AppTheme.day(),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsNothing);
  });

  testWidgets('the back control meets the tap-target floor', (tester) async {
    await pumpApp(
      tester,
      ScreenScaffold(
        title: 'Profiles',
        onBack: () {},
        child: const SizedBox.shrink(),
      ),
      theme: AppTheme.day(),
    );

    final size = tester.getSize(find.byType(IconButton));
    expect(size.height, greaterThanOrEqualTo(AppTapTargets.min));
    expect(size.width, greaterThanOrEqualTo(AppTapTargets.min));
  });

  testWidgets('shows its actions', (tester) async {
    await pumpApp(
      tester,
      ScreenScaffold(
        title: 'Home',
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
        ],
        child: const SizedBox.shrink(),
      ),
      theme: AppTheme.day(),
    );

    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  // PLAN.md §4.2: nothing goes under a notch, a home indicator or a gesture
  // bar. Losing the `SafeArea` is the kind of change that looks fine on the
  // reviewer's device and hides a control on someone else's.
  testWidgets('keeps its content out of the system insets', (tester) async {
    const insets = EdgeInsets.only(top: 44, bottom: 34);
    await pumpApp(
      tester,
      const ScreenScaffold(title: 'Home', child: SizedBox.shrink()),
      theme: AppTheme.day(),
      padding: insets,
    );

    expect(
      tester.getTopLeft(find.text('Home')).dy,
      greaterThanOrEqualTo(insets.top),
    );
  });

  // The reason this is not an AppBar: a 56 dp bar clips a 40 dp title at 200%
  // scale, and there is no way to ask it to grow. This header grows to two
  // lines instead — and stops there, so it cannot push the screen's content
  // off the bottom either.
  testWidgets('the header grows rather than overflowing at 200% text scale', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await pumpApp(
      tester,
      ScreenScaffold(
        title: 'Profiles',
        onBack: () {},
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
        ],
        child: const SizedBox.shrink(),
      ),
      theme: AppTheme.day(),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Profiles'), findsOneWidget);
  });

  testWidgets('a title too long to fit does not push the content away', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await pumpApp(
      tester,
      ScreenScaffold(
        title: 'Who is playing on this tablet today, and for how long?',
        onBack: () {},
        child: const Text('body'),
      ),
      theme: AppTheme.day(),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('body'), findsOneWidget);
  });
}
