import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/avatars.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../routes.dart';

/// The glyph for Sudoku, here rather than at each use so that the home card
/// and the screen it opens cannot drift apart.
const IconData homeSudokuIcon = Icons.grid_on;

/// The glyph for the arcade.
const IconData homeArcadeIcon = Icons.sports_esports;

/// The glyph for Draw, from phase 8.
const IconData homeDrawIcon = Icons.brush;

/// What the player is told when their save could not be read.
///
/// One sentence, no file path, no version number, nothing the child did wrong
/// (PLAN-phase-1.md §4.3). A parent who wants the detail has the file itself,
/// kept beside the new save as `save.corrupt.json`.
const String saveNoticeText =
    'We couldn’t find your old games, so we started fresh.';

/// The first screen: what there is to do, who is playing, and a way to the
/// settings.
///
/// Three cards and nothing else on purpose. The child who opens this app is
/// choosing between Sudoku, the arcade and drawing; anything else on the
/// screen is something to read before they can play.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider);
    final landscape = isLandscapeWindow(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ref.watch(saveNoticeProvider)) ...[
          _SaveNotice(
            onDismissed: () => ref.read(saveNoticeProvider.notifier).dismiss(),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Expanded(
          child: landscape ? const _LandscapeCards() : const _PortraitCards(),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProfileChip(name: profile.name, avatar: profile.avatar),
      ],
    );

    return ScreenScaffold(
      title: 'Zibo Games',
      // Nothing under the home screen is ever reachable by popping, so the
      // back control is forced off rather than left to `canPop` — which can
      // go stale while this screen sits mounted underneath another route
      // (`screen_scaffold.dart`).
      hideBack: true,
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
          icon: const Icon(Icons.settings, size: AppIconSizes.large),
          tooltip: 'Settings',
        ),
      ],
      // Fills the screen when the content fits and scrolls when it does not.
      // Both cases are real: a tablet has room for two cards half a screen
      // tall, and the same screen at 200% text scale with the recovery notice
      // showing does not, which a plain `Column` would report as an overflow
      // and draw over.
      //
      // The width cap is skipped in landscape: `_LandscapeCards` caps each
      // card itself (`PLAN-phase-5.md` §4.8's "cards capped at
      // maxContentWidth each"), and capping the whole row on top of that
      // would fight the two cards for the same room on a landscape tablet.
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: landscape ? content : ContentWidthCap(child: content),
          ),
        ],
      ),
    );
  }
}

/// Which palette role a card takes its colour from.
enum _Role { sudoku, arcade, draw }

/// The three cards, stacked full-width — unchanged from before this screen
/// knew about orientation, aside from the third card phase 8 adds.
class _PortraitCards extends StatelessWidget {
  const _PortraitCards();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _GameCard(
            icon: homeSudokuIcon,
            label: 'Sudoku',
            route: AppRoutes.sudoku,
            role: _Role.sudoku,
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _GameCard(
            icon: homeArcadeIcon,
            label: 'Arcade',
            route: AppRoutes.arcade,
            role: _Role.arcade,
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _GameCard(
            icon: homeDrawIcon,
            label: 'Draw',
            route: AppRoutes.draw,
            role: _Role.draw,
          ),
        ),
      ],
    );
  }
}

/// How tall a card is allowed to get once there is more height than a card
/// needs — a landscape phone has none to spare, and a landscape tablet has
/// far more than a button wants to stretch across (`PLAN-phase-5.md` §4.8).
const double _landscapeCardHeight = 200;

/// The three cards, side by side, each letterboxed to [_landscapeCardHeight]
/// rather than stretched to whatever height a landscape window happens to
/// leave: unlike a phone in portrait, a phone or tablet in landscape can have
/// height to spare, and a full-bleed button stretched across all of it reads
/// as broken rather than generous.
class _LandscapeCards extends StatelessWidget {
  const _LandscapeCards();

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget card) => Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: maxContentWidth,
            maxHeight: _landscapeCardHeight,
          ),
          child: card,
        ),
      ),
    );

    return Row(
      children: [
        cell(
          const _GameCard(
            icon: homeSudokuIcon,
            label: 'Sudoku',
            route: AppRoutes.sudoku,
            role: _Role.sudoku,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        cell(
          const _GameCard(
            icon: homeArcadeIcon,
            label: 'Arcade',
            route: AppRoutes.arcade,
            role: _Role.arcade,
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        cell(
          const _GameCard(
            icon: homeDrawIcon,
            label: 'Draw',
            route: AppRoutes.draw,
            role: _Role.draw,
          ),
        ),
      ],
    );
  }
}

/// The "we started fresh" notice.
///
/// Shown once per launch and dismissed by hand, rather than a `SnackBar` that
/// times out: a child reading one word at a time has no fixed number of seconds
/// in which to finish a sentence.
///
/// It is not an error state, so it is not red. Nothing here went wrong that the
/// player did, and the only thing they can do about it is read it.
class _SaveNotice extends StatelessWidget {
  const _SaveNotice({required this.onDismissed});

  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppTheme.roleScheme(
      AppPalette.of(theme.brightness).notice,
      theme.brightness,
    );

    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: AppIconSizes.large,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              saveNoticeText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismissed,
            icon: const Icon(Icons.close, size: AppIconSizes.standard),
            color: colors.onSecondaryContainer,
            tooltip: 'Got it',
          ),
        ],
      ),
    );
  }
}

/// One of the two things there are to play.
///
/// The colour is the role's, not the theme's, so the two halves of the app are
/// told apart at a glance. It is never the only difference: the icon and the
/// label carry the same information for a player who cannot use the colour
/// (`tokens.dart`).
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.label,
    required this.route,
    required this.role,
  });

  final IconData icon;
  final String label;
  final String route;
  final _Role role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(theme.brightness);
    final seed = switch (role) {
      _Role.sudoku => palette.sudoku,
      _Role.arcade => palette.arcade,
      _Role.draw => palette.draw,
    };

    return Theme(
      data: theme.copyWith(
        colorScheme: AppTheme.roleScheme(seed, theme.brightness),
      ),
      child: BigButton(
        icon: icon,
        label: label,
        onPressed: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }
}

/// Who is playing, and the way to change it.
///
/// A button rather than a `Chip`, so it takes the 56 dp tap-target floor from
/// the theme (`theme.dart`) instead of Material's smaller chip metrics.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.name, required this.avatar});

  final String name;
  final AvatarId avatar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.profiles),
      icon: Icon(avatarIcon(avatar), size: AppIconSizes.large),
      // "Playing as" rather than a bare name, so the button says what tapping
      // it is about. The name is the child's, so it is the part that is read.
      label: Text('Playing as $name', overflow: TextOverflow.ellipsis),
    );
  }
}
