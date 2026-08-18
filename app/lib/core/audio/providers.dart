import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/providers.dart';
import 'app_audio.dart';

/// The audio player every screen reaches through.
///
/// Real by default; `test/app_harness.dart` overrides it with a [SilentAudio]
/// so a widget test needs no audio device, and a test asserting *what* would
/// play overrides it again with a `RecordingAudio`
/// (`test/core/audio/recording_audio.dart`).
///
/// [AppAudio.applySettings] is applied once from the current settings and
/// again on every change, so a mute takes effect immediately rather than
/// waiting for the next sound (`PLAN-phase-5.md` §4.2).
final Provider<AppAudio> appAudioProvider = Provider<AppAudio>((ref) {
  final audio = MinisoundAudio();
  audio.applySettings(ref.read(settingsProvider));
  ref.listen(settingsProvider, (_, settings) => audio.applySettings(settings));
  ref.onDispose(audio.stopAll);
  return audio;
});
