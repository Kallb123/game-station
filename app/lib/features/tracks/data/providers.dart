// The Riverpod wiring over `features/tracks/data`.
//
// Same shape as `features/sudoku/data/providers.dart`: the implementation is
// behind a provider so that a widget test overrides it with a fake and never
// generates.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../model/tracks_menu.dart';
import 'tracks_puzzle_source.dart';

/// Where the Tracks screens get their puzzles.
///
/// Watches the repository's `.notifier` rather than the repository itself, for
/// the reason `puzzleSourceProvider` does: watching the value would rebuild
/// this on every saved move and throw away the in-flight map.
final Provider<TracksPuzzleSource> tracksPuzzleSourceProvider =
    Provider<TracksPuzzleSource>((ref) {
      final source = IsolateTracksPuzzleSource(
        ref.watch(progressRepositoryProvider.notifier),
      );
      // A generation cannot be cancelled, so one can outlive the scope. Told
      // the scope has gone, the source stops writing to a repository that has
      // gone with it.
      ref.onDispose(source.dispose);
      return source;
    });

/// The Tracks menu's numbers for the active profile.
///
/// Watches the profile, so a switch or a solved puzzle rebuilds the menu from
/// the new history.
final Provider<TracksMenu> tracksMenuProvider = Provider<TracksMenu>(
  (ref) => TracksMenu.of(ref.watch(activeProfileProvider).tracks),
);
