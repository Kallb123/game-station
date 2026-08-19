// `SystemHaptics`'s own gates (`PLAN-phase-5.md` §4.5, PR 5's done
// criterion): `settings.haptics` and the platform check both silence it, and
// each is checked against the actual platform channel `HapticFeedback` calls
// through — `RecordingHaptics` cannot answer this, because it fakes
// `AppHaptics` rather than exercising the real implementation over it.

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

  test('selectionClick reaches the platform channel on Android', () async {
    await runningOn(TargetPlatform.android, () async {
      SystemHaptics().selectionClick();
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
    });
  });

  test('haptics: false silences every one of the three calls', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(haptics: false));

      haptics.selectionClick();
      haptics.lightImpact();
      haptics.mediumImpact();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });

  test('nothing fires on macOS, regardless of the setting', () async {
    await runningOn(TargetPlatform.macOS, () async {
      final haptics = SystemHaptics()
        ..applySettings(const AppSettings(haptics: true));

      haptics.selectionClick();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });

  test('a mute takes effect immediately, not only on the next call', () async {
    await runningOn(TargetPlatform.android, () async {
      final haptics = SystemHaptics();

      haptics.selectionClick();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));

      haptics.applySettings(const AppSettings(haptics: false));
      haptics.selectionClick();
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1), reason: 'the second click should be muted');
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
