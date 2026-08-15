// The tap-target floor from PLAN.md §4.2, asserted against widgets that were
// given no styling at all.
//
// That is the point of putting it in the theme: these tests pass for a button
// written in phase 4 by someone who never read the rule.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';

import 'ui_harness.dart';

void main() {
  appThemes.forEach((themeName, buildTheme) {
    group(themeName, () {
      testWidgets('an unstyled ElevatedButton meets the tap-target floor', (
        tester,
      ) async {
        await pumpApp(
          tester,
          Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
          theme: buildTheme(),
        );

        final size = tester.getSize(find.byType(ElevatedButton));
        expect(size.height, greaterThanOrEqualTo(AppTapTargets.min));
        expect(size.width, greaterThanOrEqualTo(AppTapTargets.min));
      });

      testWidgets('an unstyled IconButton meets the tap-target floor', (
        tester,
      ) async {
        await pumpApp(
          tester,
          Scaffold(
            body: Center(
              child: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings),
              ),
            ),
          ),
          theme: buildTheme(),
        );

        final size = tester.getSize(find.byType(IconButton));
        expect(size.height, greaterThanOrEqualTo(AppTapTargets.min));
        expect(size.width, greaterThanOrEqualTo(AppTapTargets.min));
      });

      testWidgets('a default BigButton meets the primary tap-target size', (
        tester,
      ) async {
        await pumpApp(
          tester,
          Scaffold(
            body: Center(
              child: BigButton(
                icon: Icons.grid_on,
                label: 'Sudoku',
                onPressed: () {},
              ),
            ),
          ),
          theme: buildTheme(),
        );

        final size = tester.getSize(find.byType(BigButton));
        expect(size.height, greaterThanOrEqualTo(AppTapTargets.primary));
        expect(size.width, greaterThanOrEqualTo(AppTapTargets.primary));
      });

      testWidgets('the theme matches its own brightness', (tester) async {
        final theme = buildTheme();
        await pumpApp(tester, const Scaffold(body: Text('x')), theme: theme);

        final context = tester.element(find.text('x'));
        expect(Theme.of(context).brightness, theme.colorScheme.brightness);
      });
    });
  });

  // The regression this guards: `VisualDensity.adaptivePlatformDensity` is
  // compact on desktop, and compact density subtracts 8 dp from a control's
  // minimum size. A 56 dp floor set through `minimumSize` alone would render
  // at 48 dp on Windows, macOS and Linux — half the targets — with nothing in
  // the code saying so.
  for (final platform in <TargetPlatform>[
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('the tap-target floor survives $platform density', (
      tester,
    ) async {
      // Reset in a `finally` inside the test body, not in a tear-down: the
      // framework checks its "debug variable changed by the test" invariant
      // before tear-downs run, and a failing assertion here would otherwise
      // leak the override into every test after it.
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pumpApp(
          tester,
          Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
          // Built inside the test, so the density decision sees the override.
          theme: AppTheme.day(),
        );

        expect(
          tester.getSize(find.byType(ElevatedButton)).height,
          greaterThanOrEqualTo(AppTapTargets.min),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('the type scale uses only the four token sizes', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: Text('x')),
      theme: AppTheme.day(),
    );

    final textTheme = Theme.of(tester.element(find.text('x'))).textTheme;
    // A list, not a set: a const set of doubles is not allowed, because
    // `double` overrides `==`.
    const allowed = <double>[
      AppTypeScale.display,
      AppTypeScale.title,
      AppTypeScale.body,
      AppTypeScale.caption,
    ];
    final styles = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
      'titleSmall': textTheme.titleSmall,
      'bodyLarge': textTheme.bodyLarge,
      'bodyMedium': textTheme.bodyMedium,
      'bodySmall': textTheme.bodySmall,
      'labelLarge': textTheme.labelLarge,
      'labelMedium': textTheme.labelMedium,
      'labelSmall': textTheme.labelSmall,
    };

    styles.forEach((name, style) {
      expect(style?.fontSize, isIn(allowed), reason: '$name is off the scale');
    });
  });
}
