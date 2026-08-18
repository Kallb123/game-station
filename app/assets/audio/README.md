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

## The arcade set

Space Invaders only, so far — Sudoku's set above is the only one wired to a screen. `PLAN-phase-5.md`
§4.1 names each file after `invaders_sim.dart` rather than the play field, so `alien_shoot` greps to
the line that fires it where `enemy_shoot` would grep to nothing; the middle column below is the
plain-language name for anyone reading this table rather than the code.

| File | The sound | Plays when | Level |
|---|---|---|---|
| `arcade/player_shoot.wav` | shoot | The ship fires | −16 dBFS |
| `arcade/player_hit.wav` | hit | The ship is destroyed | −8 dBFS |
| `arcade/alien_shoot.wav` | enemy shoot | An alien fires | −18 dBFS |
| `arcade/alien_hit.wav` | enemy hit | An alien is destroyed | −12 dBFS |
| `arcade/alien_move.wav` | enemy move | The block steps sideways or down | −16 dBFS |
| `arcade/ufo_loop.wav` | special enemy | While the UFO is on screen, looped | −20 dBFS |
| `arcade/ufo_hit.wav` | special enemy hit | The UFO is destroyed | −8 dBFS |
| `arcade/wave_clear.wav` | — | The last alien of a wave dies | −8 dBFS |
| `arcade/extra_life.wav` | — | The 10,000-point bonus life | −8 dBFS |

`player_shoot` and `alien_shoot` are the same chirp played in opposite directions — the player's
rises, the alien's falls, 2 dB quieter — so the shot a child needs to react to is never confusable
with the one they just fired. `alien_move` is one low, muted tick rather than a pitched sequence: it
fires once per step of the alien block, which speeds up from 0.70 s to 0.09 s a step as a wave thins
(`InvadersSim._currentStepInterval()`), so the tempo comes from the game and not from anything in this
file. `player_hit`, `alien_hit` and `ufo_hit` are filtered noise rather than tones, because an
explosion is not a note; `player_hit` sweeps its filter down across its whole length on purpose, so
the loudest sound in the set reads as a fall rather than a klaxon (`AGENTS.md`: no scary failure
states).

**No `game_over` motif.** The last `player_hit` plus the game-over card is the ending; a tenth sound
on top of the card is a sound played over a screen a child is reading. **No music, on any of these** —
the arcade original's four descending notes were drafted for `alien_move` and cut, because cycling
pitches on a fixed step is music by another name (`PLAN-phase-5.md` §3.4). `settings.music`
stays in the schema, unread, by the owner's instruction (`PLAN-phase-5.md` §2).

Wiring these nine into `InvadersSim` and `InvadersGame` is `PLAN-phase-5.md` §6, PR 4 — this pull
request is the sounds themselves, with no Dart changed.

## Not here yet

Drawing-board sounds. Phase 8's pencil has none designed for it yet (`PLAN-phase-8.md`).

## Playback

`lib/core/audio/` plays these through [`minisound`](https://pub.dev/packages/minisound)
(`PLAN-phase-5.md` §3.1, not `flutter_soloud`, which resolves `http` into the shipped graph). The
`sound` setting gates every motif inside `AppAudio` rather than at each call site, so a new call site
cannot forget to check it. `sudoku/complete.wav` plays under the completion confetti (`PLAN.md`
§3.7); the rest of the Sudoku set plays from `SudokuSession`'s own events, drained by one listener
in `sudoku_play_screen.dart` rather than called from the keypad or the grid (`PLAN-phase-5.md` §3.3,
§4.3).

Both `assets/audio/sudoku/` and `assets/audio/arcade/` are declared in
[`pubspec.yaml`](../../pubspec.yaml) — an asset directory declared before it has content fails the
build, which is why the arcade line waited for this pull request.
