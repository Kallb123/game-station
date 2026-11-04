// Shared setup for the Tracks play screen's tests: pushing the route, finding
// the board, and driving a stroke through the real gesture arena.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// A drag goes through `tester.startGesture`, not through the session: the
// gesture detector's slop, its `down` start behaviour and the position
// arithmetic are exactly what a child's finger exercises, and calling
// `beginStroke` directly would test none of them.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/tracks/data/providers.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_source.dart';
import 'package:zibo_games/features/tracks/model/tracks_session.dart';
import 'package:zibo_games/features/tracks/skins/journey.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board_painter.dart';
import 'package:zibo_games/features/tracks/ui/tracks_play_screen.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../tracks_fixtures.dart';
import '../tracks_puzzle_fixtures.dart';

/// The 5x5 Easy puzzle most tests play.
final TracksPuzzleId smallPuzzle = TracksPuzzleId.parse('tracks:5x5:easy:0');

/// Pushes the play screen for [id] onto an already running app and lets the
/// route transition and the load finish.
///
/// Bounded pumps rather than `pumpAndSettle`: the clock is a periodic timer, and
/// settling would advance it by however long the transition took. 400 ms is past
/// the transition and short of the first tick.
Future<void> openTracks(WidgetTester tester, TracksPuzzleId id) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.pushNamed(AppRoutes.tracksPlay, arguments: TracksPlayArgs(id)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(TracksBoard), findsOneWidget);
}

/// Starts the app over [store] with [source] and opens [id].
Future<ProviderContainer> pumpTracks(
  WidgetTester tester, {
  TracksPuzzleId? id,
  MemorySaveStore? store,
  TracksPuzzleSource? source,
  List<Override> overrides = const [],
}) async {
  final container = await pumpApp(
    tester,
    store: store ?? MemorySaveStore(initial: freshSave()),
    overrides: [
      tracksPuzzleSourceProvider.overrideWithValue(
        source ?? FakeTracksPuzzleSource(),
      ),
      ...overrides,
    ],
  );
  await openTracks(tester, id ?? smallPuzzle);
  return container;
}

/// The session the board is drawing.
TracksSession sessionOf(WidgetTester tester) =>
    tester.widget<TracksBoard>(find.byType(TracksBoard)).session;

/// The painter the board is drawing with.
TracksBoardPainter painterOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TracksBoard),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as TracksBoardPainter;
}

ProgressRepository repositoryOf(ProviderContainer container) =>
    container.read(progressRepositoryProvider);

/// The global position of the centre of ([row], [column]), ports included.
Offset positionOnScreen(WidgetTester tester, int side, Position position) {
  final box = find
      .descendant(
        of: find.byType(TracksBoard),
        matching: find.byType(CustomPaint),
      )
      .evaluate()
      .first
      .renderObject!;
  final size = (box as RenderBox).size;
  final layout = BoardLayout.fit(size, side);
  return box.localToGlobal(layout.rectAt(position.$1, position.$2).center);
}

/// Drags one finger through [positions] and lifts it.
Future<void> drag(WidgetTester tester, List<Position> positions) async {
  final side = sessionOf(tester).spec.side;
  final gesture = await tester.startGesture(
    positionOnScreen(tester, side, positions.first),
  );
  for (final position in positions.skip(1)) {
    await gesture.moveTo(positionOnScreen(tester, side, position));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Taps the centre of [cell].
Future<void> tapCell(WidgetTester tester, int cell) async {
  final spec = sessionOf(tester).spec;
  await tester.tapAt(
    positionOnScreen(tester, spec.side, positionOf(spec, cell)),
  );
  await tester.pump();
}

/// Plays the stroke that solves [id]'s fixture.
Future<void> solveByDrag(WidgetTester tester, TracksPuzzleId id) =>
    drag(tester, solutionStroke(puzzleFor(id.value)));

/// How long the journey of the board on screen takes: what a test pumps
/// through to reach the card.
Duration journeyOf(WidgetTester tester) {
  final session = sessionOf(tester);
  final route = TrackGeometry.trace(session.clues, session.cells)!;
  return journeyDuration(painterOf(tester).skin, route);
}

/// Pumps through the journey and the arrival time after it: what a test does to
/// reach the card. Two steps because a single tick past the journey sounds the
/// motif and only then starts the arrival time that holds the card back.
Future<void> pumpToCard(WidgetTester tester) async {
  final arrival = painterOf(tester).skin.arrivalDuration;
  await tester.pump(journeyOf(tester) + const Duration(milliseconds: 100));
  await tester.pump(arrival);
}

/// Lands the repository's debounced write and takes the tree down, so no timer
/// is pending when the test ends.
Future<void> finish(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await repositoryOf(container).flush();
  await tester.pump(const Duration(seconds: 1));
}
