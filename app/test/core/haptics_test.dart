// `SystemHaptics`'s own gates and its ladder (`PLAN-phase-5.md` §4.5, PR 5's
// done criterion): `AppSettings.hapticsLevel` and the platform check both
// silence it, and each level climbs the four-rung ladder — repeating a pulse
// once an event's own rung hits the ceiling — checked against the actual
// platform channel `HapticFeedback` calls through. `RecordingHaptics` cannot
// answer any of this: it fakes `AppHaptics` rather than exercising the real
// implementation over it.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/save_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  /// Runs [body] as if the app were on [platform], resetting the override
  /// afterwards even if [body] throws (`settings_screen_test.dart` does the
  /// same, for the same reason: a tear-down runs after the framework's own
  /// "a debug variable changed" check, which would otherwise fail the test
  /// and leak the override into the next one).
  Future<void> runningOn(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// The `HapticFeedbackType` each recorded call named, in order — every
  /// `HapticFeedback` method invokes the same channel method with this as
  /// its one argument (this file's header names the source).
  List<String> typesFired() =>
      calls.map((call) => call.arguments as String).toList();

  test('off fires nothing, for any of the three events', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(hapticsLevel: HapticsLevel.off));

      haptics.tap();
      haptics.mistake();
      haptics.impact();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });

  test('nothing fires on macOS, regardless of the level', () async {
    await runningOn(TargetPlatform.macOS, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(hapticsLevel: HapticsLevel.high));

      haptics.impact();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });

  test('low pushes every event up one rung from the ladder\'s floor', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(hapticsLevel: HapticsLevel.low));

      haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.lightImpact']);
      calls.clear();

      haptics.mistake();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.mediumImpact']);
      calls.clear();

      haptics.impact();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.heavyImpact']);
    });
  });

  test('medium pushes tap and mistake up again, and repeats impact once at the '
      'ceiling', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(hapticsLevel: HapticsLevel.medium));

      haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.mediumImpact']);
      calls.clear();

      haptics.mistake();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.heavyImpact']);
      calls.clear();

      haptics.impact();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(typesFired(), [
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });
  });

  test('high repeats mistake twice and impact three times', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(hapticsLevel: HapticsLevel.high));

      haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(typesFired(), ['HapticFeedbackType.heavyImpact']);
      calls.clear();

      haptics.mistake();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(typesFired(), List.filled(2, 'HapticFeedbackType.heavyImpact'));
      calls.clear();

      haptics.impact();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(typesFired(), List.filled(3, 'HapticFeedbackType.heavyImpact'));
    });
  });

  test('a mute takes effect immediately, not only on the next call', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics();

      haptics.tap();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));

      haptics.applySettings(const AppSettings(hapticsLevel: HapticsLevel.off));
      haptics.tap();
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1), reason: 'the second tap should be muted');
    });
  });

  group('deviceCanVibrate', () {
    test('true on the two platforms with a motor', () async {
      await runningOn(TargetPlatform.android, () async {
        expect(deviceCanVibrate, isTrue);
      });
      await runningOn(TargetPlatform.iOS, () async {
        expect(deviceCanVibrate, isTrue);
      });
    });

    test('false on every desktop platform', () async {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        await runningOn(platform, () async {
          expect(deviceCanVibrate, isFalse, reason: '$platform');
        });
      }
    });
  });
}
