// A test, not an opinion (`PLAN-phase-5.md` §4.7): WCAG 2.1 relative
// luminance for every foreground-on-background pair `AppPalette` and the
// derived `ColorScheme`s actually put a child's eyes on, in both palettes.
//
// Two thresholds, per the WCAG 2.1 success criteria this pull request answers
// for `PLAN.md` §7 — 1.4.3 (4.5:1 for body text, 3:1 for text at 18pt/24px or
// 14pt/18.66px bold and up) and 1.4.11 (3:1 for a UI component's border
// against what sits next to it). Every pair below is named by which one
// applies to it and why, because a contrast test that does not say which
// clause it is enforcing is as much an opinion as a person looking at the
// screen.

import 'dart:math' as math;
import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';

/// WCAG 2.1's linearisation of one sRGB channel, already in the 0–1 range
/// `Color.r`/`.g`/`.b` return.
double _linearise(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.1 relative luminance (§1.4.3's own formula, not an approximation of
/// it): `0.2126 R + 0.7152 G + 0.0722 B` over the linearised channels.
double relativeLuminance(Color color) =>
    0.2126 * _linearise(color.r) +
    0.7152 * _linearise(color.g) +
    0.0722 * _linearise(color.b);

/// The contrast ratio between two colours, lighter over darker plus the
/// formula's own 0.05 — symmetric, so the order [a] and [b] are given in
/// never matters.
double contrastRatio(Color a, Color b) {
  final lumA = relativeLuminance(a) + 0.05;
  final lumB = relativeLuminance(b) + 0.05;
  return lumA > lumB ? lumA / lumB : lumB / lumA;
}

/// 1.4.3's floor for plain text: every digit, pencil mark, caption and body
/// sentence in the app.
const double bodyTextMinimum = 4.5;

/// 1.4.3's floor for large text (18pt/24px regular or 14pt/18.66px bold, both
/// well under the app's 18 dp button labels and 28–40 dp headings) and 1.4.11's
/// floor for a UI component's border against what sits next to it.
const double largeTextMinimum = 3;

void main() {
  group('the arithmetic itself', () {
    // A contrast test that cannot report a failure is an opinion wearing a
    // test's clothes. These three pin the formula against WCAG's own worked
    // values before anything below trusts it.
    test('black on white is the WCAG-quoted 21:1', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
    });

    test('a colour against itself is 1:1', () {
      const grey = Color(0xFF808080);
      expect(contrastRatio(grey, grey), closeTo(1, 0.001));
    });

    test('perturbing a colour towards its background lowers the ratio', () {
      // The done-criterion this file exists to meet: "fails when a palette
      // colour is perturbed towards its background." Mid grey on white passes
      // 4.5:1; nudged three quarters of the way to white, it no longer does —
      // proof the check would catch a palette edit that quietly erodes
      // contrast, not just one that already never had any.
      const background = Color(0xFFFFFFFF);
      const foreground = Color(0xFF595959);
      final before = contrastRatio(foreground, background);
      expect(before, greaterThanOrEqualTo(bodyTextMinimum));

      final nudged = Color.lerp(foreground, background, 0.75)!;
      final after = contrastRatio(nudged, background);
      expect(after, lessThan(before));
      expect(after, lessThan(bodyTextMinimum));
    });
  });

  // Everything past here is the app's own colours, not worked examples.
  //
  // `AppTheme.roleScheme` is what every role-coloured screen actually builds
  // its `ColorScheme` from — the plain day and night themes are that same
  // derivation seeded with `AppPalette.brand` (`theme.dart`) — so looping over
  // one function covers the home cards, the Sudoku and arcade menus, the
  // avatar picker and the on-screen pad alike.
  for (final brightness in Brightness.values) {
    final palette = AppPalette.of(brightness);
    final brightnessLabel = brightness == Brightness.dark ? 'night' : 'day';

    // Every seed this brightness actually colours a screen with: the app
    // theme's own brand seed plus the four role seeds `roleScheme` derives
    // from, and every avatar swatch a profile or its picker can be themed
    // with (`profile_screen.dart`'s `_AvatarTheme`).
    final seeds = <String, Color>{
      'brand': palette.brand,
      'sudoku': palette.sudoku,
      'arcade': palette.arcade,
      'draw': palette.draw,
      'notice': palette.notice,
      for (var i = 0; i < palette.avatarSwatches.length; i++)
        'avatar $i': palette.avatarSwatches[i],
    };

    for (final MapEntry(key: seedName, value: seed) in seeds.entries) {
      final role = AppTheme.roleScheme(seed, brightness);
      final label = '$seedName, $brightnessLabel';

      test('$label: body text on its surface clears $bodyTextMinimum:1', () {
        // Plain `Text` throughout a role-themed screen — the streak line and
        // the daily-puzzle heading's own body copy, a switch's label, the
        // build footer — takes its colour from the ambient `ColorScheme`,
        // which is `role` for any screen `_ChoiceSection`, `_DailyCard` and
        // their siblings theme (`sudoku_menu_screen.dart`,
        // `arcade_menu_screen.dart`).
        expect(
          contrastRatio(role.onSurface, role.surface),
          greaterThanOrEqualTo(bodyTextMinimum),
          reason: 'onSurface on surface',
        );
      });

      test('$label: captions on their surface clear $bodyTextMinimum:1', () {
        // The 14 dp, non-bold end of the type scale (`AppTypeScale.caption`):
        // the build footer and a `ListTile` subtitle both draw in
        // `onSurfaceVariant`, and neither is large enough to fall back to
        // [largeTextMinimum].
        expect(
          contrastRatio(role.onSurfaceVariant, role.surface),
          greaterThanOrEqualTo(bodyTextMinimum),
          reason: 'onSurfaceVariant on surface',
        );
      });

      test(
        '$label: a button label on its own fill clears $largeTextMinimum:1',
        () {
          // `BigButton`'s unselected fill: a `FilledButton`'s default colours,
          // which every role-themed screen inherits. The label is
          // `AppTypeScale.body` at `FontWeight.w600` — bold and 18 dp, past
          // 1.4.3's 14pt-bold large-text line.
          expect(
            contrastRatio(role.onPrimary, role.primary),
            greaterThanOrEqualTo(largeTextMinimum),
            reason: 'onPrimary on primary',
          );
        },
      );

      test('$label: a selected button label on its fill clears '
          '$largeTextMinimum:1', () {
        // `BigButton`'s selected fill (`big_button.dart`), the same bold 18
        // dp label — and the ring drawn in the same colour around it
        // (`AppBorders.selected`), which 1.4.11 holds to the same floor as a
        // UI component's border.
        expect(
          contrastRatio(role.onPrimaryContainer, role.primaryContainer),
          greaterThanOrEqualTo(largeTextMinimum),
          reason: 'onPrimaryContainer on primaryContainer',
        );
      });

      test('$label: a secondary-container card clears $bodyTextMinimum:1', () {
        // `_DailyCard`, the save-recovered notice and the Invaders card all
        // fill with `secondaryContainer` and draw both a heading and plain
        // `bodyLarge` copy in `onSecondaryContainer` — the streak line and
        // the "not played yet" message are not bold, so this pair has to
        // clear the body floor, not just the large one.
        expect(
          contrastRatio(role.onSecondaryContainer, role.secondaryContainer),
          greaterThanOrEqualTo(bodyTextMinimum),
          reason: 'onSecondaryContainer on secondaryContainer',
        );
      });

      test('$label: the selection ring clears $largeTextMinimum:1 against '
          'the surface it interrupts', () {
        // 1.4.11: `AppBorders.selected` on `BigButton` and the profile
        // avatar picker is a UI component's boundary, drawn in
        // `onPrimaryContainer` against whatever the button sits on —
        // `surface`, for every screen in `AppRoutes`.
        expect(
          contrastRatio(role.onPrimaryContainer, role.surface),
          greaterThanOrEqualTo(largeTextMinimum),
          reason: 'onPrimaryContainer (ring) on surface',
        );
      });

      test('$label: an unselected outline clears $largeTextMinimum:1 against '
          'its surface', () {
        // 1.4.11 again: the profile avatar picker's unselected border
        // (`profile_screen.dart`'s `_AvatarChoice`) is `colors.outline`
        // against the same `surface`.
        expect(
          contrastRatio(role.outline, role.surface),
          greaterThanOrEqualTo(largeTextMinimum),
          reason: 'outline on surface',
        );
      });
    }

    group('Sudoku digits and pencil marks stay readable, $brightnessLabel', () {
      // `sudoku_grid_view.dart._colorsFor` is the one place in the app that
      // draws a foreground from one role's tonal palette over a background
      // from another: the board sits on the play screen's own (brand-seeded)
      // background, but its highlights and digits are the Sudoku role's. That
      // combination is not one `ColorScheme.fromSeed` promises to contrast —
      // it promises `onSurface` reads on `surface`, not on a different role's
      // `primaryContainer` — so it is the pairing this whole file exists to
      // catch rather than assume.
      final brand =
          (brightness == Brightness.dark ? AppTheme.night() : AppTheme.day())
              .colorScheme;
      final sudoku = AppTheme.roleScheme(palette.sudoku, brightness);

      final backgrounds = <String, Color>{
        'the board\'s own background': brand.surface,
        'a selected cell': sudoku.primaryContainer,
        'a cell sharing the selected digit': sudoku.secondaryContainer,
        'a peer cell': sudoku.surfaceContainerHighest,
      };

      // Every colour `sudoku_cell.dart` can paint a digit or a pencil mark in,
      // however small the cell shrinks it — `digitSize` and `noteSize` both
      // clamp down to `AppTypeScale.caption`, so none of these can rely on
      // the large-text floor.
      final digitColors = <String, Color>{
        'a given digit': sudoku.onSurface,
        'an entered digit': sudoku.primary,
        'a wrong digit': brand.error,
        'a pencil mark': sudoku.onSurfaceVariant,
      };

      for (final MapEntry(key: backgroundName, value: background)
          in backgrounds.entries) {
        for (final MapEntry(key: digitName, value: digit)
            in digitColors.entries) {
          test('$digitName on $backgroundName clears $bodyTextMinimum:1', () {
            expect(
              contrastRatio(digit, background),
              greaterThanOrEqualTo(bodyTextMinimum),
            );
          });
        }
      }
    });
  }
}
