// The mute-aware wrapper over `package:minisound` (`PLAN-phase-5.md` §4.2).
//
// `MinisoundAudio` is the only thing in this file that touches the package,
// so the risk `PLAN-phase-5.md` §3.6 names — the one maintainer, the untested
// platforms — is a swap of this one file if it ever has to happen.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:minisound/player_flutter.dart';

import '../storage/save_data.dart';
import 'motif.dart';

/// Where every [Motif]'s asset lives, once `pubspec.yaml` has declared it.
const String _assetRoot = 'assets/audio/';

/// Plays the app's sounds, muted and silent exactly where
/// `PLAN-phase-5.md` §1 requires it: nothing plays with `settings.sound`
/// false, and a platform with no audio device gets silence rather than a
/// crash.
abstract interface class AppAudio {
  /// Plays [motif] once, at [gain] times its own level. Silent when the
  /// setting that gates it is off, when the engine failed to start, or on a
  /// platform with no audio device.
  void play(Motif motif, {double gain = 1.0});

  /// Starts [motif] looping until [stopLoop]. Only the UFO warble uses this
  /// (`PLAN-phase-5.md` §4.4).
  void startLoop(Motif motif);

  /// Stops [motif]'s loop, if it is running.
  void stopLoop(Motif motif);

  /// Stops everything now — the app going to the background, and a quit.
  void stopAll();

  /// The settings changed: a mute takes effect immediately, mid-puzzle.
  void applySettings(AppSettings settings);
}

/// The real implementation, over a single `Player`.
///
/// `init` and the first `loadSoundAsset` happen on the first [play] or
/// [startLoop] rather than in a constructor, so nothing on the launch path
/// waits for audio (`PLAN-phase-5.md` §1). Every call into the package is
/// wrapped: any throw latches [_failed] and is logged once through
/// [debugPrint], so a device with no audio backend — Linux with no ALSA, a
/// locked device — plays nothing instead of crashing. There is no retry: an
/// engine that failed once is not worth asking about on every placement.
class MinisoundAudio implements AppAudio {
  final Player _player = Player();
  final Map<Motif, LoadedSound> _loaded = {};
  bool _starting = false;
  bool _failed = false;
  bool _sound = true;

  @override
  void applySettings(AppSettings settings) {
    final wasOn = _sound;
    _sound = settings.sound;
    if (wasOn && !_sound) stopAll();
  }

  @override
  void play(Motif motif, {double gain = 1.0}) {
    if (!_sound || _failed) return;
    unawaited(
      _soundFor(motif).then((sound) {
        sound
          ..volume = gain
          ..play();
      }, onError: _fail),
    );
  }

  @override
  void startLoop(Motif motif) {
    if (!_sound || _failed) return;
    unawaited(
      _soundFor(motif).then((sound) {
        sound
          ..isLooped = true
          ..loopDelay = Duration.zero
          ..play();
      }, onError: _fail),
    );
  }

  @override
  void stopLoop(Motif motif) => _loaded[motif]?.stop();

  @override
  void stopAll() {
    for (final sound in _loaded.values) {
      sound.stop();
    }
  }

  /// The loaded sound for [motif], loading it — and starting the player, the
  /// first time anything is asked for — if it has not been already.
  Future<LoadedSound> _soundFor(Motif motif) async {
    final loaded = _loaded[motif];
    if (loaded != null) return loaded;

    if (!_starting) {
      _starting = true;
      await _player.init(32);
      await _player.start();
    }
    final sound = await _player.loadSoundAsset('$_assetRoot${motif.asset}');
    _loaded[motif] = sound;
    return sound;
  }

  void _fail(Object error) {
    _failed = true;
    debugPrint('AppAudio: silenced after $error');
  }
}

/// No-op. What every widget test gets by default (`test/app_harness.dart`),
/// so nothing needs an audio device to run.
class SilentAudio implements AppAudio {
  const SilentAudio();

  @override
  void play(Motif motif, {double gain = 1.0}) {}

  @override
  void startLoop(Motif motif) {}

  @override
  void stopLoop(Motif motif) {}

  @override
  void stopAll() {}

  @override
  void applySettings(AppSettings settings) {}
}
