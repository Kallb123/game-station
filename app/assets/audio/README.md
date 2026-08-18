# Audio

Every sound in here is synthesised by
[`tool/audio/generate_motifs.py`](../../../tool/audio/generate_motifs.py) from arithmetic — no
recording, no sample library, nothing downloaded. That script is the master and these `.wav` files
are its committed output:

```sh
python3 tool/audio/generate_motifs.py           # rewrite the files
python3 tool/audio/generate_motifs.py --check    # fail if they no longer match the script
```

It needs only the standard library, and like `tool/icon/generate_platform_icons.py` it is not wired
into `tool/verify.sh` or CI: the outputs are committed, so no build depends on a synthesiser being
installed. Changing a sound means editing the script, re-running it, **listening to the result**,
and committing both. The numbers are the sound; a diff cannot be reviewed by reading it.

## The Sudoku set

| File | Plays when | Level |
|---|---|---|
| `sudoku/place.wav` | A digit goes into a cell | −18 dBFS peak |
| `sudoku/correct.wav` | That digit was right, on a profile that flags mistakes immediately | −10 dBFS |
| `sudoku/wrong.wav` | That digit was wrong, same profiles | −16 dBFS |
| `sudoku/erase.wav` | A cell is cleared | −20 dBFS |
| `sudoku/hint.wav` | A hint arrives | −12 dBFS |
| `sudoku/complete.wav` | The puzzle is solved — the trumpet | −3 dBFS |

Levels are relative to each other and set per motif rather than normalised flat: `place` fires
hundreds of times per puzzle and `complete` once, so the tick sits 15 dB under the fanfare.

**One sound per placement, not two.** `place` is not layered under `correct` or `wrong` — a digit
plays exactly one of the three. On `MistakeFeedback.immediate`, `correct` or `wrong` plays *instead
of* `place`; on `MistakeFeedback.atCompletion`, `place` is what plays for every digit, because that
mode hides wrongness until the grid is full (`PLAN.md` §3.7) and a placement sound that brightened
for a correct digit would hand that back through the speaker — the child would learn the tick
instead of the Sudoku. `noted` plays `place` too, at a lighter volume: a pencil mark is a quieter
version of the same act. `erase` also covers an undo or a redo, which put a cell back rather than
clearing it, because both are the board changing back (`PLAN-phase-5.md` §4.3).

## Not here yet

Arcade and drawing-board sounds. Adding a motif means adding a function to the script and a row
above — the nine arcade files `PLAN-phase-5.md` §4.1 names are rows waiting to be filled in.

There is no music anywhere in the app, by the owner's instruction (`PLAN-phase-5.md` §2): `settings.music`
stays in the schema, unread.

## Playback

`lib/core/audio/` plays these through [`minisound`](https://pub.dev/packages/minisound)
(`PLAN-phase-5.md` §3.1, not `flutter_soloud`, which resolves `http` into the shipped graph). The
`sound` setting gates every motif inside `AppAudio` rather than at each call site, so a new call site
cannot forget to check it. `sudoku/complete.wav` plays under the completion confetti (`PLAN.md`
§3.7); the rest of the Sudoku set plays from `SudokuSession`'s own events, drained by one listener
in `sudoku_play_screen.dart` rather than called from the keypad or the grid (`PLAN-phase-5.md` §3.3,
§4.3).

`assets/audio/sudoku/` is declared in [`pubspec.yaml`](../../pubspec.yaml); `assets/audio/arcade/`
is declared once PR 3 puts files in it — an asset directory declared before it has content fails the
build.
