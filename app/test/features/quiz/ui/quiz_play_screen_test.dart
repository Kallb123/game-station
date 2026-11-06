// The quiz play screen, driven through the real app (`PLAN-phase-10-quiz.md`
// §4.5-§4.7): a whole round, the locked state, quitting, sound and haptics,
// and starting again.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/audio/providers.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_codec.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/ui/quiz_play_screen.dart';
import 'package:zibo_games/features/quiz/ui/quiz_style.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../../../core/audio/recording_audio.dart';
import '../../../core/recording_haptics.dart';
import '../quiz_fixtures.dart';

final _fixed = DateTime.utc(2026, 8, 12, 9);

SaveData _saveKnowing(Set<String> known) {
  final save = freshSave();
  final profile = save.profiles.first;
  return save.copyWith(
    profiles: [profile.copyWith(quiz: QuizProgress(known: known))],
  );
}

class _Run {
  _Run(this.container, this.store);
  final ProviderContainer container;
  final MemorySaveStore store;

  QuizProgress get saved => decodeSave(store.contents!).profiles.first.quiz;
}

Future<_Run> _open(
  WidgetTester tester,
  QuizPlayArgs args, {
  Set<String> known = const {},
  RecordingAudio? audio,
  RecordingHaptics? haptics,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = MemorySaveStore(initial: _saveKnowing(known));
  final container = await pumpApp(
    tester,
    store: store,
    overrides: [
      quizCatalogProvider.overrideWithValue(fixtureCatalog()),
      nowProvider.overrideWithValue(() => _fixed),
      if (audio != null) appAudioProvider.overrideWithValue(audio),
      if (haptics != null) appHapticsProvider.overrideWithValue(haptics),
    ],
  );
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed(AppRoutes.quizPlay, arguments: args),
  );
  await tester.pumpAndSettle();
  return _Run(container, store);
}

/// The visible question's number and title, read off its text
/// (`Q 7 of dahl.bfg`), which is how the fixture builds them.
(int, String) _shown(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .firstWhere((s) => RegExp(r'^Q \d+ of ').hasMatch(s));
  final m = RegExp(r'^Q (\d+) of (.+)$').firstMatch(text)!;
  return (int.parse(m[1]!), m[2]!);
}

Finder _right(WidgetTester tester) => find.text('A ${_shown(tester).$1}');
Finder _wrong(WidgetTester tester) => find.text('W ${_shown(tester).$1} a');

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

/// Answers all ten, right where [rightAt] says so, and taps Next each time.
/// Stops with the last answered but Finish not yet tapped.
Future<void> _playTen(WidgetTester tester, bool Function(int i) rightAt) async {
  for (var i = 0; i < 10; i++) {
    await tester.tap(rightAt(i) ? _right(tester) : _wrong(tester));
    await _settle(tester);
    if (i < 9) {
      await tester.tap(find.text(nextLabel));
      await _settle(tester);
    }
  }
}

