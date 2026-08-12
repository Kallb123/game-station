import 'package:flutter/material.dart';

import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/tokens.dart';

/// The screen behind a route whose game has not been built yet.
///
/// It exists so that phases 3 and 4 replace the body of a screen that already
/// has a route, a title and a widget test, rather than adding all three at once
/// (PLAN-phase-1.md §4.5). A card on the home screen that did nothing would
/// also read to a child as a broken app.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({required this.title, required this.icon, super.key});

  /// The name of the thing that is coming — the heading, so the child can see
  /// which card they tapped.
  final String title;

  /// The same glyph the card on the home screen carries, for the same reason.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScreenScaffold(
      title: title,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Icon(icon, size: AppTapTargets.primary, color: theme.disabledColor),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Coming soon!',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We are still building this one.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
