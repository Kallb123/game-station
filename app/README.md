# game_station (app)

The Flutter application: UI, storage, audio and the arcade games. Sudoku generation and solving live
in [`packages/puzzle_engine`](../packages/puzzle_engine), which this package depends on by path.

Status: phase 0 scaffold — one placeholder screen. See [PLAN.md](../PLAN.md) §7.

## Commands

```sh
flutter pub get
flutter run -d <device>
flutter test
flutter analyze
```

`../tool/verify.sh` runs everything CI runs, for both packages, in the same order.

## Layout

Phase 1 onward fills in the structure from PLAN.md §6:

```
lib/
├─ main.dart
├─ app.dart          # router and theme
├─ core/             # storage, audio, shared UI and design tokens
└─ features/         # home, profiles, settings, sudoku, arcade
```

## Constraints that affect this package

- No networking, no ads, no analytics — enforced by `../tool/check_offline.dart`, which reads both
  the source and the resolved dependency graph.
- `android/app/src/main/AndroidManifest.xml` must not request `INTERNET`. The debug and profile
  manifests do, because hot reload needs it; neither is merged into a release build.
- `macos/Runner/Release.entitlements` must not grant a network entitlement.
- Fonts are bundled files, never fetched. See [`assets/fonts/README.md`](assets/fonts/README.md).
