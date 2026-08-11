// Enforces the project's hard constraints in the build rather than by
// convention (PLAN.md §2): no network, no ads, no tracking, and a puzzle engine
// that stays pure Dart.
//
// Run from the repository root:
//
//   dart tool/check_offline.dart
//
// Exits 0 when clean, 1 with a report of every violation otherwise. The
// dependency-graph checks need `pub get` to have run; pass --skip-deps to check
// sources only.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Packages that must not appear in what ships: anything that talks to a
/// network. Matched on package name, so `http_parser` and `http_multi_server`
/// (both offline) do not trip it.
const Set<String> networkPackages = {
  'chopper',
  'dio',
  'graphql',
  'graphql_flutter',
  'grpc',
  'http',
  'socket_io_client',
  'sync_http',
  'web_socket',
  'web_socket_channel',
};

/// Packages that must not appear anywhere at all — not in the app, not in test
/// tooling. Ads and telemetry are the whole point of the project's promise.
const Set<String> forbiddenPackages = {
  'amplitude_flutter',
  'appsflyer_sdk',
  'applovin_max',
  'datadog_flutter_plugin',
  'facebook_app_events',
  'firebase_analytics',
  'firebase_core',
  'firebase_crashlytics',
  'firebase_messaging',
  'google_mobile_ads',
  'in_app_purchase',
  'mixpanel_flutter',
  'onesignal_flutter',
  'posthog_flutter',
  'segment_analytics',
  'sentry',
  'sentry_flutter',
  'unity_ads_plugin',
};

/// Package name prefixes with the same effect, so a new member of a family is
/// caught without editing this file.
const List<String> forbiddenPackagePrefixes = [
  'admob',
  'firebase_',
  'google_ads',
  'sentry_',
];

/// Fetches fonts over the network at runtime, which the no-network rule rules
/// out. Font files belong in `app/assets/fonts/`.
const Set<String> bundleInsteadPackages = {'google_fonts'};

/// Networking APIs. Reaching for one of these in application code is the thing
/// the constraint forbids; the grep is what makes it fail loudly.
const List<String> bannedApis = [
  'HttpClient',
  'HttpRequest',
  'HttpServer',
  'RawDatagramSocket',
  'RawSecureSocket',
  'RawSocket',
  'RawSynchronousSocket',
  'SecureServerSocket',
  'SecureSocket',
  'ServerSocket',
  'Socket',
  'WebSocket',
];

/// SDK libraries that either provide networking or (for the engine) drag in a
/// platform the engine is not allowed to depend on.
const Set<String> bannedSdkImports = {
  'dart:html',
  'dart:js',
  'dart:js_interop',
  'dart:js_util',
};

/// `packages/puzzle_engine` is pure Dart on purpose: its tests must run without
/// Flutter bindings, a device, or a filesystem.
const Set<String> engineBannedImports = {
  'dart:io',
  'dart:isolate',
  'dart:ui',
  'package:flutter',
};

final List<String> _violations = [];
final List<String> _notes = [];

void main(List<String> args) {
  final skipDeps = args.contains('--skip-deps');
  final root = Directory.current;

  if (!File('${root.path}/PLAN.md').existsSync() ||
      !Directory('${root.path}/app').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exit(2);
  }

  checkDartSources();
  checkEnginePurity();
  checkPubspecs();
  checkAndroidManifest();
  checkAppleEntitlements();
  if (skipDeps) {
    _notes.add('Skipped the dependency-graph audit (--skip-deps).');
  } else {
    checkDependencyGraph();
  }

  for (final note in _notes) {
    print('note: $note');
  }

  if (_violations.isEmpty) {
    print('offline check: clean');
    return;
  }

  stderr.writeln('\noffline check failed:');
  for (final violation in _violations) {
    stderr.writeln('  - $violation');
  }
  stderr.writeln(
    '\nSee PLAN.md §2. If a hit is a false positive, narrow the pattern in '
    'tool/check_offline.dart rather than skipping the check.',
  );
  exit(1);
}

/// Scans shipped Dart source for networking APIs, network imports and URLs.
///
/// Comments are blanked out first, so a link in a doc comment is fine while
/// the same text in a string literal is not: a comment cannot open a socket,
/// and the alternative — flagging every documentation URL — trains people to
/// ignore the check.
void checkDartSources() {
  for (final file in dartFilesUnder(shippedSourceDirs())) {
    final code = stripComments(file.readAsStringSync());
    final lines = code.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final where = '${relative(file.path)}:${i + 1}';

      for (final api in bannedApis) {
        if (RegExp('\\b$api\\b').hasMatch(line)) {
          _violations.add('$where uses $api — the app has no networking');
        }
      }

      final url = RegExp(r'(?:https?|ftp|wss?)://').firstMatch(line);
      if (url != null) {
        _violations.add(
          '$where contains a ${url.group(0)} URL outside a comment',
        );
      }

      for (final import in importUris(line)) {
        if (bannedSdkImports.contains(import) ||
            bannedSdkImports.any((b) => import.startsWith('$b/'))) {
          _violations.add('$where imports $import');
        }
        final package = packageNameOf(import);
        if (package != null && networkPackages.contains(package)) {
          _violations.add('$where imports package:$package');
        }
      }
    }
  }
}

