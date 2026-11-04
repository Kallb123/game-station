// What the Tracks menu is allowed to offer.
//
// The counterpart of `sudoku/model/difficulties.dart`: pure, imported by the
// menu and by its test, so that "the menu offers what the engine builds" is
// one shared fact (`PLAN-phase-9-tracks.md` §4.14).

import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/save_data.dart' show TracksTheme;

/// The name the menu, and the Puzzles card that opens it, carry.
///
/// One constant, because "Tracks" is a working name and the label is the part
/// that may still change after the ID prefix is frozen
/// (`PLAN-phase-9-tracks.md` §9).
const String tracksMenuTitle = 'Tracks';

/// The sizes the menu offers, in the order its toggle draws them.
const List<TracksSpec> tracksSizes = TracksSpec.supported;

/// The size a profile with no history is offered: the first puzzle for a young
/// child.
const TracksSpec defaultTracksSpec = TracksSpec.s5x5;

/// The difficulty a profile with no history is offered.
const Difficulty defaultTracksDifficulty = Difficulty.easy;

/// The difficulties [spec] can be played at, easiest first.
///
/// 5x5 has no Hard tier (`PLAN-phase-9-tracks.md` §4.1), and the engine refuses
/// the combination in `TracksPuzzleId.parse`. Filtered through that rather than
/// listed, so the menu cannot offer a tier the engine would throw for, and a
/// tier added later appears without an edit here. Expert is not a Tracks tier.
List<Difficulty> tracksDifficultiesFor(TracksSpec spec) => <Difficulty>[
  for (final difficulty in Difficulty.values)
    if (_isOffered(spec, difficulty)) difficulty,
];

bool _isOffered(TracksSpec spec, Difficulty difficulty) {
  try {
    TracksPuzzleId.parse('tracks:${spec.label}:${difficulty.name}:0');
    return true;
  } on FormatException {
    return false;
  }
}

/// The themes the picker offers, in the order it draws them.
///
/// Only the two whose skins exist. `trackSkinFor` still draws `santa` and
/// `snail` with the train until PR 9, so a button for either would show a
/// locomotive under another name. PR 9 adds them here
/// (`PLAN-phase-9-tracks.md` §4.8).
const List<TracksTheme> offeredTracksThemes = <TracksTheme>[
  TracksTheme.train,
  TracksTheme.water,
];
