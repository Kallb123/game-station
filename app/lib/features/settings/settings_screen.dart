import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/build_info.dart';
import '../../core/haptics.dart' show deviceCanVibrate;
import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/layout.dart';
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

/// The heading over the two mistake-feedback choices.
const String mistakeSectionLabel = 'Wrong numbers';

/// How each mistake-feedback choice is drawn, `immediate` first because it is
/// the default (`PLAN.md` §3.7).
///
/// Named by what happens rather than by what it is called in the schema: a
/// child reads "Tell me at the end", not `atCompletion`.
const Map<MistakeFeedback, ({String label, IconData icon})>
mistakeFeedbackChoices = <MistakeFeedback, ({String label, IconData icon})>{
  MistakeFeedback.immediate: (
    label: 'Tell me straight away',
    icon: Icons.error_outline,
  ),
  MistakeFeedback.atCompletion: (
    label: 'Tell me at the end',
    icon: Icons.flag_outlined,
  ),
};

/// Who the mistake setting is being changed for.
///
/// It is the one setting on this screen that belongs to a profile rather than
/// to the device (`save_data.dart`), and a grown-up who changed it for one
/// child and expected it to hold for the other would find out on the day it
/// mattered. Naming the child on the control is the mechanism that says so.
String mistakeSectionCaption(String name) => 'For $name';

/// The label on each switch, and on the haptics slider.
///
/// Named in words a child reads rather than in the words the code uses:
/// `reduceMotion` is "Less moving about", because that is what changes.
const String soundLabel = 'Sounds';
const String hapticsLabel = 'Buzzing';
const String showTimerLabel = 'Show the timer';
const String reduceMotionLabel = 'Less moving about';
const String allowPhotoImportLabel = 'Add a photo to draw on';

/// How each [HapticsLevel] reads on the slider and in its own live label.
///
/// Public because the tests name the same strings the screen does.
const Map<HapticsLevel, String> hapticsLevelLabels = {
  HapticsLevel.off: 'Off',
  HapticsLevel.low: 'Low',
  HapticsLevel.medium: 'Medium',
  HapticsLevel.high: 'High',
};

/// What the grown-up changes, and the child changes back.
///
/// Seven controls, and deliberately not eight: `music` is in schema v1 but
/// gets no control at all, because there is no music anywhere in the app to
/// switch off (`PLAN-phase-5.md` §3.4, §4.6, the owner's instruction) and a
/// switch that does nothing is worse than an absent one.
///
/// Four of the five rows are a switch with a glyph and a label; **Buzzing**
/// is a slider, because a device pass found a plain on/off too coarse to
/// answer "how hard" (`PLAN-phase-5.md` §4.5) — `core/haptics.dart` has the
/// four levels it moves between. No section headers over the five rows: five
/// rows do not need to be grouped, and a heading is one more thing to read.
/// The two choice sections below them do have headings, because a set of
/// buttons with no name is a question with no question.
///
/// **Add a photo to draw on** is the one row that gates a child rather than
/// describing a preference of theirs (`PLAN-phase-8.md` §1, §3): off by
/// default, so importing a photo stays invisible until a grown-up finds this
/// switch and turns it on.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(activeProfileProvider);

    // Read when the switch is flipped rather than when the screen is built, so
    // nothing here holds a repository from a scope that has since been replaced.
    void update(AppSettings next) =>
        ref.read(progressRepositoryProvider).updateSettings(next);

    return ScreenScaffold(
      title: 'Settings',
      child: ContentWidthCap(
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
            if (deviceCanVibrate)
              _HapticsSlider(
                value: settings.hapticsLevel,
                onChanged: (level) =>
                    update(settings.copyWith(hapticsLevel: level)),
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
            _SettingSwitch(
              icon: Icons.add_photo_alternate_outlined,
              label: allowPhotoImportLabel,
              value: settings.allowPhotoImport,
              onChanged: (value) =>
                  update(settings.copyWith(allowPhotoImport: value)),
            ),
            const SizedBox(height: AppSpacing.xl),
            _ChoiceSection<ThemeChoice>(
              label: themeSectionLabel,
              choices: themeChoices,
              chosen: settings.theme,
              onChosen: (theme) => update(settings.copyWith(theme: theme)),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Last, and the only control here that belongs to a profile rather
            // than to the device: the sections above are about the tablet, and
            // this one is about the child holding it.
            _ChoiceSection<MistakeFeedback>(
              label: mistakeSectionLabel,
              caption: mistakeSectionCaption(profile.name),
              choices: mistakeFeedbackChoices,
              chosen: profile.mistakeFeedback,
              onChosen: (value) => ref
                  .read(progressRepositoryProvider)
                  .setMistakeFeedback(profile.id, value),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _BuildFooter(),
          ],
        ),
      ),
    );
  }
}

