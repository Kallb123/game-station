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

**`place` is deliberately neutral about whether the digit is right.** `MistakeFeedback.atCompletion`
hides wrongness until the grid is full (`PLAN.md` §3.7), and a placement sound that brightened for a
correct digit would hand that back through the speaker — the child would learn the tick instead
of the Sudoku. On those profiles the placement tick is the whole feedback; `correct` and `wrong`
belong to `MistakeFeedback.immediate`.

## Not here yet

Arcade and drawing-board sounds, and the light music of `PLAN.md` §7's phase 5. Adding a motif means
adding a function to the script and a row above.

Nothing plays any of this yet. Playback is phase 5, with `flutter_soloud` and the mute-aware wrapper
in `lib/core/audio/`; the `sound` setting exists and is stored, but nothing consumes it
(`PLAN-phase-1.md` §2).

These files are therefore **not declared in [`pubspec.yaml`](../../pubspec.yaml)**, for the same
reason the icon PNGs are not: an asset declared before anything reads it is bytes in every
platform's binary to be read by nothing. Phase 5 declares `assets/audio/` in the commit that first
plays a sound.
