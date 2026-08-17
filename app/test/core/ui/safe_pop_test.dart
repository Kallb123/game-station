import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/safe_pop.dart';

void main() {
  testWidgets('does nothing where there is nothing to pop', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (innerContext) {
            context = innerContext;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );

    // A raw `Navigator.of(context).pop()` here removes the app's only route
    // and throws nothing — the screen just goes blank, which is the bug this
    // guards against (`screen_scaffold.dart`, `sudoku_play_screen.dart`,
    // `game_shell.dart` all route their back controls through this rather
    // than popping directly).
    popIfPossible(context);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('pops exactly once however many times it is called', (
    tester,
  ) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            rootContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );

    unawaited(
      Navigator.of(
        rootContext,
      ).push(MaterialPageRoute<void>(builder: (_) => const Text('pushed'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('pushed'), findsOneWidget);

    final pushedContext = tester.element(find.text('pushed'));
    // A second call once the route is already gone — the case a stray extra
    // tap or a second input reaching the same handler would produce — must
    // not reach past the route it already popped.
    popIfPossible(pushedContext);
    popIfPossible(pushedContext);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);
  });
}
