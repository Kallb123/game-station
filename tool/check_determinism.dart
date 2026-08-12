// Enforces the puzzle engine's determinism rules in the build rather than by
// convention (`PLAN-phase-2.md` §1): nothing in `packages/puzzle_engine/lib`
// may draw on `dart:math`'s `Random`, read a clock, or iterate a `Map`'s keys,
// values or entries.
//
// Saved progress stores puzzle IDs rather than grids, so a generator whose
// output depends on anything but its ID turns a solved puzzle into a different
// unsolved one — and it does it quietly, on someone else's machine, months
// later. The golden files catch the effect; this catches the cause, at the line
// that introduced it.
//
// Run from the repository root:
//
//   dart tool/check_determinism.dart
//   dart tool/check_determinism.dart --self-test
//
// Exits 0 when clean, 1 with a report of every violation otherwise.
//
// This is a textual scan, so it can be evaded — `Function.apply` on a name
// built at runtime, an alias for `DateTime`. It is a tripwire for the accident,
// not a sandbox against intent; the golden files are the backstop.
//
// A reviewed exception is marked with `// determinism: ok` on the offending
// line or the line above it, which keeps the exception next to its reason
// instead of in a list at the top of this file.

import 'dart:io';

// The comment stripper is shared with the offline check rather than copied:
// it is the subtle part of both scanners, it has a self-test of its own there,
// and a second copy would be a second thing to keep in step. Without it, a doc
// comment explaining why `dart:math` is banned would trip the ban.
import 'check_offline.dart' show importUris, relative, stripComments;

/// The directory whose contents have to be deterministic.
///
/// Only `lib/`: the package's own `tool/` scripts and its tests may time
/// things and use `dart:math` freely, since nothing they do reaches a player's
/// save file.
const String scannedDir = 'packages/puzzle_engine/lib';

/// The marker that opts one line out of the scan.
const String optOut = 'determinism: ok';

/// Imports that make output depend on something other than the puzzle ID.
///
/// `dart:math`'s `Random` is the whole reason this check exists; the rest of
/// the library (`min`, `max`, `sqrt`) is harmless, but the engine has no use
/// for it, and banning the import outright is a rule that can be checked
/// without resolving names.
const Set<String> bannedImports = {'dart:math'};

/// Clock reads. Output that varies by the day it was generated on is exactly
/// the failure the golden files exist to catch, caught earlier.
///
/// `DateTime.timestamp()` is here as well as `DateTime.now()` because it is the
/// same clock behind a different name, and a ban that only knows one of the two
/// is a ban on typing the familiar one.
const List<String> bannedClockApis = ['DateTime.now', 'DateTime.timestamp'];

/// Elapsed-time measurement. A generator that gives up after N milliseconds
/// produces different puzzles on a slow tablet than on a fast one.
const List<String> bannedTypes = ['Stopwatch'];

/// Map and set views whose iteration order is not part of the language's
/// guarantees for every implementation, and which are the usual way an
/// unspecified order sneaks into a search.
const List<String> orderDependentViews = ['keys', 'values', 'entries'];

/// Each banned name paired with the pattern that finds it and the reason it is
/// banned, compiled once rather than once per line of every file.
///
/// The clock patterns tolerate spaces around the dot, so `DateTime . now()`
/// does not walk past a check whose whole job is to be hard to walk past.
final List<(String name, RegExp pattern, String reason)> bannedApiPatterns = [
  for (final api in bannedClockApis)
    (
      api,
      RegExp('\\b${api.replaceAll('.', r'\s*\.\s*')}\\b'),
      'generation may not read a clock',
    ),
  for (final type in bannedTypes)
    (type, RegExp('\\b$type\\b'), 'generation may not measure time'),
];

/// A member access to one of [orderDependentViews], capturing the receiver so
/// that a type's `values` can be told from a map's.
final RegExp orderDependentAccess = RegExp(
  '([A-Za-z_\$][A-Za-z0-9_\$]*)?\\s*\\.\\s*'
  '(${orderDependentViews.join('|')})\\b',
);

/// A receiver that names a type rather than a variable.
final RegExp typeReceiver = RegExp('^[A-Z]');

