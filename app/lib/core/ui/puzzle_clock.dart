// What both play screens share about loading and the clock: how long a load
// may take before the screen admits it, how the clock ticks and reads, and what
// a puzzle that will not load says (`PLAN-phase-3.md` §4.2,
// `PLAN-phase-9-tracks.md` §4.7).

/// How long a load may take before the screen admits it is loading
/// (`PLAN-phase-3.md` §4.2).
///
/// A 9x9 Easy is a millisecond and a cached puzzle is none (`PLAN.md` §3.5), so
/// a spinner drawn the moment a load starts would be a flash that reads as a
/// glitch. One constant with one test, rather than a `Future.delayed` at each
/// call site.
const Duration puzzleSpinnerDelay = Duration(milliseconds: 150);

/// How often the clock moves.
const Duration clockTick = Duration(seconds: 1);

/// What is shown while a puzzle that will not load is on screen.
///
/// One plain sentence, and the back arrow the screen already has: a child
/// cannot act on anything more specific, and an internal error is never put in
/// front of one (`AGENTS.md`). Public because the test names the same string.
const String puzzleFailedMessage = 'We could not start this puzzle.';

/// [elapsed] as `4:05`, or as `1:02:03` once a puzzle has run past an hour.
///
/// Minutes are not padded and hours are not shown until there are some: the
/// leading zeros of `00:04:05` are three characters a child has to read past to
/// find the number that is moving.
String formatElapsed(Duration elapsed) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % Duration.minutesPerHour;
  final seconds = elapsed.inSeconds % Duration.secondsPerMinute;

  return hours == 0
      ? '$minutes:${twoDigits(seconds)}'
      : '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
}
