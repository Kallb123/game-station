// The screen a Tracks puzzle is played on (`PLAN-phase-9-tracks.md` §4.12).
//
// The same job as `sudoku_play_screen.dart`, and the lifecycle machinery is
// deliberately the same: where the puzzle comes from, the clock, and the save.
// The board and toolbar take a session and draw it, so everything about a
// puzzle being *resumed* rather than started is decided here and nowhere else.
//
// **Solving is recorded when it happens, not when the animation ends.** The
// journey of §4.8 takes seconds; a force-quit during it must lose nothing, so
// `_finish` writes the result first and the timeline only decides when the card
// appears.

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/audio/motif.dart';
import '../../../core/audio/providers.dart';
import '../../../core/haptics.dart';
import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/storage/save_data.dart';
import '../../../core/ui/completion_card.dart';
import '../../../core/ui/confetti.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/puzzle_clock.dart';
import '../../../core/ui/safe_pop.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../data/tracks_puzzle_record.dart';
import '../model/tracks_session.dart';
import '../skins/journey.dart';
import '../skins/track_geometry.dart';
import '../skins/track_skin.dart';
import '../skins/track_skins.dart';
import 'tracks_board.dart';
import 'tracks_toolbar.dart';

/// What the Back button on the completion card says.
const String backToTracksLabel = 'Back to Tracks';

/// What `/tracks/play` is pushed with.
///
/// A typed object for the reason [SudokuPlayArgs] is: `arguments` is `Object?`,
/// and the route table checks the type rather than casting.
@immutable
class TracksPlayArgs {
  /// Play the puzzle [id] names.
  const TracksPlayArgs(this.id);

  /// Which puzzle to play. The board is a pure function of it.
  final TracksPuzzleId id;
}

/// One Tracks puzzle, played.
class TracksPlayScreen extends ConsumerStatefulWidget {
  /// The screen for the puzzle [args] names.
  const TracksPlayScreen({required this.args, super.key});

  /// Which puzzle this is.
  final TracksPlayArgs args;

  @override
  ConsumerState<TracksPlayScreen> createState() => _TracksPlayScreenState();
}

