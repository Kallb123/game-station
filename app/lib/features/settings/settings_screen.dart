import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/tokens.dart';

/// The heading over the three theme choices.
const String themeSectionLabel = 'Colours';

/// How each theme choice is drawn.
///
/// Public because the tests name the same strings the screen does. The order
/// here is the order they appear in: `system` first, since it is the default and
/// the one that needs no decision.
const Map<ThemeChoice, ({String label, IconData icon})> themeChoices =
    <ThemeChoice, ({String label, IconData icon})>{
      ThemeChoice.system: (label: 'Automatic', icon: Icons.brightness_auto),
      ThemeChoice.day: (label: 'Day', icon: Icons.light_mode),
      ThemeChoice.night: (label: 'Night', icon: Icons.dark_mode),
    };

/// The label on each switch.
///
/// Named in words a child reads rather than in the words the code uses:
/// `reduceMotion` is "Less moving about", because that is what changes.
const String soundLabel = 'Sounds';
const String hapticsLabel = 'Buzzing';
const String showTimerLabel = 'Show the timer';
const String reduceMotionLabel = 'Less moving about';

/// What the grown-up changes, and the child changes back.
///
/// Five controls, and deliberately not six: `music` is in schema v1 but gets no
/// control until phase 5 (PLAN-phase-1.md §2), because nothing plays music yet
/// and a switch that does nothing is worse than an absent one.
///
/// Each row is a switch with a glyph and a label. No section headers over the
/// four switches: four rows do not need to be grouped, and a heading is one
/// more thing to read.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // Read when the switch is flipped rather than when the screen is built, so
    // nothing here holds a repository from a scope that has since been replaced.
    void update(AppSettings next) =>
        ref.read(progressRepositoryProvider).updateSettings(next);

    return ScreenScaffold(
      title: 'Settings',
      child: ListView(
        children: [
          _SettingSwitch(
            icon: Icons.volume_up,
            label: soundLabel,
            value: settings.sound,
            onChanged: (value) => update(settings.copyWith(sound: value)),
          ),
          // Hidden rather than disabled where there is nothing to vibrate: a
          // control that does nothing on the device in front of you is worse
          // than an absent one (PLAN-phase-1.md §4.5).
          if (_deviceCanVibrate)
            _SettingSwitch(
              icon: Icons.vibration,
              label: hapticsLabel,
              value: settings.haptics,
              onChanged: (value) => update(settings.copyWith(haptics: value)),
            ),
          _SettingSwitch(
            icon: Icons.timer_outlined,
            label: showTimerLabel,
            value: settings.showTimer,
            onChanged: (value) => update(settings.copyWith(showTimer: value)),
          ),
          _SettingSwitch(
            icon: Icons.slow_motion_video,
            label: reduceMotionLabel,
            value: settings.reduceMotion,
            onChanged: (value) =>
                update(settings.copyWith(reduceMotion: value)),
          ),
          const SizedBox(height: AppSpacing.xl),
          _ThemeSection(
            chosen: settings.theme,
            onChosen: (theme) => update(settings.copyWith(theme: theme)),
          ),
        ],
      ),
    );
  }
}

/// Whether this device has anything to buzz with.
///
/// `defaultTargetPlatform` rather than `dart:io`'s `Platform`, so that a test can
/// override it and so the answer is right on a web build, which `dart:io` cannot
/// even be imported for.
///
/// Private on purpose: phase 5 is the one that has to know whether a *vibration*
/// will actually happen, which is a question about the plugin and the device's
/// hardware, not about the platform. This is only what the screen needs to decide
/// whether to draw a row.
bool get _deviceCanVibrate => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  TargetPlatform.fuchsia ||
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

/// One switch, sized for a child's aim.
///
/// A [SwitchListTile] rather than a row with a [Switch] in it: the whole row
/// toggles, which is a target the width of the screen instead of the width of
/// the switch, and a screen reader announces the label and the state as one
/// control rather than two.
class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      // A floor, not a height: the tile still grows when the label wraps at a
      // large text scale. Primary rather than minimum because these rows are
      // what the screen is for, and a `ListTile` takes no size from the button
      // themes that hold the rest of the app above the floor (`theme.dart`).
      minTileHeight: AppTapTargets.primary,
      minVerticalPadding: AppSpacing.md,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium),
      secondary: Icon(icon, size: AppIconSizes.large),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    );
  }
}

/// Day, night, or whatever the device is doing.
///
/// Three buttons rather than a dropdown or a segmented control: the chosen one
/// is visible without opening anything, each is a [BigButton] and so clears the
/// primary tap target, and selection is a border and a check as well as a
/// colour (`big_button.dart`).
class _ThemeSection extends StatelessWidget {
  const _ThemeSection({required this.chosen, required this.onChosen});

  final ThemeChoice chosen;
  final ValueChanged<ThemeChoice> onChosen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Semantics(
            header: true,
            child: Text(
              themeSectionLabel,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        for (final MapEntry(key: choice, value: (:label, :icon))
            in themeChoices.entries)
          BigButton(
            icon: icon,
            label: label,
            selected: choice == chosen,
            onPressed: () => onChosen(choice),
          ),
      ],
    );
  }
}
