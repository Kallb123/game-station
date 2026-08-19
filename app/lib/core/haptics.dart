// The mute-and-platform-aware wrapper over `HapticFeedback`
// (`PLAN-phase-5.md` §4.5). Same shape as `core/audio/app_audio.dart`: an
// interface, a real implementation, a silent fake for tests, and a provider.
// One file rather than a directory, unlike `core/audio/` — there is one
// ladder to climb, not fifteen motifs to name.
//
// PR 5 first shipped a plain on/off switch calling three of
// `HapticFeedback`'s six methods, on the understanding that the other three
// — `vibrate()` and `heavyImpact()` among them — reached Android's
// `Vibrator` and so needed `android.permission.VIBRATE`. A device pass found
// every one of those three calls too faint to reliably feel, which sent that
// belief back for a check: the engine's own
// `PlatformPlugin.vibrateHapticFeedback` (`shell/platform/android/io/flutter/
// plugin/platform/PlatformPlugin.java`) routes all six through
// `View.performHapticFeedback` with a different `HapticFeedbackConstants`
// value apiece — `heavyImpact` gets `CONTEXT_CLICK`, the bare `vibrate()`
// gets `LONG_PRESS` — and none of them touch `Vibrator`. The belief was
// wrong; nothing here needs a permission, so [SystemHaptics] climbs a
// four-rung ladder instead of stopping at three, and
// `haptics_call_site_test.dart` is the guard that actually matters: every
// call stays inside this one file, which is what keeps a mute or a platform
// gate from being skippable by mistake, not which of the six names get used.

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show HapticFeedback, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage/providers.dart';
import 'storage/save_data.dart';

/// Whether this device has a motor to buzz. `defaultTargetPlatform` rather
/// than `dart:io`'s `Platform`, so a test can override it and the answer is
/// right on a web build, which `dart:io` cannot even be imported for.
///
/// Moved here from `settings_screen.dart`, which now imports it: that screen
/// needs the same answer to decide whether **Buzzing** is worth a row, and a
/// second copy of this switch would be a second place for the platform list
/// to drift out of step with [SystemHaptics]'s own gate.
bool get deviceCanVibrate => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  TargetPlatform.fuchsia ||
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => false,
};

/// Buzzes the device for one of three events, muted and gated exactly where
/// `PLAN-phase-5.md` §4.5 requires it: nothing fires with
/// `AppSettings.hapticsLevel` at [HapticsLevel.off], and nothing fires on a
/// platform with no motor.
///
/// Named for what happened, not for which `HapticFeedback` call answers it —
/// [SystemHaptics] moves that mapping as [HapticsLevel] rises, so a fixed
/// method name tied to one platform call would be a lie within a level or
/// two.
abstract interface class AppHaptics {
  /// A digit or a note entered, or a pad button pressed. The lightest event,
  /// fired hundreds of times a puzzle.
  void tap();

  /// A wrong digit on an `immediate` profile — *instead of* [tap], the one
  /// place a child should feel a difference and still not a punishment.
  void mistake();

  /// The ship destroyed, and game over: the two moments in an Invaders run
  /// worth feeling.
  void impact();

  /// The settings changed: a mute takes effect immediately, mid-puzzle.
  void applySettings(AppSettings settings);
}

/// The real implementation, over `HapticFeedback`.
///
/// The check is here, inside the wrapper, rather than at each of the four
/// call sites — the same reason `AppAudio.play` checks `settings.sound`
/// itself (`PLAN-phase-5.md` §4.2): a call site cannot forget a check it
/// never has to make.
class SystemHaptics implements AppHaptics {
  HapticsLevel _level = HapticsLevel.low;

  @override
  void applySettings(AppSettings settings) => _level = settings.hapticsLevel;

  @override
  void tap() => _fire(0);

  @override
  void mistake() => _fire(1);

  @override
  void impact() => _fire(2);

  /// Every rung [_fire] can reach, lightest first. All four route through
  /// `View.performHapticFeedback` (this file's header), so the ladder is
  /// free to use every one of them rather than stopping short.
  static const List<Future<void> Function()> _ladder = [
    HapticFeedback.selectionClick,
    HapticFeedback.lightImpact,
    HapticFeedback.mediumImpact,
    HapticFeedback.heavyImpact,
  ];

  /// How far up [_ladder] each non-off level pushes a tier — [tap] starts at
  /// rung 0, so [HapticsLevel.low]'s offset of 1 is the "turn it up one
  /// notch" fix a device pass asked for, applied before the slider even
  /// moves off its default. [HapticsLevel.off] never reaches [_fire].
  static const Map<HapticsLevel, int> _offset = {
    HapticsLevel.low: 1,
    HapticsLevel.medium: 2,
    HapticsLevel.high: 3,
  };

  /// The gap between repeated pulses, for a tier whose rung has already hit
  /// the ladder's ceiling — [impact] starts at rung 2, so
  /// [HapticsLevel.medium] already maxes it out at rung 4-clamped-to-3, and
  /// a second pulse is the only way left for [HapticsLevel.high] to make it
  /// feel any stronger.
  static const Duration _pulseGap = Duration(milliseconds: 60);

  void _fire(int tier) {
    if (_level == HapticsLevel.off || !deviceCanVibrate) return;
    final wanted = tier + _offset[_level]!;
    final index = wanted.clamp(0, _ladder.length - 1);
    unawaited(_pulse(index, 1 + (wanted - index)));
  }

  Future<void> _pulse(int index, int times) async {
    for (var i = 0; i < times; i++) {
      if (i > 0) await Future<void>.delayed(_pulseGap);
      await _ladder[index]();
    }
  }
}

/// No-op. What every widget test gets by default (`test/app_harness.dart`),
/// so nothing here needs a device to run.
class SilentHaptics implements AppHaptics {
  const SilentHaptics();

  @override
  void tap() {}

  @override
  void mistake() {}

  @override
  void impact() {}

  @override
  void applySettings(AppSettings settings) {}
}

/// The haptics feedback every screen reaches through.
///
/// Real by default; `test/app_harness.dart` overrides it with a
/// [SilentHaptics] so a widget test needs no device.
///
/// [AppHaptics.applySettings] is applied once from the current settings and
/// again on every change, so moving the **Buzzing** slider takes effect
/// immediately rather than waiting for the next buzz.
final Provider<AppHaptics> appHapticsProvider = Provider<AppHaptics>((ref) {
  final haptics = SystemHaptics();
  haptics.applySettings(ref.read(settingsProvider));
  ref.listen(
    settingsProvider,
    (_, settings) => haptics.applySettings(settings),
  );
  return haptics;
});
