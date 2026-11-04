// The grid of picture buttons that chooses how Tracks looks
// (`PLAN-phase-9-tracks.md` §4.8, §4.14).
//
// Each button shows the thing the skin starts with, painted by the skin itself,
// so what a child taps is what they will play with and no second set of
// pictures exists to drift from the first. The theme is per profile, because
// siblings on one tablet want different trains; choosing one writes only the
// active profile (`ProgressRepository.setTracksTheme`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/tokens.dart';
import '../model/tracks_difficulties.dart';
import '../skins/track_skin.dart';
import '../skins/track_skins.dart';

/// The heading over the picker.
const String pickThemeTitle = 'Theme';

/// How tall the picture on each button is.
const double _pictureSize = 64;

/// One selectable picture per theme in [offeredTracksThemes].
class TracksThemePicker extends ConsumerWidget {
  /// The picker; the chosen theme is the active profile's.
  const TracksThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final chosen = ref.watch(
      activeProfileProvider.select((profile) => profile.tracksTheme),
    );

    // Rows of two: four buttons at 64 dp picture plus padding do not fit one
    // row on a 360 dp phone. Each row is an IntrinsicHeight so a label that
    // wraps to two lines at a large text scale makes its neighbour as tall
    // rather than ragged.
    final themes = offeredTracksThemes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.md,
      children: [
        for (var start = 0; start < themes.length; start += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                for (final theme in themes.skip(start).take(2))
                  // Expanded so each label has a bounded width to wrap into.
                  Expanded(
                    child: _ThemeButton(
                      skin: trackSkinFor(theme, brightness),
                      selected: theme == chosen,
                      onPressed: () => ref
                          .read(progressRepositoryProvider)
                          .setTracksTheme(theme),
                    ),
                  ),
                // An odd last row keeps its button the width of the others.
                if (themes.length - start == 1) const Spacer(),
              ],
            ),
          ),
      ],
    );
  }
}

/// A card with the skin's start sprite over its name.
///
/// Selected is a border and a check as well as a colour, as `BigButton` has it:
/// colour is never the only signal (`tokens.dart`).
class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.skin,
    required this.selected,
    required this.onPressed,
  });

  final TrackSkin skin;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      // A transparent border of the same width when unselected, so choosing
      // one does not shift the row.
      side: BorderSide(
        color: selected ? colors.onPrimaryContainer : Colors.transparent,
        width: AppBorders.selected,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: skin.name,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerHigh,
        shape: shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTapTargets.primary),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.sm,
                children: [
                  SizedBox.square(
                    dimension: _pictureSize,
                    child: CustomPaint(painter: _StartPainter(skin)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          skin.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.check_circle,
                          size: AppIconSizes.standard,
                          color: foreground,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints what [skin] waits at the start port with.
class _StartPainter extends CustomPainter {
  _StartPainter(this.skin);

  final TrackSkin skin;

  @override
  void paint(Canvas canvas, Size size) =>
      skin.paintStart(canvas, Offset.zero & size, departed: false);

  @override
  // A skin has no equality and the picker rebuilds only on a choice, a
  // profile switch or a brightness change, each of which can change the skin.
  bool shouldRepaint(_StartPainter oldDelegate) => true;
}
