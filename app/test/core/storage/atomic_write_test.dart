// [writeFileAtomically]'s own test, over a real temp directory. Both
// `FileSaveStore` and `DrawingRepository` exercise it indirectly through
// their own suites; this is the one place its own contract — write via a
// `.tmp` sibling, rename over the target, leave no `.tmp` behind on success —
// is checked directly.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/atomic_write.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('zibo_games_atomic');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('writes the target file with the given contents', () async {
    final target = File('${directory.path}/thing.json');

    await writeFileAtomically(target, '{"a":1}');

    expect(target.readAsStringSync(), '{"a":1}');
  });

  test('replaces an existing target', () async {
    final target = File('${directory.path}/thing.json')
      ..writeAsStringSync('old');

    await writeFileAtomically(target, 'new');

    expect(target.readAsStringSync(), 'new');
  });

  test('leaves no .tmp file behind once the write lands', () async {
    final target = File('${directory.path}/thing.json');

    await writeFileAtomically(target, 'x');

    expect(File('${target.path}.tmp').existsSync(), isFalse);
  });
}
