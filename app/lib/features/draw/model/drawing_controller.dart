// One drawing in progress: its strokes, its redo stack, and the horizon past
// which undo can no longer reach.
//
// A [ChangeNotifier], matching `SudokuSession` (`features/sudoku/model/`) —
// the same shape over the same base class, for the same reason: a model that
// already depends on the state library cannot be tested without it, and
// nothing here imports Flutter beyond `foundation.dart` and `dart:ui`'s
// [Offset], so its tests are plain `test()` calls with no `WidgetTester`
// (`PLAN-phase-8.md` §4.1).
//
// **The picture and the undo stack are the same list.** Unlike a Sudoku move,
// which is a delta a `SudokuMove` restores, a stroke is the picture itself —
// there is nothing to compute back to. Undo is `strokes.removeLast()`, redo
// is putting it back, and the horizon below is what stops a child undoing an
// entire afternoon by holding a button (`PLAN-phase-8.md` §4.3, §4.4).

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'stroke.dart';

/// How many of the most recent strokes stay undoable. Older strokes are
/// still part of the drawing — [DrawingController.strokes] never drops one —
/// but a paint layer bakes them into a cached image it does not re-walk every
/// frame, and undo stops reaching them (`PLAN-phase-8.md` §4.3).
const int drawUndoHorizon = 50;

class DrawingController extends ChangeNotifier {
  /// Resumes a drawing over [strokes], oldest first — what
  /// `drawing_codec.dart` decodes a saved [Drawing] into.
  ///
  /// Neither the undo horizon nor the redo stack is persisted
  /// (`PLAN-phase-8.md` §4.4): which strokes count as still "live" is
  /// recomputed from [strokes]'s length alone, the same answer every time a
  /// drawing is reopened rather than one that depends on when a previous
  /// session happened to bake.
  DrawingController({List<Stroke> strokes = const []})
    : _all = [...strokes],
      _bakedCount = _initialBakedCount(strokes.length);

  static int _initialBakedCount(int total) =>
      total > drawUndoHorizon ? total - drawUndoHorizon : 0;

  /// Every stroke ever drawn, oldest first — the picture, and what
  /// [drawing_codec.dart] persists in full.
  final List<Stroke> _all;

  /// How many of [_all], counting from index 0, are baked: still part of the
  /// picture, but no longer reachable by [undo].
  int _bakedCount;

  /// Undone strokes, most recently undone last. Never persisted.
  final List<Stroke> _redo = [];

  /// The stroke [beginStroke] opened and neither [endStroke] nor a fresh
  /// [beginStroke] has closed, or null when nothing is being drawn.
  _OpenStroke? _open;

  /// A stroke [endStroke] just baked, or null when the last mutation did not
  /// cross the horizon. Cleared by the read, so a bake is reported once —
  /// the same outbox shape as `SudokuSession.takeEvent`.
  Stroke? _justBaked;

  /// Every stroke of the picture, oldest first. Never a defensive copy at
  /// every call: callers must not mutate the result.
  List<Stroke> get strokes => List.unmodifiable(_all);

  /// The strokes still reachable by [undo] — at most [drawUndoHorizon] of
  /// them, newest last. What the painter (PR 2) walks as paths rather than
  /// reading from the baked image.
  List<Stroke> get liveStrokes => List.unmodifiable(_all.sublist(_bakedCount));

  /// The strokes already folded into the baked image, oldest first. What the
  /// painter (PR 2) renders once, on load, to build that image in the first
  /// place.
  List<Stroke> get bakedStrokes =>
      List.unmodifiable(_all.sublist(0, _bakedCount));

  /// The stroke under the finger right now, or null when nothing is being
  /// drawn. A snapshot: mutating [extendStroke] again does not change an
  /// already-returned value.
  Stroke? get current => _open?.toStroke();

  bool get canUndo => _all.length > _bakedCount;
  bool get canRedo => _redo.isNotEmpty;

  /// The stroke [endStroke] most recently baked, or null. Cleared by the
  /// read: a bake is reported exactly once (`PLAN-phase-8.md` §6, PR 1).
  Stroke? takeBaked() {
    final baked = _justBaked;
    _justBaked = null;
    return baked;
  }

  /// Starts a stroke at [point], in sheet coordinates. `colorIndex` is
  /// [Stroke.eraserColorIndex] for the eraser.
  ///
  /// Any stroke already open is discarded rather than finished — a second
  /// pointer going down mid-stroke is not something this controller resolves;
  /// the sheet (PR 2) starts a stroke on the one pointer it tracks.
  void beginStroke({
    required int colorIndex,
    required int sizeIndex,
    required Offset point,
  }) {
    _open = _OpenStroke(colorIndex: colorIndex, sizeIndex: sizeIndex)
      ..points.add(point);
    notifyListeners();
  }

  /// Adds [point] to the stroke [beginStroke] opened. Does nothing if none is
  /// open.
  ///
  /// Appends every point handed to it: the 2-sheet-unit sampling
  /// `PLAN-phase-8.md` §4.2 asks for is the sheet's job (PR 2), which knows
  /// the pointer stream this does not.
  void extendStroke(Offset point) {
    final open = _open;
    if (open == null) return;
    open.points.add(point);
    notifyListeners();
  }

  /// Closes the open stroke and adds it to the picture. Does nothing if none
  /// is open.
  ///
  /// Clears the redo stack — the standard rule, and the one a child's
  /// expectation matches: having drawn something new, "redo" has nothing to
  /// mean. Bakes the oldest live stroke when this push carries the live
  /// window past [drawUndoHorizon].
  void endStroke() {
    final open = _open;
    if (open == null) return;
    _open = null;
    _push(open.toStroke());
  }

  /// Adds [stroke] to the picture directly, as if drawn in one motion.
  ///
  /// For a caller that already has a complete [Stroke] — a test, or a future
  /// paste/replay feature — without going through [beginStroke]/
  /// [extendStroke]/[endStroke].
  void addStroke(Stroke stroke) => _push(stroke);

  /// Moves the last stroke to the redo stack. Does nothing past the horizon:
  /// [canUndo] is false once only baked strokes remain, and the button that
  /// asks for it stays visible but greyed (`PLAN-phase-8.md` §4.4).
  void undo() {
    if (!canUndo) return;
    _redo.add(_all.removeLast());
    notifyListeners();
  }

  /// Puts back what [undo] most recently took away. Does nothing if nothing
  /// was undone since the last new stroke.
  void redo() {
    if (_redo.isEmpty) return;
    _all.add(_redo.removeLast());
    notifyListeners();
  }

  void _push(Stroke stroke) {
    _redo.clear();
    _all.add(stroke);
    if (_all.length - _bakedCount > drawUndoHorizon) {
      _justBaked = _all[_bakedCount];
      _bakedCount++;
    }
    notifyListeners();
  }
}

/// The stroke [DrawingController.beginStroke] is still accumulating. A
/// mutable buffer kept apart from [Stroke], which is immutable and frozen the
/// moment [endStroke] closes it.
class _OpenStroke {
  _OpenStroke({required this.colorIndex, required this.sizeIndex});

  final int colorIndex;
  final int sizeIndex;
  final List<Offset> points = [];

  Stroke toStroke() => Stroke(
    colorIndex: colorIndex,
    sizeIndex: sizeIndex,
    points: List.unmodifiable(points),
  );
}
