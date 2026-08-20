import 'package:flutter/material.dart';

import 'safe_pop.dart';
import 'tokens.dart';

/// The frame every screen in the app sits in: safe-area insets, screen-edge
/// padding, a title, and a way back.
///
/// It is deliberately not an [AppBar]. An app bar is a fixed 56 dp tall, so at
/// 200% text scale its title is clipped rather than wrapped, and its leading
/// button is 48 dp — under the floor in PLAN.md §4.2. A header that is just a
/// row grows instead.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
    this.onBack,
    this.hideBack = false,
    super.key,
  });

  /// The screen's name, shown as its heading.
  final String title;

  /// The screen's content. It is given the space left under the header.
  final Widget child;

  /// Controls shown at the trailing end of the header, such as the home
  /// screen's settings button.
  final List<Widget> actions;

  /// Overrides what the back control does. When null, the control pops the
  /// route, and is hidden entirely if there is nothing to pop — a back arrow
  /// that does nothing is worse than no arrow.
  final VoidCallback? onBack;

  /// Forces the back control off for a screen that never has anything to go
  /// back to, such as the home screen.
  ///
  /// [Navigator.canPop] is read fresh each time this widget rebuilds, but it
  /// does not rebuild every time it becomes visible again — a screen kept
  /// mounted underneath another route can be rebuilt for an unrelated reason
  /// (a watched provider changing) while `canPop` is answering for whatever
  /// route is on top at that moment, and nothing rebuilds it a second time
  /// once that route is popped and the true answer changes back. The home
  /// screen has no route beneath it ever, so it sets this instead of relying
  /// on a check that can go stale.
  final bool hideBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showBack =
        !hideBack && (onBack != null || Navigator.of(context).canPop());

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (showBack) ...[
                    IconButton(
                      onPressed: onBack ?? () => popIfPossible(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        size: AppIconSizes.large,
                      ),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.displaySmall,
                        // Wraps to a second line, then truncates. A screen
                        // title here is one or two words, and at 200% text
                        // scale an unbounded one would wrap to eight lines and
                        // push the screen's content off the bottom — a heading
                        // that eats the screen it names.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