void main(List<String> args) {
  if (args.contains('--self-test')) {
    // `exitCode` rather than `exit()`: `exit()` can drop buffered stdout, which
    // would lose the report this exists to produce.
    exitCode = selfTest() ? 0 : 1;
    return;
  }

  if (!File('PLAN.md').existsSync() || !Directory('packages').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exitCode = 2;
    return;
  }

  final dir = Directory(scannedDir);
  if (!dir.existsSync()) {
    stderr.writeln('determinism check failed:\n  - $scannedDir does not exist');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  var scanned = 0;
  for (final file
      in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    scanned++;
    violations.addAll(scanSource(relative(file.path), file.readAsStringSync()));
  }

  // A scan that finds no files reports "clean", which is the failure mode this
  // check is supposed to be immune to: if the engine moves, this says so
  // instead of passing forever.
  if (scanned == 0) {
    stderr.writeln(
      'determinism check failed:\n'
      '  - no Dart files under $scannedDir — has the engine moved?',
    );
    exitCode = 1;
    return;
  }

  if (violations.isEmpty) {
    print('determinism check: $scanned files clean');
    return;
  }

  stderr.writeln('\ndeterminism check failed:');
  for (final violation in violations) {
    stderr.writeln('  - $violation');
  }
  stderr.writeln(
    '\nSee PLAN-phase-2.md §1. Identical input must produce identical output '
    'forever, because saves store puzzle IDs rather than grids. If a hit is '
    'genuinely deterministic, mark the line `// $optOut` with a comment saying '
    'why — do not widen the rule.',
  );
  exitCode = 1;
}

/// Every determinism violation in [source], reported against [where].
///
/// Comments are stripped first, so the reasoning about a banned construct can
/// be written next to the code that avoids it.
List<String> scanSource(String where, String source) {
  final violations = <String>[];
  final raw = source.split('\n');
  final code = stripComments(source).split('\n');

  for (var i = 0; i < code.length; i++) {
    if (isOptedOut(raw, i)) continue;
    final line = code[i];
    final at = '$where:${i + 1}';

    for (final import in importUris(line)) {
      final banned = bannedImports.firstWhere(
        (b) => import == b || import.startsWith('$b/'),
        orElse: () => '',
      );
      if (banned.isNotEmpty) {
        violations.add(
          '$at imports $import — its Random gives no cross-version guarantee',
        );
      }
    }

    for (final (name, pattern, reason) in bannedApiPatterns) {
      if (pattern.hasMatch(line)) {
        violations.add('$at uses $name — $reason');
      }
    }

    for (final match in orderDependentAccess.allMatches(line)) {
      // `Difficulty.values` is declaration-ordered and so deterministic. A type
      // name is the only receiver that can be told apart textually, and the
      // convention that separates it — types capitalised, variables not — is
      // enforced by the analyzer's own lints, so this is not the guess it
      // looks like.
      final receiver = match.group(1);
      if (receiver != null && receiver.startsWith(typeReceiver)) continue;
      violations.add(
        '$at iterates .${match.group(2)} — its order is not guaranteed',
      );
    }
  }

  return violations;
}

/// Whether line [index] of [lines] carries the opt-out marker, on itself or in
/// a comment on the line directly above it.
bool isOptedOut(List<String> lines, int index) {
  if (lines[index].contains(optOut)) return true;
  if (index == 0) return false;
  final above = lines[index - 1].trim();
  return above.startsWith('//') && above.contains(optOut);
}

/// Checks the scanner against the cases that decide whether it works, run by
/// CI and `tool/verify.sh` before the check itself.
///
/// Every banned construct appears here twice: once where it must be reported,
/// and once in a shape that must not be — a mention in a comment, a type's
/// `values`, a `DateTime.utc`. A guard that fires on documentation gets
/// ignored, and an ignored guard is the same as no guard.
bool selfTest() {
  final failures = <String>[];
  var cases = 0;

  void expect(String label, String source, {required int hits}) {
    cases++;
    final found = scanSource('fixture.dart', source);
    if (found.length != hits) {
      failures.add(
        '$label: expected $hits violation(s), got ${found.length}'
        '${found.isEmpty ? '' : '\n    ${found.join('\n    ')}'}',
      );
    }
  }

  expect('random import', "import 'dart:math';", hits: 1);
  expect('aliased random import', "import 'dart:math' as math;", hits: 1);
  expect('library import', "import 'dart:math/foo.dart';", hits: 1);
  expect('random import in a comment', "// import 'dart:math';", hits: 0);
  expect('allowed import', "import 'dart:typed_data';", hits: 0);

  expect('clock read', 'final t = DateTime.now();', hits: 1);
  expect('spaced clock read', 'final t = DateTime . now();', hits: 1);
  expect('timestamp', 'final t = DateTime.timestamp();', hits: 1);
  expect('clock read in a doc comment', '/// Never DateTime.now().', hits: 0);
  expect('fixed date', 'final t = DateTime.utc(2026, 1, 1);', hits: 0);

  expect('stopwatch', 'final sw = Stopwatch()..start();', hits: 1);
  expect('stopwatch in a comment', '// A Stopwatch would vary.', hits: 0);
  expect('a name containing it', 'final stopwatchLike = 1;', hits: 0);

  expect('map keys', 'for (final k in counts.keys) print(k);', hits: 1);
  expect('map values', 'final first = counts.values.first;', hits: 1);
  expect('map entries', 'for (final e in counts.entries) print(e);', hits: 1);
  expect('a private map', 'for (final k in _counts.keys) print(k);', hits: 1);
  expect(
    'a returned map',
    'for (final k in unitsOf(i).keys) print(k);',
    hits: 1,
  );
  expect('enum values', 'final d = Difficulty.values[tier - 1];', hits: 0);

  expect(
    'the opt-out on the line',
    'final k = order.keys; // $optOut deliberate\n',
    hits: 0,
  );
  expect(
    'the opt-out on the line above',
    '// $optOut — the map is a LinkedHashMap built in index order\n'
        'final k = order.keys;',
    hits: 0,
  );
  expect(
    'the opt-out two lines above',
    '// $optOut\n\nfinal k = order.keys;',
    hits: 1,
  );
  expect(
    'the opt-out does not cover the rest of the file',
    'final a = order.keys; // $optOut\nfinal b = order.values;',
    hits: 1,
  );

  expect(
    'several constructs in one file',
    "import 'dart:math';\n"
        'final t = DateTime.now();\n'
        'final sw = Stopwatch();\n'
        'for (final k in m.keys) print(k);',
    hits: 4,
  );

  // The stripper keeps line numbers, so a violation after a multi-line comment
  // is reported where it is rather than where the comment started.
  final located = scanSource(
    'fixture.dart',
    '/* a\n   multi-line\n   comment */\nfinal t = DateTime.now();',
  );
  cases++;
  if (located.length != 1 || !located.single.startsWith('fixture.dart:4 ')) {
    failures.add('line numbers survive a block comment: got $located');
  }

  if (failures.isEmpty) {
    print('determinism check self-test: $cases cases clean');
    return true;
  }
  stderr.writeln('determinism check self-test failed:');
  for (final failure in failures) {
    stderr.writeln('  - $failure');
  }
  return false;
}