/// The engine stays pure Dart — no Flutter, no I/O, no isolates.
///
/// Generation runs in an isolate, but the app spawns it (`compute`); the engine
/// itself is a plain function so its tests need no bindings.
void checkEnginePurity() {
  final lib = Directory('packages/puzzle_engine/lib');
  if (!lib.existsSync()) return;

  for (final file in dartFilesUnder([lib])) {
    final code = stripComments(file.readAsStringSync());
    final lines = code.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final import in importUris(lines[i])) {
        final banned = engineBannedImports.firstWhere(
          (b) =>
              import == b ||
              import.startsWith('$b/') ||
              import.startsWith('$b:'),
          orElse: () => '',
        );
        if (banned.isNotEmpty) {
          _violations.add(
            '${relative(file.path)}:${i + 1} imports $import — '
            'puzzle_engine is pure Dart',
          );
        }
      }
    }
  }
}

/// Checks declared dependencies before the graph audit, so a bad entry is named
/// at its own file and line even when `pub get` has not run.
void checkPubspecs() {
  final pubspecs = [
    File('app/pubspec.yaml'),
    ...Directory('packages').listSync().whereType<Directory>().map(
      (d) => File('${d.path}/pubspec.yaml'),
    ),
  ].where((f) => f.existsSync());

  for (final pubspec in pubspecs) {
    final lines = pubspec.readAsLinesSync();
    var inDeps = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#')) continue;

      if (RegExp(r'^(dev_)?dependencies:').hasMatch(line)) {
        inDeps = true;
        continue;
      }
      if (RegExp(r'^\S').hasMatch(line)) {
        inDeps = false;
        continue;
      }
      if (!inDeps) continue;

      final entry = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
      if (entry == null) continue;
      final name = entry.group(1)!;
      final where = '${relative(pubspec.path)}:${i + 1}';

      if (isForbidden(name)) {
        _violations.add('$where depends on $name — no ads, no telemetry');
      } else if (networkPackages.contains(name)) {
        _violations.add('$where depends on $name — the app has no networking');
      } else if (bundleInsteadPackages.contains(name)) {
        _violations.add('$where depends on $name — bundle the font files');
      }
    }
  }
}

/// Walks the resolved graph, so a forbidden package is caught even when it
/// arrives transitively.
///
/// Two scopes: what ships (every runtime dependency) must also be free of
/// networking packages, while test-only tooling is allowed to contain an HTTP
/// client — `integration_test` pulls one in to talk to the driver — as long as
/// it is unreachable from the app's runtime dependencies.
void checkDependencyGraph() {
  for (final dir in ['app', 'packages/puzzle_engine']) {
    final graph = pubDeps(dir);
    if (graph == null) continue;

    final runtime = runtimeClosure(graph);
    for (final name in graph.keys) {
      final shipped = runtime.contains(name);
      if (isForbidden(name)) {
        _violations.add(
          '$dir dependency graph contains $name — no ads, no telemetry',
        );
      } else if (bundleInsteadPackages.contains(name)) {
        _violations.add('$dir dependency graph contains $name');
      } else if (networkPackages.contains(name)) {
        if (shipped) {
          _violations.add(
            '$dir ships $name, which is a network client '
            '(reached from a runtime dependency)',
          );
        } else {
          _notes.add('$dir: $name is present but test-only, so it never ships');
        }
      }
    }
  }
}

/// Android enforces the promise itself: without the permission the OS blocks
/// network access, and the store listing shows the app cannot reach the network
/// — better evidence for a parent than a sentence in the description.
void checkAndroidManifest() {
  final manifest = File('app/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    _violations.add('${relative(manifest.path)} is missing');
    return;
  }
  if (manifest.readAsStringSync().contains('android.permission.INTERNET')) {
    _violations.add(
      '${relative(manifest.path)} requests INTERNET — release builds must not',
    );
  }
  // The debug and profile manifests keep INTERNET on purpose: hot reload and
  // the VM service need it, and neither manifest is merged into a release APK.
}

/// The macOS sandbox and iOS builds get no network entitlement.
void checkAppleEntitlements() {
  final release = File('app/macos/Runner/Release.entitlements');
  if (!release.existsSync()) {
    _violations.add('${relative(release.path)} is missing');
    return;
  }
  final contents = release.readAsStringSync();
  for (final key in const [
    'com.apple.security.network.client',
    'com.apple.security.network.server',
  ]) {
    if (contents.contains(key)) {
      _violations.add('${relative(release.path)} grants $key');
    }
  }
}

