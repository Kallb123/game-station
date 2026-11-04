import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/model/tracks_difficulties.dart';

void main() {
  test('the sizes are the engine\'s, smallest first', () {
    expect(tracksSizes, TracksSpec.supported);
    expect(tracksSizes.first, defaultTracksSpec);
  });

  test('a tier is offered exactly when the engine can spell its id', () {
    for (final spec in tracksSizes) {
      for (final difficulty in Difficulty.values) {
        var parses = true;
        try {
          TracksPuzzleId.parse('tracks:${spec.label}:${difficulty.name}:0');
        } on FormatException {
          parses = false;
        }
        expect(
          tracksDifficultiesFor(spec).contains(difficulty),
          parses,
          reason: '${spec.label} ${difficulty.name}',
        );
      }
    }
  });

  test('5x5 has no Hard, and every size starts at Easy', () {
    expect(
      tracksDifficultiesFor(TracksSpec.s5x5),
      isNot(contains(Difficulty.hard)),
    );
    for (final spec in tracksSizes) {
      expect(tracksDifficultiesFor(spec).first, defaultTracksDifficulty);
    }
  });

  test('the picker offers every theme once, in enum order, train first', () {
    expect(offeredTracksThemes.first, TracksTheme.train);
    expect(offeredTracksThemes.toSet(), hasLength(offeredTracksThemes.length));
    expect(offeredTracksThemes, TracksTheme.values);
  });
}
