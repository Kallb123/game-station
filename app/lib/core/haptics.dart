// The mute-and-platform-aware wrapper over `HapticFeedback`
// (`PLAN-phase-5.md` §4.5). Same shape as `core/audio/app_audio.dart`: an
// interface, a real implementation, a silent fake for tests, and a provider.
// One file rather than a directory, unlike `core/audio/` — there is one
// enum's worth of call, not fifteen motifs to name.

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

/// Buzzes the device, muted and gated exactly where `PLAN-phase-5.md` §4.5
/// requires it: nothing fires with `settings.haptics` false, and nothing
/// fires on a platform with no motor.
///
/// Only three of `HapticFeedback`'s methods are named here —
/// [selectionClick], [lightImpact] and [mediumImpact] — because those three
/// route through `View.performHapticFeedback` on Android, which needs no
/// permission. `HapticFeedback.vibrate()` and `.heavyImpact()` reach
/// `Vibrator`, which needs `android.permission.VIBRATE`; adding a permission
/// to this app costs the no-network, no-tracking promise `PLAN.md` §1 makes
/// as a whole (`PLAN-phase-5.md` §3.5). `no_vibrate_test.dart` bans both
/// names in `lib/` from the other side.
abstract interface class AppHaptics {
  /// A digit or a note entered, or a pad button pressed. The lightest thing
  /// available, fired hundreds of times a puzzle.
  void selectionClick();

  /// A wrong digit on an `immediate` profile — *instead of* [selectionClick],
  /// the one place a child should feel a difference and still not a
  /// punishment.
  void lightImpact();

  /// The ship destroyed, and game over: the two moments in an Invaders run
  /// worth feeling.
  void mediumImpact();

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
  bool _haptics = true;

  @override
  void applySettings(AppSettings settings) => _haptics = settings.haptics;

  @override
  void selectionClick() => _fire(HapticFeedback.selectionClick);

  @override
  void lightImpact() => _fire(HapticFeedback.lightImpact);

  @override
  void mediumImpact() => _fire(HapticFeedback.mediumImpact);

  void _fire(Future<void> Function() call) {
    if (!_haptics || !deviceCanVibrate) return;
    unawaited(call());
  }
}

/// No-op. What every widget test gets by default (`test/app_harness.dart`),
/// so nothing here needs a device to run.
class SilentHaptics implements AppHaptics {
  const SilentHaptics();

  @override
  void selectionClick() {}

  @override
  void lightImpact() {}

  @override
  void mediumImpact() {}

  @override
  void applySettings(AppSettings settings) {}
}

/// The haptics feedback every screen reaches through.
///
/// Real by default; `test/app_harness.dart` overrides it with a
/// [SilentHaptics] so a widget test needs no device.
///
/// [AppHaptics.applySettings] is applied once from the current settings and
/// again on every change, so turning **Buzzing** off takes effect immediately
/// rather than waiting for the next buzz.
final Provider<AppHaptics> appHapticsProvider = Provider<AppHaptics>((ref) {
  final haptics = SystemHaptics();
  haptics.applySettings(ref.read(settingsProvider));
  ref.listen(
    settingsProvider,
    (_, settings) => haptics.applySettings(settings),
  );
  return haptics;
});
