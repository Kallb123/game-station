# Asset licensing

Code in this repository is MIT (see [`LICENSE`](../../LICENSE)). Assets are separate: fonts, images
and audio each carry their own terms, and mixing an incompatible one in would block a store release
or an F-Droid listing.

## Rules

- Prefer **CC0** or public domain. Nothing to attribute, nothing to track.
- **CC-BY** is acceptable if the attribution is recorded in the table below and shown in the app's
  about screen.
- **No CC-BY-NC, no CC-BY-ND, and no asset-store licence that forbids redistribution** — the source
  is public, so an asset that cannot be redistributed cannot live here.
- Fonts must be **OFL or Apache-2.0** licensed and committed as files. `google_fonts` fetches over
  the network at runtime, which the no-network rule rules out.
- Every asset gets a row below, added in the same commit as the file.

## Inventory

| Asset | Kind | Source | Licence | Attribution required |
|---|---|---|---|---|
| `images/Zibo Games 512.png` | Image | Supplied by the project owner | MIT, with the rest of the repository | No |
| `images/Zibo Games 114.png` | Image | Supplied by the project owner | MIT, with the rest of the repository | No |
| `audio/sudoku/place.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/sudoku/correct.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/sudoku/wrong.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/sudoku/erase.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/sudoku/hint.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/sudoku/complete.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/player_shoot.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/player_hit.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/alien_shoot.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/alien_hit.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/alien_move.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/ufo_loop.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/ufo_hit.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/wave_clear.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |
| `audio/arcade/extra_life.wav` | Audio | Synthesised by `tool/audio/generate_motifs.py` | MIT, with the rest of the repository | No |

The two images above are the app icon, at the two sizes an Amazon Appstore listing asks for: 512 px
for the large icon, 114 px for the small one (PLAN.md §9, phase 6). The 512 px one is also the master
that [`tool/icon/generate_platform_icons.py`](../../tool/icon/generate_platform_icons.py) resamples
into the Android mipmaps, the two `AppIcon.appiconset`s and the Windows `.ico`, so replacing it and
re-running that script is the whole of changing the icon.

The fifteen audio files are the Sudoku and arcade motifs, and they are the licensing-free case on
purpose: they are generated from arithmetic by a committed script rather than taken from a sample
library, so there is no third-party licence in the tree to honour and no attribution to carry into
the about screen. See [`audio/README.md`](audio/README.md) for what each one plays for and how to
change it. A recorded or downloaded sound may still be added later, but it needs its own row and has
to clear the rules above — "free for personal use" is not one of the licences listed there.

Neither of the images is declared in [`pubspec.yaml`](../pubspec.yaml). Nothing in the app draws
them — they are store and build inputs, not runtime assets — and declaring them would put a 171 kB
PNG in every build to be read by nothing. The audio is declared: see [`audio/README.md`](audio/README.md).
