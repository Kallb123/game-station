// Guards that every `Motif` has what it needs to be heard: its file, a
// declared asset directory, and a licence row.
//
// A missing asset or an undeclared directory fails silently at runtime:
// `MinisoundAudio` latches `_failed` on any load error and logs "silenced"
// once (`lib/core/audio/app_audio.dart`), after which the whole app is mute.
// No other test notices, since they all run over a recording fake. This is the
// one that does.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/motif.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final declared = {
    for (final line in pubspec)
      if (RegExp(r'^\s*-\s+assets/audio/').hasMatch(line))
        line.trim().substring(1).trim(),
  };
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
