// The Tracks play screen's tests (`PLAN-phase-9-tracks.md` §6, PR 7): a puzzle
// driven to solved with simulated drags, the completion timeline with and
// without `reduceMotion`, the toolbar, the sounds, and the clock's save.
//
// Every board is played through the gesture arena (`tracks_play_harness.dart`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/audio/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/completion_card.dart';
import 'package:zibo_games/core/ui/confetti.dart';
import 'package:zibo_games/core/ui/puzzle_clock.dart';
import 'package:zibo_games/features/tracks/data/providers.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_record.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_source.dart';
import 'package:zibo_games/features/tracks/skins/journey.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board.dart';
import 'package:zibo_games/features/tracks/ui/tracks_play_screen.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../../../core/audio/recording_audio.dart';
import '../tracks_fixtures.dart';
import '../tracks_puzzle_fixtures.dart';
import 'tracks_play_harness.dart';

void main() {
  for (final id in [
    TracksPuzzleId.parse('tracks:5x5:easy:0'),
    TracksPuzzleId.parse('tracks:7x7:easy:0'),
  ]) {
    testWidgets('drags to solved on ${id.value} and shows the card', (
      tester,
    ) async {
      final container = await pumpTracks(tester, id: id);
      final repository = repositoryOf(container);

      await solveByDrag(tester, id);
      expect(sessionOf(tester).isSolved, isTrue);

      // The result is stored at the moment of solving, before the journey ends.
      final profile = repository.activeProfile;
      expect(profile.tracks.solved, contains(id.value));
      expect(profile.tracks.inProgress, isNot(contains(id.value)));
      expect(
        profile.tracks.bestTimeMs,
        contains(TracksProgress.bestTimeKey(id.spec, id.difficulty)),
        reason: 'a best time was recorded',
      );
      expect(find.text(completionTitle), findsNothing);

      await tester.pump();
      await tester.pump(journeyOf(tester) + const Duration(milliseconds: 100));
      expect(find.text(completionTitle), findsOneWidget);

      await finish(tester, container);
    });
  }

  testWidgets('with reduceMotion the card shows at once and no frame is '
      'scheduled', (tester) async {
    final container = await pumpTracks(
      tester,
      store: MemorySaveStore(
        initial: freshSave(settings: const AppSettings(reduceMotion: true)),
      ),
    );

    await solveByDrag(tester, smallPuzzle);
    await tester.pump();

    expect(find.text(completionTitle), findsOneWidget);
    expect(painterOf(tester).frame, JourneyFrame.arrived);
    // A further pump, then nothing left to draw: no ticker is running. The
    // clock is a timer, not a frame.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    final confetti = find.descendant(
      of: find.byType(Confetti),
      matching: find.byType(CustomPaint),
    );
    expect(confetti, findsNothing);

    await finish(tester, container);
  });

  testWidgets('mid-journey the traveller is part-way and a tap skips to the '
      'card', (tester) async {
    final container = await pumpTracks(tester);
    await solveByDrag(tester, smallPuzzle);

    final session = sessionOf(tester);
    final route = TrackGeometry.trace(session.clues, session.cells)!;
    final travel = travelDuration(painterOf(tester).skin, route);

    await tester.pump();
    await tester.pump(travel ~/ 2);
    final t = painterOf(tester).frame.t;
    expect(t, greaterThan(0));
    expect(t, lessThan(1));
    expect(find.text(completionTitle), findsNothing);

    await tester.tapAt(tester.getCenter(find.byType(TracksBoard)));
    await tester.pump();
    expect(find.text(completionTitle), findsOneWidget);
    expect(painterOf(tester).frame, JourneyFrame.arrived);

    await finish(tester, container);
  });

  testWidgets('nothing changes a solved board during the journey', (
    tester,
  ) async {
    // A goal cell that is not fixed, so the finishing connection into the
    // goal port is the child's own and a retrace could lift it.
    final puzzle = findPuzzle(
      (puzzle) => puzzle.clues.fixed[puzzle.clues.goalCell] == 0 ? true : null,
    ).puzzle;
    final container = await pumpTracks(tester, id: puzzle.id);
    final stroke = solutionStroke(puzzle);
    final side = puzzle.id.spec.side;

    // The finger reaches the goal port and comes straight back into the goal
    // cell before a frame is drawn, so the board has not yet been rebuilt as
    // not interactive: the retrace must still not lift the finishing
    // connection.
    final gesture = await tester.startGesture(
      positionOnScreen(tester, side, stroke.first),
    );
    for (final position in stroke.skip(1)) {
      await gesture.moveTo(positionOnScreen(tester, side, position));
      if (position != stroke.last) await tester.pump();
    }
    await gesture.moveTo(
      positionOnScreen(tester, side, stroke[stroke.length - 2]),
    );
    await gesture.up();
    await tester.pump();

    final session = sessionOf(tester);
    expect(session.isSolved, isTrue);

    // Undo and hint would unsolve a board the save already calls finished.
    for (final tooltip in ['Undo', 'Redo', 'Hint']) {
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull, reason: tooltip);
    }

    await tester.pump(journeyOf(tester));
    await tester.pump();
    expect(session.isSolved, isTrue);
    expect(find.text(completionTitle), findsOneWidget);

    await finish(tester, container);
  });

  testWidgets('a tap marks an empty cell, a second unmarks it, and a tap on '
      'track lifts it', (tester) async {
    final container = await pumpTracks(tester);
    final session = sessionOf(tester);
    final puzzle = puzzleFor(smallPuzzle.value);

    final empty = [
      for (var cell = 0; cell < session.spec.cells; cell++)
        if (session.maskAt(cell) == 0) cell,
    ].first;
    await tapCell(tester, empty);
    expect(session.isMarked(empty), isTrue);
    await tapCell(tester, empty);
    expect(session.isMarked(empty), isFalse);

    final path = solutionPath(puzzle);
    final free = path.indexWhere((cell) => !session.isFixed(cell));
    await drag(tester, [
      solutionStroke(puzzle).first,
      for (final cell in path.take(free + 1)) positionOf(session.spec, cell),
    ]);
    expect(session.maskAt(path[free]), isNot(0));

    await tapCell(tester, path[free]);
    expect(session.maskAt(path[free]), 0);

    await finish(tester, container);
  });

  testWidgets('undo, redo and hint do what the session says', (tester) async {
    final container = await pumpTracks(tester);
    final session = sessionOf(tester);

    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
    expect(button('Undo').onPressed, isNull, reason: 'nothing to undo yet');
    expect(button('Redo').onPressed, isNull);

    final before = snapshotOf(session);
    await drag(
      tester,
      solutionStroke(puzzleFor(smallPuzzle.value)).take(3).toList(),
    );
    expect(session.canUndo, isTrue);
    expect(button('Undo').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expectBoard(session, before);
    expect(button('Redo').onPressed, isNotNull);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(session.canUndo, isTrue);

    expect(session.hints, 0);
    await tester.tap(find.byTooltip('Hint'));
    await tester.pump();
    expect(session.hints, 1);

    await finish(tester, container);
  });

  testWidgets('a source that fails shows the message and nothing else', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [
        tracksPuzzleSourceProvider.overrideWithValue(_FailingSource()),
      ],
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.pushNamed(
        AppRoutes.tracksPlay,
        arguments: TracksPlayArgs(smallPuzzle),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(puzzleFailedMessage), findsOneWidget);
    expect(find.byType(TracksBoard), findsNothing);
    expect(find.byTooltip('Undo'), findsNothing);
    expect(tester.takeException(), isNull);

    await finish(tester, container);
  });

  testWidgets('a laid connection plays the place sound, and the fanfare '
      'waits for the end of the journey', (tester) async {
    final audio = RecordingAudio();
    final container = await pumpTracks(
      tester,
      overrides: [appAudioProvider.overrideWithValue(audio)],
    );
    final stroke = solutionStroke(puzzleFor(smallPuzzle.value));

    await drag(tester, stroke.take(3).toList());
    expect(audio.played, contains(Motif.sudokuPlace));
    expect(audio.played, isNot(contains(Motif.sudokuComplete)));

    await drag(tester, stroke);
    expect(sessionOf(tester).isSolved, isTrue);
    expect(
      audio.played,
      isNot(contains(Motif.sudokuComplete)),
      reason: 'not at the moment of solving',
    );

    await tester.pump();
    await tester.pump(journeyOf(tester) + const Duration(milliseconds: 100));
    expect(audio.played.where((m) => m == Motif.sudokuComplete), hasLength(1));

    await finish(tester, container);
  });

  testWidgets('next puzzle replaces the route with the next index', (
    tester,
  ) async {
    final source = FakeTracksPuzzleSource();
    final container = await pumpTracks(tester, source: source);
    await solveByDrag(tester, smallPuzzle);
    await tester.pump();
    await tester.pump(journeyOf(tester) + const Duration(milliseconds: 100));

    await tester.tap(find.text(nextPuzzleLabel));
    // Past the replacement transition, in which the finished screen is still
    // there underneath.
    await tester.pumpAndSettle();

    expect(source.loads.last.value, 'tracks:5x5:easy:1');
    expect(find.text(completionTitle), findsNothing);
    expect(find.byType(TracksBoard), findsOneWidget);

    await finish(tester, container);
  });

  testWidgets('going back mid-puzzle writes the clock', (tester) async {
    final container = await pumpTracks(tester);
    await drag(
      tester,
      solutionStroke(puzzleFor(smallPuzzle.value)).take(3).toList(),
    );
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await repositoryOf(container).flush();

    final saved = repositoryOf(
      container,
    ).activeProfile.tracks.inProgress[smallPuzzle.value];
    expect(saved?.elapsedMs, 3000);

    await finish(tester, container);
  });
}

class _FailingSource implements TracksPuzzleSource {
  @override
  Future<TracksPuzzleRecord> load(TracksPuzzleId id) =>
      Future<TracksPuzzleRecord>.error(StateError('no isolate'));

  @override
  void prewarm(TracksPuzzleId id) {}
}
