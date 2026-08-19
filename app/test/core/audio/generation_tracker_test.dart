// The race `MinisoundAudio` (`app_audio.dart`) needs this for: a `play` or
// `startLoop` call cannot commit until an async decode resolves, and by then
// a stop may already have run. Tested here with no plugin, no platform
// channel and no audio device, unlike `MinisoundAudio` itself, which
// `PLAN-phase-5.md` §3.6 leaves to a device pass rather than a unit test.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/audio/generation_tracker.dart';

void main() {
  test('a generation never cancelled stays current', () {
    final tracker = GenerationTracker<String>();

    final generation = tracker.start('a');

    expect(tracker.isCurrent('a', generation), isTrue);
  });

  test('cancel makes a generation captured before it stale', () {
    final tracker = GenerationTracker<String>();
    final generation = tracker.start('a');

    tracker.cancel('a');

    expect(tracker.isCurrent('a', generation), isFalse);
  });

  test('a generation started after a cancel is current', () {
    final tracker = GenerationTracker<String>();
    tracker.cancel('a'); // cancelling before anything started is a no-op

    final generation = tracker.start('a');

    expect(tracker.isCurrent('a', generation), isTrue);
  });

  test('a second start after a cancel supersedes the first', () {
    final tracker = GenerationTracker<String>();
    final first = tracker.start('a');

    tracker.cancel('a');
    final second = tracker.start('a');

    expect(tracker.isCurrent('a', first), isFalse);
    expect(tracker.isCurrent('a', second), isTrue);
  });

  test('cancel only affects the key it names', () {
    final tracker = GenerationTracker<String>();
    final a = tracker.start('a');
    final b = tracker.start('b');

    tracker.cancel('a');

    expect(tracker.isCurrent('a', a), isFalse);
    expect(tracker.isCurrent('b', b), isTrue);
  });

  test('cancelAll cancels every key that has ever started', () {
    final tracker = GenerationTracker<String>();
    final a = tracker.start('a');
    final b = tracker.start('b');

    tracker.cancelAll();

    expect(tracker.isCurrent('a', a), isFalse);
    expect(tracker.isCurrent('b', b), isFalse);
  });

  test('cancelAll leaves a key that never started untouched', () {
    final tracker = GenerationTracker<String>();
    tracker.start('a');

    tracker.cancelAll();
    // Started for the first time only after the cancelAll — nothing was
    // issued for it before then to cancel, so this is a fresh, current
    // generation rather than one already stale.
    final b = tracker.start('b');

    expect(tracker.isCurrent('b', b), isTrue);
  });
}
