// The Tracks board as a widget: the painter, the gestures that drive the
// session, and the one semantics label (`PLAN-phase-9-tracks.md` §4.12).
//
// It draws and translates; it decides nothing. A stroke is the session's to
// walk, a tap's meaning is decided by what is under it, and whether the board
// may be touched at all is the screen's, passed in as [TracksBoard.interactive].

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../model/tracks_session.dart';
import '../skins/journey.dart';
import '../skins/track_skin.dart';
import 'tracks_board_painter.dart';

/// How many of [session]'s row and column clues are met, and how many there
/// are: the figure the board's semantics value reads out.
///
/// A clue is met when its line holds exactly the number it asks for. Kept apart
/// from the widget so a test can ask it without a screen.
({int met, int total}) cluesMet(TracksSession session) {
  final side = session.spec.side;
  var met = 0;
  for (var line = 0; line < side; line++) {
    if (session.placedInRow(line) == session.clues.rowCounts[line]) met++;
    if (session.placedInColumn(line) == session.clues.columnCounts[line]) met++;
  }
  return (met: met, total: side * 2);
}

/// [session] drawn with [skin] and played with a finger.
class TracksBoard extends StatefulWidget {
  /// A board over [session].
  ///
  /// While [interactive] is false the board ignores strokes and taps, and a tap
  /// calls [onSkip] when there is one: the solve animation's way of being cut
  /// short.
  const TracksBoard({
    required this.session,
    required this.skin,
    required this.frame,
    required this.interactive,
    this.onSkip,
    super.key,
  });

  /// The puzzle being played.
  final TracksSession session;

  /// How the board looks. Held by identity by the painter, so the screen must
  /// keep handing over the same one (`tracks_board_painter.dart`).
  final TrackSkin skin;

  /// Where the solve animation is; [JourneyFrame.waiting] until a board is
  /// solved.
  final ValueListenable<JourneyFrame> frame;

  /// Whether a finger changes the board.
  final bool interactive;

  /// Called by a tap while the board is not [interactive].
  final VoidCallback? onSkip;

  @override
  State<TracksBoard> createState() => _TracksBoardState();
}

class _TracksBoardState extends State<TracksBoard> {
  /// The last position sent to the session, so a drag that stays inside one
  /// square does not call it again.
  (int, int)? _last;

  /// Whether a stroke has begun. Separate from `session.isStroking` because a
  /// finger that goes down off the board has not begun one yet.
  bool _begun = false;

  TracksSession get _session => widget.session;

  void _onPanStart(DragStartDetails details, BoardLayout layout) {
    _begun = false;
    _last = null;
    if (!widget.interactive) return;
    _moveTo(layout.positionAt(details.localPosition));
  }

  void _onPanUpdate(DragUpdateDetails details, BoardLayout layout) {
    if (!widget.interactive) return;
    _moveTo(layout.positionAt(details.localPosition));
  }

  void _moveTo((int, int)? position) {
    // Solved is checked here as well as through [TracksBoard.interactive],
    // which only changes on the next build: several pointer moves can arrive
    // before it, and one that retraced out of the goal port would unsolve a
    // board the screen has already recorded as solved.
    if (_session.isSolved) return;
    if (position == null || position == _last) return;
    _last = position;
    if (!_begun) {
      // A finger that came down off the board starts where it first reaches it.
      _begun = true;
      _session.beginStroke(position.$1, position.$2);
      return;
    }
    _session.strokeTo(position.$1, position.$2);
  }

  /// Not gated on [TracksBoard.interactive]: a stroke that solved the board is
  /// still open when the finger lifts, and it must be closed.
  void _onPanEnd() {
    _begun = false;
    _last = null;
    if (_session.isStroking) _session.endStroke();
  }

  void _onTapUp(TapUpDetails details, BoardLayout layout) {
    if (!widget.interactive || _session.isSolved) {
      widget.onSkip?.call();
      return;
    }
    final position = layout.positionAt(details.localPosition);
    if (position == null) return;
    final (row, column) = position;
    final side = _session.spec.side;
    if (row < 0 || row >= side || column < 0 || column >= side) return;

    // No mode toggle: a tap on track lifts it and a tap on bare ground marks it
    // (§4.12).
    final cell = _session.spec.indexAt(row, column);
    if (_session.maskAt(cell) != 0) {
      _session.clearCell(cell);
    } else {
      _session.toggleMark(cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyLarge?.fontFamily;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = BoardLayout.fit(constraints.biggest, _session.spec.side);

        return ListenableBuilder(
          listenable: _session,
          builder: (context, child) {
            final clues = cluesMet(_session);

            return Semantics(
              label:
                  'Track from ${widget.skin.travellerLabel} to '
                  '${widget.skin.goalLabel}',
              value: _session.isSolved
                  ? 'finished'
                  : '${clues.met} of ${clues.total} clues met',
              child: child,
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // So the stroke begins where the finger went down rather than
            // where it had got to when the drag recogniser gave in, 18 px
            // later: on a 5x5 board that is most of a cell.
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (details) => _onPanStart(details, layout),
            onPanUpdate: (details) => _onPanUpdate(details, layout),
            onPanEnd: (_) => _onPanEnd(),
            onPanCancel: _onPanEnd,
            onTapUp: (details) => _onTapUp(details, layout),
            child: ValueListenableBuilder<JourneyFrame>(
              valueListenable: widget.frame,
              builder: (context, frame, _) => SizedBox.expand(
                child: CustomPaint(
                  painter: TracksBoardPainter(
                    session: _session,
                    skin: widget.skin,
                    frame: frame,
                    clueFontFamily: fontFamily,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