// --- helpers ---------------------------------------------------------------

/// Directories whose contents end up in a shipped binary.
List<Directory> shippedSourceDirs() => [
  Directory('app/lib'),
  ...Directory(
    'packages',
  ).listSync().whereType<Directory>().map((d) => Directory('${d.path}/lib')),
].where((d) => d.existsSync()).toList();

Iterable<File> dartFilesUnder(List<Directory> dirs) => dirs
    .expand((d) => d.listSync(recursive: true))
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

bool isForbidden(String name) =>
    forbiddenPackages.contains(name) ||
    forbiddenPackagePrefixes.any(name.startsWith);

/// The URIs of any `import`, `export` or deferred directive on [line].
Iterable<String> importUris(String line) => RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
).allMatches(line).map((m) => m.group(1)!);

String? packageNameOf(String uri) => uri.startsWith('package:')
    ? uri.substring('package:'.length).split('/').first
    : null;

String relative(String path) {
  final prefix = '${Directory.current.path}/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

/// Replaces comments with spaces, keeping line count and column positions.
///
/// String literals are tracked so that a `//` inside one — as in a URL — is not
/// mistaken for the start of a comment, which would otherwise hide the very
/// thing being looked for.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  var blockDepth = 0;
  String? quote; // the delimiter of the string literal being scanned

  while (i < source.length) {
    final rest = source.length - i;
    final char = source[i];
    final next = rest > 1 ? source[i + 1] : '';

    if (blockDepth > 0) {
      if (char == '/' && next == '*') {
        blockDepth++;
        out.write('  ');
        i += 2;
        continue;
      }
      if (char == '*' && next == '/') {
        blockDepth--;
        out.write('  ');
        i += 2;
        continue;
      }
      out.write(char == '\n' ? '\n' : ' ');
      i++;
      continue;
    }

    if (quote != null) {
      if (char == r'\' && !quote.startsWith('r') && rest > 1) {
        out.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      final delimiter = quote.replaceFirst('r', '');
      if (source.startsWith(delimiter, i)) {
        out.write(delimiter);
        i += delimiter.length;
        quote = null;
        continue;
      }
      out.write(char);
      i++;
      continue;
    }

    if (char == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (char == '/' && next == '*') {
      blockDepth = 1;
      out.write('  ');
      i += 2;
      continue;
    }

    // A raw string's backslashes are literal, so the escape rule above must
    // know about the `r` prefix; carry it in the tracked delimiter.
    final raw = char == 'r' && (next == "'" || next == '"');
    final start = raw ? i + 1 : i;
    final quoteChar = source[start];
    if (quoteChar == "'" || quoteChar == '"') {
      final triple = quoteChar * 3;
      final delimiter = source.startsWith(triple, start) ? triple : quoteChar;
      quote = (raw ? 'r' : '') + delimiter;
      out.write(source.substring(i, start + delimiter.length));
      i = start + delimiter.length;
      continue;
    }

    out.write(char);
    i++;
  }

  return out.toString();
}

/// `pub deps --json` for [dir], as a package name to entry map.
Map<String, Map<String, Object?>>? pubDeps(String dir) {
  final flutterApp = File(
    '$dir/pubspec.yaml',
  ).readAsStringSync().contains('sdk: flutter');
  final executable = flutterApp ? 'flutter' : 'dart';
  final result = Process.runSync(
    executable,
    ['pub', 'deps', '--json'],
    workingDirectory: dir,
    runInShell: Platform.isWindows,
  );

  final stdoutText = result.stdout as String;
  final start = stdoutText.indexOf('{');
  if (result.exitCode != 0 || start < 0) {
    _violations.add(
      '$dir: could not read the dependency graph — run '
      '`$executable pub get` in $dir first '
      '(${(result.stderr as String).trim()})',
    );
    return null;
  }

  final json = jsonDecode(stdoutText.substring(start)) as Map<String, Object?>;
  final packages = (json['packages'] as List<Object?>)
      .cast<Map<String, Object?>>();
  return {for (final p in packages) p['name'] as String: p};
}

/// Package names reachable from the root's non-dev dependencies.
///
/// A dev dependency's own transitive packages are only reachable through it, so
/// skipping the dev entries at the root is enough to separate what ships from
/// what merely runs the tests.
Set<String> runtimeClosure(Map<String, Map<String, Object?>> graph) {
  final root = graph.values.firstWhere(
    (p) => p['kind'] == 'root',
    orElse: () => const {},
  );
  final queue = <String>[
    ...?(root['dependencies'] as List<Object?>?)?.cast<String>().where(
      (name) => graph[name]?['kind'] != 'dev',
    ),
  ];

  final seen = <String>{};
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (!seen.add(name)) continue;
    final deps = graph[name]?['dependencies'] as List<Object?>?;
    queue.addAll(deps?.cast<String>() ?? const []);
  }
  return seen;
}