/// Which build this is, at the bottom of the last screen a child goes looking
/// at — so the answer to "what version have you got?" is on the tablet rather
/// than in a store listing this app is not in yet.
///
/// The smallest type on the screen and the quietest colour, because it is the
/// one thing here that is not for the player: nothing on this line is worth a
/// child's attention, and everything above it is. It is a plain [Text] rather
/// than a control — there is nothing to tap, and a tappable version number is
/// how a child ends up somewhere a grown-up has to get them out of.
///
/// Last in the [ListView] rather than pinned under it: pinning costs the height
/// on every screen, which at 200% text scale is height the settings themselves
/// need.
class _BuildFooter extends StatelessWidget {
  const _BuildFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Text(
        BuildInfo.current.label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

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

/// **Buzzing**'s own row: a glyph and a label like [_SettingSwitch], the
/// current level spelled out beside them, and a four-stop [Slider] below
/// rather than a switch.
///
/// The slider sits inside its own [SizedBox] at [AppTapTargets.min] rather
/// than whatever height `Slider` defaults to: the widget's hit-test area is
/// its full layout box, so this is what actually enlarges the strip a child
/// can drag from, not only what it looks like.
class _HapticsSlider extends StatelessWidget {
  const _HapticsSlider({required this.value, required this.onChanged});

  final HapticsLevel value;
  final ValueChanged<HapticsLevel> onChanged;

  static const List<HapticsLevel> _levels = HapticsLevel.values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _levels.indexOf(value).toDouble();

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTapTargets.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.vibration, size: AppIconSizes.large),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(hapticsLabel, style: theme.textTheme.titleMedium),
                ),
                Text(
                  hapticsLevelLabels[value]!,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            SizedBox(
              height: AppTapTargets.min,
              child: Slider(
                value: index,
                min: 0,
                max: (_levels.length - 1).toDouble(),
                divisions: _levels.length - 1,
                label: hapticsLevelLabels[value],
                semanticFormatterCallback: (raw) =>
                    hapticsLevelLabels[_levels[raw.round()]]!,
                onChanged: (raw) => onChanged(_levels[raw.round()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One question, answered by one of a handful of buttons.
///
/// Buttons rather than a dropdown or a segmented control: the chosen one is
/// visible without opening anything, each is a [BigButton] and so clears the
/// primary tap target, and selection is a border and a check as well as a
/// colour (`big_button.dart`).
///
/// Generic over what is being chosen, because the screen asks two questions
/// this shape — the theme and the mistake feedback — and two copies of it would
/// be two places for the tap-target rule and the selection drawing to drift
/// apart.
class _ChoiceSection<T> extends StatelessWidget {
  const _ChoiceSection({
    required this.label,
    required this.choices,
    required this.chosen,
    required this.onChosen,
    this.caption,
  });

  /// The heading over the buttons.
  final String label;

  /// A line under the heading, where the question needs one.
  final String? caption;

  /// What can be chosen, in the order it is offered.
  final Map<T, ({String label, IconData icon})> choices;

  /// Which one is chosen now.
  final T chosen;

  /// Called with the choice a tap landed on.
  final ValueChanged<T> onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = this.caption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.md,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          // Merged, so a screen reader announces the heading and the line under
          // it as one thing rather than as two consecutive labels.
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(label, style: theme.textTheme.titleLarge),
                ),
                if (caption != null)
                  Text(caption, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        for (final MapEntry(key: choice, value: (:label, :icon))
            in choices.entries)
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
