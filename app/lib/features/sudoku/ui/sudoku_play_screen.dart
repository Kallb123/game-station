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
import '../../../core/storage/save_data.dart';
import '../../../core/ui/safe_pop.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../data/puzzle_record.dart';
import '../model/sudoku_session.dart';
import 'completion_card.dart';
import 'confetti.dart';
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

  /// Whether the puzzle has been finished and written down.
  ///
  /// It is what stops the board being saved again as a puzzle in progress:
  /// [ProgressRepository.recordSolved] clears that entry in the same mutation
  /// it stores the result (`PLAN-phase-3.md` §4.8), and the screen closing a
  /// moment later must not put it back.
  bool _solved = false;

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
      // Nothing is *written* here: the board was written as it was played, and
      // the seconds since the last move were written by [_onPopped] or by the
      // lifecycle listener before this screen got as far as being taken down.
      // A write still sitting in the debounce window is started, though —
      // starting one is not a mutation, and a screen that has gone has no next
      // move to coalesce it with. [flush] never throws, so there is nothing
      // here to await (`progress_repository.dart`).
      if (!_repository.isDisposed) unawaited(_repository.flush());
      session
        ..removeListener(_onSessionChanged)
        ..dispose();
    }
    _elapsed.dispose();
    super.dispose();
  }

  /// Writes where the clock stopped, as the screen is left.
  ///
  /// Leaving stops the clock as surely as a pause does, and the seconds since
  /// the last move are only in memory until something writes them. **The write
  /// belongs to the pop rather than to [dispose]**: a screen is disposed
  /// part-way through a build, and Riverpod refuses a provider mutation made
  /// during one — rightly, since two widgets in the same frame would otherwise
  /// read different states. A pop is a tap handler, which is exactly where a
  /// mutation is allowed. Popping mid-puzzle is a child tapping the back arrow,
  /// so this is not a corner.
  ///
  /// It covers every way off this screen that has anything to write: the app
  /// going to the background writes through [_onLifecycleChanged], and both
  /// ways on from the completion card leave a puzzle whose result is already
  /// stored (`PLAN-phase-3.md` §4.8).
  void _onPopped(bool didPop, Object? result) {
    if (!didPop) return;

    _stopClock();
    _save();
    // Landed rather than left in the debounce window: the window exists to
    // coalesce the writes of a puzzle being played, and this one has no more
    // moves to coalesce with. [flush] never throws
    // (`progress_repository.dart`), so there is nothing here to await.
    unawaited(_repository.flush());
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
      // The pop is where the last write is made — see [_onPopped]. Nothing is
      // blocked: a child leaving a puzzle is leaving it, and the board they
      // left is what comes back.
      onPopInvokedWithResult: _onPopped,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: AppSpacing.md),
                if (_session case final session?) ...[
                  _ProgressBar(session: session),
                  const SizedBox(height: AppSpacing.sm),
                ],
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
            onPressed: () => popIfPossible(context),
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

    final board = Column(
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
    if (!_solved) return board;

    // The finished board stays where it was, under the card
    // (`PLAN-phase-3.md` §4.6). The barrier is what stops a tap reaching the
    // keypad behind it: entering a digit over a solved grid would unsolve it,
    // and there is no way back from that to the card.
    return Stack(
      fit: StackFit.expand,
      children: [
        board,
        ModalBarrier(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
          dismissible: false,
        ),
        Confetti(colors: _confettiColors(context)),
        CompletionCard(
          time: formatElapsed(session.elapsed),
          hints: session.hints,
          mistakes: session.mistakes,
          clean: session.hints == 0 && session.mistakes == 0,
          onNext: _nextPuzzle(session.id) == null ? null : _playNext,
          onBack: () => popIfPossible(context),
        ),
      ],
    );
  }

  /// The paper the celebration is cut from: the Sudoku role's own tones, so it
  /// reads as part of this screen rather than as a second palette
  /// (`sudoku_grid_view.dart` derives the board's colours the same way).
  List<Color> _confettiColors(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final role = AppTheme.roleScheme(
      AppPalette.of(brightness).sudoku,
      brightness,
    );

    return [role.primary, role.secondary, role.tertiary, role.primaryContainer];
  }

  /// The same size and difficulty, one index on (`PLAN-phase-3.md` §4.6), or
  /// null at the end of the endless list.
  ///
  /// The list stops at `PuzzleId.maxPuzzleIndex`, which is a billion puzzles
  /// away and still worth a check rather than an assertion failure: this is the
  /// one place in the app that builds an id by arithmetic.
  PuzzleId? _nextPuzzle(PuzzleId id) => id.index < PuzzleId.maxPuzzleIndex
      ? PuzzleId(id.spec, id.difficulty, id.index + 1)
      : null;

  void _playNext() {
    final next = _nextPuzzle(widget.args.id);
    if (next == null) return;

    // Replaced rather than pushed: a child who plays six in a row would
    // otherwise stack six finished boards behind them, and the back arrow would
    // walk back through every one of them to reach the menu.
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.sudokuPlay,
      arguments: SudokuPlayArgs(next),
    );
  }

  Future<void> _load() async {
    final id = widget.args.id;
    final SudokuSession session;
    try {
      final record = await ref.read(puzzleSourceProvider).load(id);
      if (!mounted) return;
      // Read once, here: the profile's answer decides how the board draws a
      // wrong digit, and nothing reachable from this screen changes either the
      // answer or whose it is (`sudoku_session.dart`).
      final mistakeFeedback = _repository.activeProfile.mistakeFeedback;
      // Building the session is inside the same `try` as the load: it decodes
      // the record it was handed, so it is one more way the puzzle can fail to
      // arrive rather than a step that happens after it has.
      session =
          _restore(id, record, mistakeFeedback) ??
          SudokuSession.start(
            id: id,
            record: record,
            mistakeFeedback: mistakeFeedback,
          );
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
    session.addListener(_onSessionChanged);

    _spinnerDelay?.cancel();
    setState(() {
      _session = session;
      _showSpinner = false;
      _elapsed.value = session.elapsed;
    });
    _startClock();

    // A saved board that is already finished can only come from a file edited
    // by hand — `recordSolved` clears the in-progress entry as it stores the
    // result — but without this a child would be left looking at a full grid
    // with no card and nothing to tap (`AGENTS.md`).
    if (session.isSolved) _finish(session);
  }

  /// The saved board for [id], or null when there is none — and when the one
  /// there is does not describe this puzzle.
  SudokuSession? _restore(
    PuzzleId id,
    PuzzleRecord record,
    MistakeFeedback mistakeFeedback,
  ) {
    final saved = _repository.activeProfile.sudoku.inProgress[id.value];
    if (saved == null) return null;

    try {
      return SudokuSession.resume(
        id: id,
        record: record,
        saved: saved,
        mistakeFeedback: mistakeFeedback,
      );
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
    // A finished puzzle's time is what was written down, so nothing may start
    // it moving again — coming back to the app on a solved board is the path
    // that would.
    if (_clock != null || _session == null || !_resumed || _solved) return;
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

  /// What every change to the board leads to: it is written down, and if it
  /// finished the puzzle, that is written down instead.
  void _onSessionChanged() {
    final session = _session;
    if (session == null || _solved) return;

    if (session.isSolved) {
      _finish(session);
      return;
    }
    _save();
  }

  /// Stops the clock, records the result, and puts the card over the board.
  ///
  /// The listener goes first so that nothing the card does — a rebuild, a
  /// route change — can write the finished board back as a puzzle in progress.
  /// Removing it from inside a notification is safe: `ChangeNotifier` allows a
  /// listener to remove itself while it is being called.
  void _finish(SudokuSession session) {
    _solved = true;
    _stopClock();
    session.removeListener(_onSessionChanged);

    _repository.recordSolved(
      session.id,
      SolvedPuzzle(
        timeMs: session.elapsed.inMilliseconds,
        hints: session.hints,
        mistakes: session.mistakes,
        // The star: no hints and no mistakes, where a mistake counts even if it
        // was corrected (`PLAN.md` §3.7, `sudoku_session.dart`).
        clean: session.hints == 0 && session.mistakes == 0,
      ),
    );
    // Landed rather than left in the debounce window, for the same reason the
    // screen's own close flushes: a finished puzzle has no later move to
    // coalesce the write with.
    unawaited(_repository.flush());

    setState(() {});
  }

  void _save() {
    final session = _session;
    // A solved puzzle is stored as a `SolvedPuzzle` and nothing else: writing
    // it here as well would leave the save holding one puzzle that is both
    // finished and in progress, which is exactly what `recordSolved` goes out
    // of its way to prevent.
    if (session == null || _solved) return;
    _repository.saveInProgress(session.id, session.toSaved());
  }
}

/// How much of [session]'s board the child has filled in, across the top of
/// the screen.
///
/// A cell-style listener rather than an [AnimatedBuilder] on the whole
/// session (`sudoku_cell.dart`): most of what a session notifies about —
/// which cell is selected, a pencil mark toggled — leaves [SudokuSession.progress]
/// unchanged, and a bar that repainted on every one of those would be doing
/// work with nothing to show for it.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.session});

  final SudokuSession session;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  late double _progress = widget.session.progress;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(_ProgressBar old) {
    super.didUpdateWidget(old);
    if (old.session == widget.session) return;
    old.session.removeListener(_onSessionChanged);
    widget.session.addListener(_onSessionChanged);
    _progress = widget.session.progress;
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final next = widget.session.progress;
    if (next == _progress) return;
    setState(() => _progress = next);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final role = AppTheme.roleScheme(
      AppPalette.of(brightness).sudoku,
      brightness,
    );
    final percent = (_progress * 100).round();

    return Semantics(
      label: 'Progress',
      value: '$percent%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: LinearProgressIndicator(
          value: _progress,
          minHeight: AppSpacing.xs,
          backgroundColor: role.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(role.primary),
        ),
      ),
    );
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
