// Guards that every `Motif` has what it needs to be heard: its file, a
// declared asset directory, and a licence row.
//
// A missing asset or an undeclared directory fails silently at runtime:
// `MinisoundAudio` latches `_failed` on any load error and logs "silenced"
// once (`lib/core/audio/app_audio.dart`), after which the whole app is mute.
// No other test notices, since they all run over a recording fake. A missing
// licence row costs nothing at runtime; it is checked here because
// `LICENSE-ASSETS.md` asks for a row in the same commit as the file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';

void main() {
  final declared = _declaredAssets(File('pubspec.yaml').readAsLinesSync());
  final licences = File('assets/LICENSE-ASSETS.md').readAsStringSync();

  for (final motif in Motif.values) {
    group(motif.name, () {
      test('has a non-empty RIFF/WAVE file', () {
        final file = File('assets/audio/${motif.asset}');
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        final bytes = file.readAsBytesSync();
        expect(bytes, isNotEmpty, reason: '${file.path} is empty');
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      });

      test('has its directory declared in pubspec.yaml', () {
        final dir = motif.asset.substring(0, motif.asset.lastIndexOf('/') + 1);
        expect(
          declared,
          contains('assets/audio/$dir'),
          reason: 'assets/audio/$dir is not declared under flutter: assets:',
        );
      });

      test('has an inventory row in LICENSE-ASSETS.md', () {
        expect(
          licences,
          contains('`audio/${motif.asset}`'),
          reason: 'no LICENSE-ASSETS.md row for audio/${motif.asset}',
        );
      });
    });
  }

  test('no two motifs share an asset', () {
    final assets = Motif.values.map((m) => m.asset).toList();
    expect(assets.toSet().length, assets.length);
  });
}

/// The entries of the `assets:` list under `flutter:`, and nothing else: a
/// commented-out line or an `- assets/...` under another key is not a
/// declaration.
Set<String> _declaredAssets(List<String> pubspec) {
  final start = pubspec.indexWhere((line) => line == '  assets:');
  if (start == -1) throw StateError('pubspec.yaml has no flutter: assets:');
  final entries = <String>{};
  for (final line in pubspec.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final entry = RegExp(r'^    - (\S+)\s*$').firstMatch(line);
    if (entry == null) break;
    entries.add(entry.group(1)!);
  }
  return entries;
}
