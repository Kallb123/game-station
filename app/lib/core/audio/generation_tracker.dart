/// Tells a deferred callback whether it has been superseded by a later
/// request for the same key, or cancelled outright, since it started.
///
/// `MinisoundAudio` (`app_audio.dart`) is the one caller: a `play` or
/// `startLoop` call cannot commit its sound to actually playing until an
/// async decode resolves, and by then a `stopLoop` or `stopAll` may already
/// have run. Extracted into its own file, and generic rather than keyed on
/// `Motif`, so this — the actual logic those two bugs were in — has a test
/// that runs with no plugin, no platform channel and no audio device, unlike
/// `MinisoundAudio` itself, which `PLAN-phase-5.md` §3.6 deliberately leaves
/// to a device pass instead of a unit test.
class GenerationTracker<K> {
  final Map<K, int> _generations = {};

  /// The current generation for [key], starting it at zero if this is the
  /// first request seen for it. Call this before awaiting anything, and pass
  /// the result to [isCurrent] once the awaited work resolves.
  int start(K key) => _generations[key] ??= 0;

  /// Bumps [key]'s generation, so any [start] result captured before this
  /// call now fails [isCurrent].
  void cancel(K key) => _generations[key] = (_generations[key] ?? 0) + 1;

  /// Bumps every key that has ever called [start]. A key that never has is
  /// left alone: nothing was ever issued for it to cancel.
  void cancelAll() {
    for (final key in _generations.keys) {
      _generations[key] = _generations[key]! + 1;
    }
  }

  /// Whether [generation] — a value [start] returned earlier for [key] — is
  /// still the current one, i.e. nothing has [cancel]led or [cancelAll]ed it
  /// since.
  bool isCurrent(K key, int generation) => _generations[key] == generation;
}
