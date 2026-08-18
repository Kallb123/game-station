// A fake for tests that assert *what* would have played, not just that
// nothing crashed. `SilentAudio` alone cannot answer that — it remembers
// nothing — so this wraps the same no-op behaviour with a log
// (`PLAN-phase-5.md` §4.2).

import 'package:zibo_games/core/audio/app_audio.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/storage/save_data.dart';

/// Records every [Motif] played or looped, in order, instead of making a
/// sound. `sound: false` in [applySettings] silences it exactly as the real
/// wrapper is silenced, so a test can assert an empty log rather than reading
/// the setting itself.
class RecordingAudio implements AppAudio {
  final List<Motif> played = [];
  final Set<Motif> looping = {};
  bool _sound = true;

  @override
  void play(Motif motif, {double gain = 1.0}) {
    if (!_sound) return;
    played.add(motif);
  }

  @override
  void startLoop(Motif motif) {
    if (!_sound) return;
    looping.add(motif);
  }

  @override
  void stopLoop(Motif motif) => looping.remove(motif);

  @override
  void stopAll() => looping.clear();

  @override
  void applySettings(AppSettings settings) => _sound = settings.sound;
}
