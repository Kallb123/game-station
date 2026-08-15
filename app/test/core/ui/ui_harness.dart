// Shared setup for the `core/ui` widget tests.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/theme.dart';

/// The app's themes, by the name a test description reads best with.
///
/// Every size rule has to hold in both, so tests loop over this rather than
/// asserting against one and assuming the other.
const Map<String, ThemeData Function()> appThemes =
    <String, ThemeData Function()>{
      'the day theme': AppTheme.day,
      'the night theme': AppTheme.night,
    };

/// Pumps [home] inside a [MaterialApp] using [theme], with text scaled by
/// [textScale].
///
/// The scale is injected through `builder` rather than by wrapping [home]:
/// `MaterialApp` inserts its own `MediaQuery` from the view, which would
/// otherwise replace an outer one and quietly test at 100%.
Future<void> pumpApp(
  WidgetTester tester,
  Widget home, {
  required ThemeData theme,
  double textScale = 1,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          // System insets — a notch, a home indicator, a gesture bar.
          padding: padding,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Resizes the test surface to a small phone for the duration of the test.
///
/// The 800x600 default is a tablet. A layout that overflows does it on the
/// narrowest target first, so the text-scale tests run here.
Future<void> usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
