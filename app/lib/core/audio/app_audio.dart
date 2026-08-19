// The mute-aware wrapper over `package:minisound` (`PLAN-phase-5.md` §4.2).
//
// `MinisoundAudio` is the only thing in this file that touches the package,
// so the risk `PLAN-phase-5.md` §3.6 names — the one maintainer, the untested
// platforms — is a swap of this one file if it ever has to happen.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:minisound/player_flutter.dart';

import '../storage/save_data.dart';
import 'generation_tracker.dart';
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

  /// Loads every motif in [motifs] now rather than waiting for its first
  /// [play] or [startLoop] — called with a screen's own set when that screen
  /// opens, so the async decode a motif's first use would otherwise pay
  /// lands during the screen transition instead of audibly late on the play
  /// field the first time each of a game's several distinct sounds is
  /// heard. Takes the set explicitly rather than loading all of [Motif]:
  /// `InvadersScreen` has no use for the six Sudoku motifs, and decoding
  /// them anyway would compete with the nine that matter for exactly the
  /// time budget this method exists to protect. Safe to call more than
  /// once; an already-loaded motif is skipped.
  void preload(Iterable<Motif> motifs);

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

  /// One in-flight or resolved load per motif, keyed the same as [_loaded]
  /// but populated first: two requests for a motif neither has loaded yet —
  /// [preload] racing the child's first real tap, say — share this one
  /// future rather than each calling `_player.loadSoundAsset` on the same
  /// asset. Without it, whichever of the two resolved last would be the only
  /// entry [_loaded] ever saw, and [stopLoop] or [stopAll] would then be
  /// reaching for a `LoadedSound` that was never the one actually playing.
  final Map<Motif, Future<LoadedSound>> _pending = {};

  /// Set once, by whichever call to [_soundFor] gets there first; every
  /// other concurrent call awaits this same future rather than checking a
  /// flag and racing ahead — a flag would only record that starting had
  /// *begun*, not that `init`/`start` had *finished*, which is exactly the
  /// gap [preload]'s several near-simultaneous calls used to fall into
  /// (`_player.loadSoundAsset` invoked before `_player.start` had
  /// returned).
  Future<void>? _ready;

  /// One generation per motif, bumped by [stopLoop] and [stopAll]. [play]
  /// and [startLoop] each capture the current generation for their motif
  /// before awaiting anything, and check it again once the awaited decode
  /// resolves — before committing to actually playing. Without this, a
  /// sound still decoding (or even just resolved-but-not-yet-run, since even
  /// an already-loaded `Future` defers its callback to a microtask) when a
  /// stop ran would play anyway once that callback finally fires — silently
  /// undoing the stop, and for a loop specifically, with `InvadersSim.step`
  /// a no-op once the run is over, nothing left to stop it a second time.
  final GenerationTracker<Motif> _generation = GenerationTracker<Motif>();

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
    final generation = _generation.start(motif);
    unawaited(
      _soundFor(motif).then((sound) {
        // A `stopAll` — a pause, or the run ending — landed between this
        // call and its sound finishing loading; play nothing this late.
        if (!_generation.isCurrent(motif, generation)) return;
        sound
          ..volume = gain
          ..play();
      }, onError: _fail),
    );
  }

  @override
  void startLoop(Motif motif) {
    if (!_sound || _failed) return;
    final generation = _generation.start(motif);
    unawaited(
      _soundFor(motif).then((sound) {
        // A stop requested after this call but before the sound finished
        // loading (or just before this callback's own microtask ran) bumped
        // the generation; this loop is no longer wanted.
        if (!_generation.isCurrent(motif, generation)) return;
        sound
          ..isLooped = true
          ..loopDelay = Duration.zero
          ..play();
      }, onError: _fail),
    );
  }

  @override
  void stopLoop(Motif motif) {
    _generation.cancel(motif);
    _loaded[motif]?.stop();
  }

  @override
  void preload(Iterable<Motif> motifs) {
    if (_failed) return;
    // Not gated on `_sound`: a muted profile that turns sound back on
    // mid-run should not pay the decode cost right as the child re-enables
    // it, so this loads regardless of the current setting.
    for (final motif in motifs) {
      unawaited(_soundFor(motif).then((_) {}, onError: _fail));
    }
  }

  @override
  void stopAll() {
    _generation.cancelAll();
    for (final sound in _loaded.values) {
      sound.stop();
    }
  }

  /// The loaded sound for [motif], loading it — and starting the player, the
  /// first time anything is asked for — if it has not been already.
  ///
  /// Deliberately not `async`: `_pending[motif] ??= _load(motif)` has to
  /// assign synchronously, in the same breath as reading the map, so that a
  /// second call for the same not-yet-loaded motif — arriving perhaps a
  /// microtask later, from a real [play] while [preload] is still in flight
  /// for it — sees its entry already there instead of racing to create a
  /// second one (see [_pending]'s own doc).
  Future<LoadedSound> _soundFor(Motif motif) {
    final loaded = _loaded[motif];
    if (loaded != null) return Future.value(loaded);
    return _pending[motif] ??= _load(motif);
  }

  Future<LoadedSound> _load(Motif motif) async {
    // `??=` assigns synchronously too, before this `await` ever suspends, so
    // a second *different* motif loading concurrently (`preload`'s loop, or
    // two new motifs drained in one frame) awaits this same in-flight future
    // rather than starting the engine a second time.
    await (_ready ??= _start());
    final sound = await _player.loadSoundAsset('$_assetRoot${motif.asset}');
    _loaded[motif] = sound;
    return sound;
  }

  Future<void> _start() async {
    await _player.init(32);
    await _player.start();
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
  void preload(Iterable<Motif> motifs) {}

  @override
  void applySettings(AppSettings settings) {}
}
