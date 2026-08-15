// The screen a puzzle is played on.
//
// It owns the three things the board and the keypad deliberately do not: where
// the puzzle comes from, the clock, and the save. The widgets under it take a
// session and draw it, so everything about a puzzle being *resumed* rather than
// started is decided here and nowhere else (`PLAN-phase-3.md` §4.5).
//
// **The force-quit is the phase's done-criterion** (`PLAN.md` §7): a child who
// closes the tablet mid-puzzle gets the same board back. That is three
// mechanisms, not one — the session is written on every move, the clock is
// written whenever it stops, and `app.dart` flushes the debounce when the
// platform says the process may be killed.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/ui/tokens.dart';
import '../data/providers.dart';
import '../data/puzzle_record.dart';
import '../model/sudoku_session.dart';
import 'sudoku_grid_view.dart';
import 'sudoku_keypad.dart';

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

/// What `/sudoku/play` is pushed with.
///
/// A typed object rather than a bare [PuzzleId] so that the route's arguments
/// have a name a `switch` can check for: `arguments` is `Object?`, and the
/// screen would otherwise cast whatever it was handed.
@immutable
class SudokuPlayArgs {
  /// Play the puzzle [id] names.
  const SudokuPlayArgs(this.id);

  /// Which puzzle to play. The board is a pure function of it.
  final PuzzleId id;
}

/// One puzzle, played.
class SudokuPlayScreen extends ConsumerStatefulWidget {
  /// The screen for the puzzle [args] names.
  const SudokuPlayScreen({required this.args, super.key});

  /// Which puzzle this is.
  final SudokuPlayArgs args;

  @override
  ConsumerState<SudokuPlayScreen> createState() => _SudokuPlayScreenState();
}

class _SudokuPlayScreenState extends ConsumerState<SudokuPlayScreen> {
  /// Captured once rather than read at each use: [dispose] saves through it,
  /// and a `ref` is not something to reach for while the tree is coming down.
  late final ProgressRepository _repository;
  late final AppLifecycleListener _lifecycle;

  SudokuSession? _session;

  /// Fires when the load has taken long enough to be worth admitting to.
  Timer? _spinnerDelay;
  Timer? _clock;

