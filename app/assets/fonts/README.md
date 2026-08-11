# Fonts

Font files are committed here and declared in `app/pubspec.yaml`. They are never fetched at runtime:
`google_fonts` downloads on first use, which breaks on a plane and contradicts the no-network rule, so
that package is on the banned list enforced by `tool/check_offline.dart`.

Requirements for a font added here:

- OFL or Apache-2.0 licensed, with the licence file committed alongside it.
- A row in [`../LICENSE-ASSETS.md`](../LICENSE-ASSETS.md).
- Legible at small sizes and at 200% system text scale, with unambiguous digits — the Sudoku grid is
  almost entirely digits, and a child should not have to work out whether a glyph is a 1 or a 7.
- Only the weights actually used, since each one is bundled into every platform's binary.
