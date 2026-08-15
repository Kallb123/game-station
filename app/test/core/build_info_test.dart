// What the settings footer says about the running build, and — the part worth
// having — that the script which stamps a build still agrees with the code that
// reads the stamp.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/build_info.dart';

void main() {
  group('label', () {
    test('names the version and when it was built', () {
      const info = BuildInfo(
        version: '0.1.0+1',
        timestamp: '2026-08-15T13:07:41Z',
      );

      expect(info.isDevelopment, isFalse);
      expect(info.label, 'Version 0.1.0+1 · built 15 Aug 2026, 13:07 UTC');
    });

    test('reports the build time in UTC whatever zone it was stamped in', () {
      // The same instant as above, written from a machine two hours ahead. A
      // footer that read differently depending on where the build was cut would
      // be no use for telling two builds apart.
      const info = BuildInfo(
        version: '0.1.0+1',
        timestamp: '2026-08-15T15:07:41+02:00',
      );

      expect(info.label, 'Version 0.1.0+1 · built 15 Aug 2026, 13:07 UTC');
    });

    test('falls back to the version alone when the stamp does not parse', () {
      const info = BuildInfo(version: '0.1.0+1', timestamp: 'yesterday-ish');

      expect(info.builtAt, isNull);
      expect(info.label, 'Version 0.1.0+1');
    });

    test(
      'says so rather than inventing a version when nothing was stamped',
      () {
        const info = BuildInfo(version: '', timestamp: '');

        expect(info.isDevelopment, isTrue);
        expect(info.label, developmentLabel);
      },
    );
  });

  // The guard. `build_info.dart` reads two defines by name and the shell script
  // writes two defines by name, and nothing but this test connects the two
  // strings: rename one and every build goes on succeeding while quietly
  // shipping "Development build" to the release page. That is the failure mode
  // AGENTS.md wants a test for, so the test runs the real script and reads the
  // real flags rather than asserting the names against a copy of themselves.
  group('tool/build_defines.sh', () {
    late Map<String, String> defines;

    setUpAll(() {
      // `flutter test` runs from app/, so the script is one level up.
      final result = Process.runSync('bash', <String>[
        '../tool/build_defines.sh',
      ]);
      expect(result.exitCode, 0, reason: 'the script failed: ${result.stderr}');

      defines = <String, String>{};
      for (final flag in (result.stdout as String).trim().split(' ')) {
        // Split on the first `=` after the flag name: a value may contain one,
        // and `0.1.0+1` is a value today that could.
        final body = flag.replaceFirst('--dart-define=', '');
        final separator = body.indexOf('=');
        expect(separator, greaterThan(0), reason: 'unparseable flag: $flag');
        defines[body.substring(0, separator)] = body.substring(separator + 1);
      }
    });

    test('emits the defines build_info.dart reads', () {
      expect(
        defines.keys,
        containsAll(<String>[versionDefine, buildTimeDefine]),
      );
    });

    test('stamps a build that reports a version and a build time', () {
      final info = BuildInfo(
        version: defines[versionDefine]!,
        timestamp: defines[buildTimeDefine]!,
      );

      expect(info.isDevelopment, isFalse);
      expect(info.builtAt, isNotNull);
      expect(info.label, startsWith('Version '));
      expect(info.label, contains(' UTC'));
    });

    test('takes the version from pubspec, so the two cannot disagree', () {
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final version = pubspec
          .firstWhere((line) => line.startsWith('version:'))
          .substring('version:'.length)
          .trim();

      expect(defines[versionDefine], version);
    });
    // Windows has no bash, and this checks a script only the CI runners and
    // developer machines run. Skipped rather than rewritten in Dart: what is
    // being checked is the shell script itself.
  }, skip: Platform.isWindows ? 'needs bash' : null);
}
