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

The two images above are the app icon, at the two sizes an Amazon Appstore listing asks for: 512 px
for the large icon, 114 px for the small one (PLAN.md §9, phase 6). The 512 px one is also the master
that [`tool/icon/generate_platform_icons.py`](../../tool/icon/generate_platform_icons.py) resamples
into the Android mipmaps, the two `AppIcon.appiconset`s and the Windows `.ico`, so replacing it and
re-running that script is the whole of changing the icon.

Neither is declared in [`pubspec.yaml`](../pubspec.yaml). Nothing in the app draws them — they are
store and build inputs, not runtime assets — and declaring them would put a 171 kB PNG in every build
to be read by nothing.
