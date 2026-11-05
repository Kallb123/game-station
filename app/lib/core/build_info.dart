// Which build is running: the version it was cut from, and when it was
// compiled. The settings screen shows it, so that "which build have you got?"
// has an answer a grown-up can read off the tablet.
//
// Both values arrive as compile-time `--dart-define`s rather than from a
// plugin. Reading pubspec's version at runtime means `package_info_plus`, and
// every dependency here is weighed by what it drags in (AGENTS.md) — two
// defines cost nothing, need no platform channel, and behave identically on all
// six targets including web.
//
// There is deliberately no fallback version compiled into this file. A
// hard-coded '0.1.0+1' would be a second home for a number that already lives
// in app/pubspec.yaml, and its failure mode is a build that confidently reports
// the version before last. Instead, a build that was not stamped says it was
// not stamped, and `tool/build_defines.sh` reads the version out of pubspec so
// that a stamped one cannot disagree with it.
//
// The flavour is the one other thing a build knows about itself. It exists so
// that the footer can say *home build*: with one app id and one label shared by
// both builds, the footer is the only way to tell which build a tablet has.
// Which content a build holds is decided by what was bundled into it
// (PLAN-phase-10-quiz.md §4.9), never by this flag, so nothing should gate
// content on it.

import 'package:flutter/services.dart' show appFlavor;

/// The define carrying the pubspec version, `0.1.0+1` shaped.
const String versionDefine = 'APP_VERSION';

/// The define carrying the compile time, as an ISO-8601 UTC instant.
const String buildTimeDefine = 'BUILD_TIME';

/// The flavour name of the build cut for home use, with the private packs
/// bundled.
const String privateFlavor = 'private';

/// What is shown for a build that was compiled without the defines — `flutter
/// run` from a checkout, and every test.
const String developmentLabel = 'Development build';

/// What the footer appends for a home build.
const String homeBuildLabel = 'home build';

/// What build this is, and how to say it in one line.
class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.timestamp,
    this.flavor,
  });

  /// The build the running binary was compiled as.
  ///
  /// `const`, so the strings are baked in at compile time and an unstamped
  /// build carries the empty ones rather than reading anything at startup.
  static const BuildInfo current = BuildInfo(
    version: String.fromEnvironment(versionDefine),
    timestamp: String.fromEnvironment(buildTimeDefine),
    flavor: appFlavor,
  );

  /// The pubspec version this build was compiled from, or empty when it was
  /// not stamped.
  final String version;

  /// When it was compiled, as an ISO-8601 UTC instant, or empty when it was not
  /// stamped.
  ///
  /// Held as the raw string rather than as a [DateTime] so that [current] can
  /// stay `const`: parsing is not a constant expression.
  final String timestamp;

  /// The `--flavor` the build was made with, or null when it was made without
  /// one, as on every platform but Android and in every test.
  final String? flavor;

  /// Whether this is the build cut for home use.
  ///
  /// For the footer only: the packs a build holds are whatever was bundled, and
  /// a check of this flag must never stand in for that.
  bool get isHomeBuild => flavor == privateFlavor;

  /// Whether this build carries no stamp at all.
  bool get isDevelopment => version.isEmpty;

  /// When it was compiled, or null when [timestamp] is absent or unparseable.
  ///
  /// A stamp that does not parse degrades to showing the version alone rather
  /// than throwing: the footer is the least important thing on the screen, and
  /// nothing here is worth a crash in front of a child.
  DateTime? get builtAt => DateTime.tryParse(timestamp)?.toUtc();

  /// The one line the settings footer shows.
  ///
  /// The home marker goes on every form, so that a local private build with no
  /// stamp still says what it is.
  String get label =>
      isHomeBuild ? '$_stampLabel · $homeBuildLabel' : _stampLabel;

  String get _stampLabel {
    if (isDevelopment) return developmentLabel;
    final at = builtAt;
    if (at == null) return 'Version $version';
    return 'Version $version · built ${_formatUtc(at)}';
  }
}

/// The build time as `15 Aug 2026, 13:07 UTC`.
///
/// Written by hand rather than with `intl`, which is a dependency and a
/// localisation story this app does not have yet.
///
/// Left in UTC rather than converted to the device's zone: the point of the
/// stamp is telling two builds apart, and a value that reads differently on the
/// tablet and on the laptop that built it defeats that. The minute is included
/// for the same reason — two builds on one afternoon are the normal case.
String _formatUtc(DateTime at) {
  final month = _months[at.month - 1];
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '${at.day} $month ${at.year}, $hour:$minute UTC';
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