void main() {
  testWidgets('a single-title round reaches the card and is saved', (
    tester,
  ) async {
    final run = await _open(tester, const QuizPlayArgs.title(narniaId));
    bool rightAt(int i) => i.isEven || i == 7; // 6 right.
    await _playTen(tester, rightAt);

    expect(find.text(finishLabel), findsOneWidget);
    await tester.tap(find.text(finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('6 out of 10'), findsOneWidget);
    expect(find.text(playAgainLabel), findsOneWidget);
    expect(find.text(backToQuizLabel), findsOneWidget);

    await run.container.read(progressRepositoryProvider).flush();
    final title = run.saved.titles[narniaId]!;
    expect(title.rounds, 1);
    expect(title.best, 6);
    expect(title.next, 10);
    expect(run.saved.mixed.rounds, 0);
  });

  testWidgets(
    'a mixed round over ticked titles reaches the card and is saved',
    (tester) async {
      final run = await _open(
        tester,
        const QuizPlayArgs.mixed(),
        known: {narniaId, ...dahlIds},
      );
      await _playTen(tester, (i) => i < 9); // 9 right.
      await tester.tap(find.text(finishLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('9 out of 10'), findsOneWidget);

      await run.container.read(progressRepositoryProvider).flush();
      expect(run.saved.mixed.rounds, 1);
      expect(run.saved.mixed.best, 9);
      // Ten questions were drawn across the shelf, so some title advanced.
      expect(run.saved.titles, isNotEmpty);
      expect(run.saved.titles.values.fold<int>(0, (n, t) => n + t.next), 10);
    },
  );

  testWidgets('an answered question is locked and Next appears', (
    tester,
  ) async {
    await _open(tester, const QuizPlayArgs.title(narniaId));
    expect(find.text(nextLabel), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.tap(_wrong(tester));
    await _settle(tester);
    final (n, _) = _shown(tester);
    expect(find.text(nextLabel), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // A second tap, on the right answer, changes nothing.
    await tester.tap(find.text('A $n'));
    await _settle(tester);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.bySemanticsLabel('A $n, right answer'), findsOneWidget);

    // The wrong choice keeps its error colour once locked.
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('W $n a'), matching: find.byType(Material))
          .first,
    );
    final colors = Theme.of(tester.element(find.text('W $n a'))).colorScheme;
    expect(material.color, colors.errorContainer);

    await tester.tap(find.text(nextLabel));
    await _settle(tester);
    expect(find.text(nextLabel), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('quitting after three answers saves the place but not the score', (
    tester,
  ) async {
    final run = await _open(tester, const QuizPlayArgs.title(narniaId));
    for (var i = 0; i < 3; i++) {
      await tester.tap(_right(tester));
      await _settle(tester);
      await tester.tap(find.text(nextLabel));
      await _settle(tester);
    }
    // The third was followed by Next, so three are answered and a fourth shown.
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.text(quizQuitTitle), findsOneWidget);

    await tester.tap(find.text(quizKeepPlayingLabel));
    await _settle(tester);
    expect(find.byType(QuizPlayScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    await tester.tap(find.text(quizStopLabel));
    await _settle(tester);
    expect(find.byType(QuizPlayScreen), findsNothing);

    await run.container.read(progressRepositoryProvider).flush();
    final title = run.saved.titles[narniaId]!;
    expect(title.next, 3);
    expect(title.rounds, 0);
    expect(title.best, 0);
  });

  testWidgets('back with nothing answered leaves without asking', (
    tester,
  ) async {
    await _open(tester, const QuizPlayArgs.title(narniaId));
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.text(quizQuitTitle), findsNothing);
    expect(find.byType(QuizPlayScreen), findsNothing);
  });

  testWidgets('right and wrong answers and the finish sound and buzz as '
      'planned', (tester) async {
    final audio = RecordingAudio();
    final haptics = RecordingHaptics();
    await _open(
      tester,
      const QuizPlayArgs.title(narniaId),
      audio: audio,
      haptics: haptics,
    );
    expect(
      audio.preloaded,
      containsAll([
        Motif.sudokuCorrect,
        Motif.sudokuWrong,
        Motif.sudokuComplete,
      ]),
    );

    await tester.tap(_right(tester));
    await _settle(tester);
    expect(audio.played, [Motif.sudokuCorrect]);
    expect(haptics.calls, ['tap']);

    await tester.tap(find.text(nextLabel));
    await _settle(tester);
    await tester.tap(_wrong(tester));
    await _settle(tester);
    expect(audio.played, [Motif.sudokuCorrect, Motif.sudokuWrong]);
    expect(audio.gains.last, 0.5);
    expect(haptics.calls, ['tap'], reason: 'no buzz for a wrong answer');

    await tester.tap(find.text(nextLabel));
    await _settle(tester);
    for (var i = 2; i < 10; i++) {
      await tester.tap(_right(tester));
      await _settle(tester);
      if (i < 9) {
        await tester.tap(find.text(nextLabel));
        await _settle(tester);
      }
    }
    await tester.tap(find.text(finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(audio.played.last, Motif.sudokuComplete);
  });

  testWidgets('Play again starts a fresh round of the same kind', (
    tester,
  ) async {
    final run = await _open(tester, const QuizPlayArgs.title(narniaId));
    await _playTen(tester, (_) => true);
    await tester.tap(find.text(finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('10 out of 10'), findsOneWidget);

    await tester.tap(find.text(playAgainLabel));
    await _settle(tester);
    expect(find.text('10 out of 10'), findsNothing);
    expect(find.text(nextLabel), findsNothing);
    expect(_shown(tester).$2, narniaId);

    // Replaced, not stacked: one Back leaves the quiz play route.
    await run.container.read(progressRepositoryProvider).flush();
    expect(run.saved.titles[narniaId]!.rounds, 1);
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(find.byType(QuizPlayScreen), findsNothing);
  });

  testWidgets('a mixed round with nothing ticked shows a gentle line', (
    tester,
  ) async {
    await _open(tester, const QuizPlayArgs.mixed());
    expect(find.text(nothingToAskMessage), findsOneWidget);
    await tester.tap(find.text(backToQuizLabel));
    await _settle(tester);
    expect(find.byType(QuizPlayScreen), findsNothing);
  });
}