class _TracksPlayScreenState extends ConsumerState<TracksPlayScreen>
    with SingleTickerProviderStateMixin {
  /// Captured once rather than read at each use: [dispose] saves through it,
  /// and a `ref` is not something to reach for while the tree is coming down.
  late final ProgressRepository _repository;
  late final AppLifecycleListener _lifecycle;

  TracksSession? _session;

  /// Fires when the load has taken long enough to be worth admitting to.
  Timer? _spinnerDelay;
  Timer? _clock;

  /// The clock, separately from `session.elapsed`, so that a second passing
  /// rebuilds the characters that show it rather than the whole board.
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );

  /// Where the solve animation is. The board listens to it directly, so a
  /// frame of the journey repaints the board and nothing else.
  final ValueNotifier<JourneyFrame> _frame = ValueNotifier<JourneyFrame>(
    JourneyFrame.waiting,
  );

  /// Drives [_frame] while the traveller runs; null otherwise, and always null
  /// under `reduceMotion`, which is what "no animation frames scheduled" means.
  Ticker? _journey;

  /// The skin, kept until the theme or brightness changes: the painter compares
  /// skins by identity, so a fresh one per build would repaint every frame
  /// (`tracks_board_painter.dart`).
  TrackSkin? _skin;
  TracksTheme? _skinTheme;
  Brightness? _skinBrightness;

  bool _showSpinner = false;
  bool _failed = false;
  bool _resumed = true;

  /// Whether the puzzle has been finished and written down. It stops the board
  /// being saved again as a puzzle in progress after
  /// [ProgressRepository.recordTracksSolved] cleared that entry.
  bool _solved = false;

  /// Whether the journey is over and the card is up.
  bool _arrived = false;

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
    _journey?.dispose();
    _lifecycle.dispose();

    final session = _session;
    if (session != null) {
      // Nothing is written here, for the reasons `SudokuPlayScreen.dispose`
      // gives: the board was written as it was played and the clock by
      // [_onPopped]. A write still in the debounce window is started, because
      // a screen that has gone has no next move to coalesce it with.
      if (!_repository.isDisposed) unawaited(_repository.flush());
      session
        ..removeListener(_onSessionChanged)
        ..dispose();
    }
    _elapsed.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Writes where the clock stopped, as the screen is left. The write belongs
  /// to the pop rather than to [dispose] because Riverpod refuses a provider
  /// mutation during a build (`sudoku_play_screen.dart` has the long form).
  void _onPopped(bool didPop, Object? result) {
    if (!didPop) return;

    _stopClock();
    _save();
    unawaited(_repository.flush());
  }

  @override
  Widget build(BuildContext context) {
    // Not `ScreenScaffold`, for the reason the Sudoku screen gives: a heading
    // at display size comes off a square board's side as well as its bottom.
    return PopScope(
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
              'Tracks',
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // The clock runs whether or not it is shown: `bestTimeMs` and the card
        // are fed by it (`sudoku_play_screen.dart`).
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
      return _showSpinner
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Making a puzzle',
              ),
            )
          : const SizedBox.expand();
    }

    final board = _boardAndToolbar(session, _currentSkin(watch: true));
    if (!_arrived) return board;

    // The finished board stays under the card, and the barrier stops a tap
    // reaching it.
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
          backLabel: backToTracksLabel,
          onBack: () => popIfPossible(context),
        ),
      ],
    );
  }

  /// The skin for the profile's theme and the current brightness. [watch] is
  /// true from [build], which must rebuild when the theme changes, and false
  /// from [_finish], where a `watch` is not allowed.
  TrackSkin _currentSkin({required bool watch}) {
    final profile = watch
        ? ref.watch(activeProfileProvider)
        : ref.read(activeProfileProvider);
    final theme = profile.tracksTheme;
    final brightness = Theme.of(context).brightness;
    if (_skin == null || theme != _skinTheme || brightness != _skinBrightness) {
      _skin = trackSkinFor(theme, brightness);
      _skinTheme = theme;
      _skinBrightness = brightness;
    }
    return _skin!;
  }

  /// The board and the toolbar, arranged for the window's orientation, on the
  /// reasoning of `SudokuPlayScreen._boardAndKeypad`: portrait gives the board
  /// the height the toolbar leaves, landscape gives the toolbar its intrinsic
  /// width and the board the rest.
  Widget _boardAndToolbar(TracksSession session, TrackSkin skin) {
    if (!isLandscapeWindow(context)) {
      return Column(
        children: [
          Expanded(child: _board(session, skin)),
          const SizedBox(height: AppSpacing.md),
          TracksToolbar(session: session),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _board(session, skin)),
        const SizedBox(width: AppSpacing.lg),
        IntrinsicWidth(
          child: Center(
            child: SingleChildScrollView(
              child: TracksToolbar(session: session, axis: Axis.vertical),
            ),
          ),
        ),
      ],
    );
  }

  /// [TracksBoard], capped at [maxBoardSide] on an [AppFormFactor.expanded]
  /// window, for the reason `SudokuPlayScreen._grid` gives.
  Widget _board(TracksSession session, TrackSkin skin) {
    final board = TracksBoard(
      session: session,
      skin: skin,
      frame: _frame,
      // Not interactive from the moment of solving: a stroke on a solved board
      // could unsolve it.
      interactive: !_solved,
      onSkip: _journey == null ? null : _skipJourney,
    );
    if (AppFormFactor.of(context) != AppFormFactor.expanded) return board;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxBoardSide,
          maxHeight: maxBoardSide,
        ),
        child: board,
      ),
    );
  }

  /// The Puzzles role's tones, which the Puzzles card inherits from Sudoku's
  /// palette (`PLAN-phase-9-tracks.md` §4.14).
  List<Color> _confettiColors(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final role = AppTheme.roleScheme(
      AppPalette.of(brightness).sudoku,
      brightness,
    );

    return [role.primary, role.secondary, role.tertiary, role.primaryContainer];
  }

  /// The same size and difficulty, one index on, or null at the end of the
  /// endless list.
  TracksPuzzleId? _nextPuzzle(TracksPuzzleId id) =>
      id.index < TracksPuzzleId.maxPuzzleIndex
      ? TracksPuzzleId(id.spec, id.difficulty, id.index + 1)
      : null;

  void _playNext() {
    final next = _nextPuzzle(widget.args.id);
    if (next == null) return;

    // Replaced rather than pushed, so a run of puzzles is not a stack of
    // finished boards behind the back arrow.
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.tracksPlay,
      arguments: TracksPlayArgs(next),
    );
  }

  Future<void> _load() async {
    final id = widget.args.id;
    final TracksSession session;
    try {
      final record = await ref.read(tracksPuzzleSourceProvider).load(id);
      if (!mounted) return;
      final mistakeFeedback = _repository.activeProfile.mistakeFeedback;
      session =
          _restore(id, record, mistakeFeedback) ??
          TracksSession.start(
            id: id,
            clues: record.clues,
            solution: record.solution,
            mistakeFeedback: mistakeFeedback,
          );
    } on Object {
      // Every way this fails is the same thing to a child, and none of them is
      // a message (`AGENTS.md`).
      if (mounted) _fail();
      return;
    }

    // Every move is written as it is played; the repository debounces and drops
    // writes equal to the stored one, so a stroke's many notifications cost
    // nothing (`PLAN.md` §5.3).
    session.addListener(_onSessionChanged);

    _spinnerDelay?.cancel();
    setState(() {
      _session = session;
      _showSpinner = false;
      _elapsed.value = session.elapsed;
    });
    _startClock();

    // As Sudoku has it: only a hand-edited save can resume solved, and without
    // this a child would face a finished board with no card.
    if (session.isSolved) _finish(session);
  }

  TracksSession? _restore(
    TracksPuzzleId id,
    TracksPuzzleRecord record,
    MistakeFeedback mistakeFeedback,
  ) {
    final saved = _repository.activeProfile.tracks.inProgress[id.value];
    if (saved == null) return null;

    try {
      return TracksSession.resume(
        id: id,
        clues: record.clues,
        solution: record.solution,
        saved: saved,
        mistakeFeedback: mistakeFeedback,
      );
    } on FormatException {
      // Dropped and started fresh, not reported (`AGENTS.md`).
      _repository.clearTracksInProgress(id);
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

  /// Counts ticks rather than reading a clock, so a widget test can move it
  /// (`sudoku_play_screen.dart`).
  void _startClock() {
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
  void _onLifecycleChanged(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _startClock();
      return;
    }
    _stopClock();
    _save();
  }

  /// What every change to the board leads to: a sound, and it is written down —
  /// or, if it finished the puzzle, that is written down instead. The event is
  /// drained before the `isSolved` check so the slot never carries a stale
  /// [TracksEvent.solved] into a puzzle played on.
  void _onSessionChanged() {
    final session = _session;
    if (session == null || _solved) return;

    final event = session.takeEvent();
    if (session.isSolved) {
      _finish(session);
      return;
    }
    if (event != null) _play(event);
    _save();
  }

  /// Turns [event] into its sound and buzz (`PLAN-phase-9-tracks.md` §4.10).
  /// The motifs are Sudoku's: a connection is the same act as a digit.
  void _play(TracksEvent event) {
    final audio = ref.read(appAudioProvider);
    final haptics = ref.read(appHapticsProvider);
    switch (event) {
      case TracksEvent.laid:
        audio.play(Motif.sudokuPlace);
        haptics.tap();
      case TracksEvent.laidWrong:
        audio.play(Motif.sudokuWrong);
        haptics.mistake();
      case TracksEvent.refused:
        // A soft bump, never an error (§4.7): quieter and without a buzz.
        audio.play(Motif.sudokuWrong, gain: 0.5);
      case TracksEvent.lifted:
      case TracksEvent.restored:
        audio.play(Motif.sudokuErase);
      case TracksEvent.marked:
        audio.play(Motif.sudokuPlace, gain: 0.7);
        haptics.tap();
      case TracksEvent.hinted:
        audio.play(Motif.sudokuHint);
      case TracksEvent.solved:
        // Never reached: `_onSessionChanged` goes through `_finish` first.
        break;
    }
  }

  /// Stops the clock, records the result, and starts the timeline that ends in
  /// the card (`PLAN-phase-9-tracks.md` §4.8).
  void _finish(TracksSession session) {
    _solved = true;
    _stopClock();
    session.removeListener(_onSessionChanged);

    _repository.recordTracksSolved(
      session.id,
      SolvedPuzzle(
        timeMs: session.elapsed.inMilliseconds,
        hints: session.hints,
        mistakes: session.mistakes,
        clean: session.hints == 0 && session.mistakes == 0,
      ),
    );
    unawaited(_repository.flush());
    ref.read(appHapticsProvider).impact();

    final route = TrackGeometry.trace(session.clues, session.cells);
    if (MediaQuery.disableAnimationsOf(context) || route == null) {
      _arrive();
      return;
    }

    final skin = _currentSkin(watch: false);
    final total = journeyDuration(skin, route);
    _journey = createTicker((elapsed) {
      if (elapsed >= total) {
        _endJourney();
        return;
      }
      _frame.value = journeyFrameAt(skin, route, elapsed);
    })..start();
    // Rebuilt so the board is no longer interactive and a tap can skip.
    setState(() {});
  }

  void _skipJourney() => _endJourney();

  void _endJourney() {
    final journey = _journey;
    if (journey == null) return;
    _journey = null;
    journey.dispose();
    _arrive();
  }

  void _arrive() {
    _frame.value = JourneyFrame.arrived;
    // PR 9's per-theme arrival motif plays here, before the shared fanfare.
    //
    // Under the confetti and unaffected by `reduceMotion`: that setting is about
    // movement, not celebration (`PLAN.md` §3.7).
    ref.read(appAudioProvider).play(Motif.sudokuComplete);
    setState(() => _arrived = true);
  }

  void _save() {
    final session = _session;
    // A solved puzzle is stored as a `SolvedPuzzle` and nothing else.
    if (session == null || _solved) return;
    _repository.saveTracksInProgress(session.id, session.toSaved());
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