  /// The clock, separately from `session.elapsed`, so that a second passing
  /// rebuilds the four characters that show it rather than the whole board.
  /// The session's own field is written from the same tick and does not notify
  /// (`sudoku_session.dart`).
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );

  bool _showSpinner = false;
  bool _failed = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(progressRepositoryProvider);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
    _spinnerDelay = Timer(
      puzzleSpinnerDelay,
      () => setState(() => _showSpinner = true),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _spinnerDelay?.cancel();
    _stopClock();
    _lifecycle.dispose();

    final session = _session;
    if (session != null) {
      // The board itself is not written here: it was written when the screen
      // was popped (see [build]), because a provider cannot be modified while
      // the tree is coming down — Riverpod asserts on it, and the assertion
      // would fire on the *Back* tap that ends every session.
      //
      // The flush is not a mutation and stays: it lands whatever the last move
      // left in the debounce window, for the ways off this screen that are not
      // a pop — a relaunch, or a route stack replaced under it. [flush] never
      // throws (`progress_repository.dart`), so there is nothing to await.
      unawaited(_repository.flush());
      session
        ..removeListener(_save)
        ..dispose();
    }
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Not [ScreenScaffold], which every other screen uses, and the exception is
    // measured rather than felt. Its heading is a screen's name at display
    // size, and this screen's content is a square board, so every dp the
    // heading takes comes off the board's side as well as its bottom. The same
    // board and keypad on a 360x640 phone, with a notch and a gesture bar:
    //
    //                 ScreenScaffold   this frame
    //   9x9 at 100%        166 dp        194 dp
    //   9x9 at 200%         14 dp        170 dp
    //
    // The frame is otherwise the same one: the same safe area, the same screen
    // padding, the same back control with the same tooltip
    // (`PLAN-phase-3.md` §4.5).
    return PopScope(
      // The way off this screen, and so the moment the clock is written. It is
      // here rather than in [dispose] because a pop runs between frames and an
      // unmount runs inside one, and only the first of those may touch a
      // provider. Every pop counts — the back control, the system gesture and
      // the desktop shortcut all arrive here.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _saveOnLeaving();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        // Hidden where there is nothing to pop, as `screen_scaffold.dart` has
        // it: a back arrow that does nothing is worse than no arrow.
        if (Navigator.of(context).canPop()) ...[
          IconButton(
            onPressed: Navigator.of(context).pop,
            icon: const Icon(Icons.arrow_back, size: AppIconSizes.large),
            tooltip: 'Back',
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Sudoku',
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Read from the settings rather than from a field, so turning the timer
        // on in another screen shows it here without restarting the puzzle. The
        // clock itself runs either way: `bestTimeMs` and the completion card
        // are fed by it, and a child who hid the timer has not asked to stop
        // being timed.
        if (ref.watch(settingsProvider).showTimer) _Clock(elapsed: _elapsed),
      ],
    );
  }

  Widget _body() {
    if (_failed) {
      return Center(
        child: Text(
          puzzleFailedMessage,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      );
    }

    final session = _session;
    if (session == null) {
      // Nothing at all until the delay is up: an empty screen for a tenth of a
      // second reads as a screen that has not drawn yet, which is what it is.
      return _showSpinner
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Making a puzzle',
              ),
            )
          : const SizedBox.expand();
    }

    return Column(
      children: [
        Expanded(child: SudokuGridView(session: session)),
        const SizedBox(height: AppSpacing.md),
        // The keypad takes the height it needs and the board takes the rest,
        // rather than the other way round: every button on it has a floor to
        // clear (`PLAN.md` §4.2) and the board has none, so the board is the
        // one that can give.
        SudokuKeypad(session: session),
      ],
    );
  }

  Future<void> _load() async {
    final id = widget.args.id;
    final SudokuSession session;
    try {
      final record = await ref.read(puzzleSourceProvider).load(id);
      if (!mounted) return;
      // Building the session is inside the same `try` as the load: it decodes
      // the record it was handed, so it is one more way the puzzle can fail to
      // arrive rather than a step that happens after it has.
      session =
          _restore(id, record) ?? SudokuSession.start(id: id, record: record);
    } on Object {
      // Every way this fails — an isolate that died, a record that will not
      // decode — is the same thing to a child, and it is not a message about
      // any of them (`AGENTS.md`).
      if (mounted) _fail();
      return;
    }

    // Every move: the board is written as it is played rather than when the
    // screen closes, because a force-quit does not close a screen. The
    // repository debounces the writes into one every 500 ms (`PLAN.md` §5.3),
    // and a tap that only moves the selection produces a `PuzzleInProgress`
    // equal to the stored one, which it drops without scheduling anything.
    session.addListener(_save);

    _spinnerDelay?.cancel();
    setState(() {
      _session = session;
      _showSpinner = false;
      _elapsed.value = session.elapsed;
    });
    _startClock();
  }

  /// The saved board for [id], or null when there is none — and when the one
  /// there is does not describe this puzzle.
  SudokuSession? _restore(PuzzleId id, PuzzleRecord record) {
    final saved = _repository.activeProfile.sudoku.inProgress[id.value];
    if (saved == null) return null;

    try {
      return SudokuSession.resume(id: id, record: record, saved: saved);
    } on FormatException {
      // A truncated or hand-edited entry. Dropping it and starting fresh is the
      // whole of the handling: the alternative is telling a six-year-old that
      // their save file is malformed.
      _repository.clearInProgress(id);
      return null;
    }
  }

  void _fail() {
    _spinnerDelay?.cancel();
    setState(() {
      _failed = true;
      _showSpinner = false;
    });
  }

  /// Counts ticks rather than reading a clock.
  ///
  /// `DateTime.now` cannot be moved forward by a widget test, so a clock read
  /// from it could only be tested by waiting; a periodic timer is advanced by
  /// `tester.pump`. It also stops of its own accord while the app is not
  /// running, which is the behaviour [_onLifecycleChanged] otherwise has to
  /// arrange. A tick that arrives late loses a few milliseconds against the
  /// wall clock, which is not a quantity a child's puzzle timer is measured in.
  void _startClock() {
    if (_clock != null || _session == null || !_resumed) return;
    _clock = Timer.periodic(clockTick, (_) => _tick());
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  void _tick() {
    final session = _session;
    if (session == null) return;
    session.elapsed += clockTick;
    _elapsed.value = session.elapsed;
  }

  /// Stops the clock while the app is away, and writes where it stopped.
  ///
  /// The write does not race `app.dart`'s flush, in either order: [flush] loops
  /// until nothing is pending, so a mutation made while its first write is in
  /// flight is picked up by the next pass rather than left in the debounce
  /// window (`progress_repository.dart`).
  void _onLifecycleChanged(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _startClock();
      return;
    }
    _stopClock();
    _save();
  }

  void _save() {
    final session = _session;
    if (session == null) return;
    _repository.saveInProgress(session.id, session.toSaved());
  }

  /// Writes where the clock stopped, on the way out.
  ///
  /// Leaving the screen stops the clock as surely as a pause does, and the
  /// seconds since the last move are only in memory until something writes
  /// them.
  void _saveOnLeaving() {
    // Stopped before the write rather than in `dispose`, which runs a route
    // transition later: a tick in between would move a clock nothing is going
    // to write again.
    _stopClock();
    _save();
    // Landed rather than left in the debounce window: the window exists to
    // coalesce the writes of a puzzle being played, and this one has no more
    // moves to coalesce with. [ProgressRepository.flush] never throws
    // (`progress_repository.dart`), so there is nothing here to await.
    unawaited(_repository.flush());
  }
}

/// Time on the clock, in the header.
class _Clock extends StatelessWidget {
  const _Clock({required this.elapsed});

  final ValueListenable<Duration> elapsed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: elapsed,
      builder: (context, value, _) {
        final clock = formatElapsed(value);

        return Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: Text(
            clock,
            style: Theme.of(context).textTheme.titleLarge,
            // `4:05` read aloud on its own is a fraction or a date. The
            // accessibility pass is phase 5 (`PLAN-phase-3.md` §2); this is the
            // label it should not have to invent.
            semanticsLabel: 'Time $clock',
          ),
        );
      },
    );
  }
}

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
