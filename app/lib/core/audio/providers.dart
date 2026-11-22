import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/providers.dart';
import 'app_audio.dart';

/// The audio player every screen reaches through.
///
/// Real by default; `test/app_harness.dart` overrides it with a [SilentAudio]
/// so a widget test needs no audio device, or with the `RecordingAudio` a test
/// asserting *what* would play passes as `pumpApp(audio:)`
/// (`test/core/audio/recording_audio.dart`).
///
/// [AppAudio.applySettings] is applied once from the current settings and
/// again on every change, so a mute takes effect immediately rather than
/// waiting for the next sound (`PLAN-phase-5.md` §4.2). Through
/// [followSettings] rather than `ref.listen`, which Riverpod 3 pauses here.
final Provider<AppAudio> appAudioProvider = Provider<AppAudio>((ref) {
  final audio = MinisoundAudio();
  followSettings(ref, audio.applySettings);
  ref.onDispose(audio.stopAll);
  return audio;
});
