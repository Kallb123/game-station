// The sheet a drawing happens on: the canvas and the tool row together
// (`PLAN-phase-8.md` §6, PR 3). Which pencil size, which colour and whether
// the eraser is active live here rather than on [DrawingController] — they
// are what the *next* stroke will be, not part of the picture already drawn,
// the same split `SudokuSession.pencilMode` draws between a play mode and the
// board it acts on.
//
// Owns the one piece of state [DrawingPainter] cannot: the baked [ui.Image],
// accumulated across frames as [DrawingController] reports a bake
// (`PLAN-phase-8.md` §4.3). Everything else about the picture — undo, redo,
// the stroke list — lives in the controller, which this screen only listens
// to and samples a pointer stream into.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../model/drawing_controller.dart';
import '../model/palette.dart';
import '../model/stroke.dart';
import 'drawing_painter.dart';
import 'tool_row.dart';

/// How far, in sheet units, the finger must move past the last sampled point
/// before a new one is appended. A 60-unit-long stroke is then at most 30
/// points regardless of how slowly the finger moved (`PLAN-phase-8.md` §4.2).
const double drawSampleDistance = 2;

Color _colorOf(int colorIndex) => DrawPalette.colorAt(colorIndex);

double _widthOf(int sizeIndex) => DrawPencils.widthAt(sizeIndex);

/// One sheet, drawn on with a finger, with the tool row below it.
class DrawSheetScreen extends StatefulWidget {
  /// Draws on [controller], or a fresh one when none is given — a test's own
  /// controller today, or a drawing resumed from disk once PR 4 wires that
  /// up.
  const DrawSheetScreen({this.controller, super.key});

  /// The drawing this screen starts on. Owned by the caller when given: only
  /// a screen that created its own disposes it. Tapping **New sheet**
  /// (`tool_row.dart`) always switches to an internally-created controller
  /// from then on, because [DrawingController] has no way to clear a picture
  /// in place (`PLAN-phase-8.md` §2 — no destructive clear) — the given
  /// controller's own strokes are left exactly as they were, just no longer
  /// on screen.
  final DrawingController? controller;

  @override
  State<DrawSheetScreen> createState() => _DrawSheetScreenState();
}

class _DrawSheetScreenState extends State<DrawSheetScreen> {
  late DrawingController _controller;
  late bool _ownsController;

  int _sizeIndex = 0;
  int _colorIndex = 0;
  bool _isEraser = false;

  ui.Image? _baked;

  /// Strokes the controller has reported baked but that [_baked] does not
  /// contain yet — composited in, one at a time, by [_bakeChain]. Painted
  /// alongside `liveStrokes` (`build`) so the oldest live stroke does not
  /// flash out of the picture for the frame between the controller crossing
  /// the horizon and the composited image landing.
  final List<Stroke> _pendingBakes = [];

  /// Every [_applyBake] chains onto this, so a stroke reported baked while an
  /// earlier one is still compositing waits its turn rather than compositing
  /// onto a [_baked] that is about to be replaced — two strokes crossing the
  /// horizon close together would otherwise race, and the loser's stroke
  /// would be dropped from the picture for good rather than merely delayed.
  Future<void> _bakeChain = Future<void>.value();

  /// Bumped by [_startNewSheet]. A bake started before it runs still finishes
  /// its compositing — [_bakeChain] is not cancelled — but [_applyBake]
  /// checks this before applying the result, so a bake for a sheet a child
  /// has already left cannot land on the blank one that replaced it.
  int _sheetGeneration = 0;

  /// The one pointer this screen is tracking, or null when nothing is being
  /// drawn. A second pointer going down while this one is active is ignored
  /// rather than starting a second stroke — the controller resolves one
  /// stroke at a time, and this is the one place that decides which pointer
  /// gets it (`drawing_controller.dart`).
  int? _activePointer;

  /// The sheet-coordinate point [extendStroke] last accepted, against which
  /// [drawSampleDistance] is measured. Null whenever [_activePointer] is.
  Offset? _lastSampled;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DrawingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
    // A controller resumed with more than the undo horizon's worth of
    // strokes already has some baked (`DrawingController._initialBakedCount`)
    // — folded into the picture, but into no image yet, since nothing has
    // painted one. Composing them once here is what PR 4's resumed drawing
    // needs; a fresh controller has none, and this is a no-op. Nothing can
    // race it: it is the first thing this state does, before a frame has
    // been built for a pointer to reach.
    final alreadyBaked = _controller.bakedStrokes;
    if (alreadyBaked.isNotEmpty) {
      final generation = _sheetGeneration;
      unawaited(
        _composeImage(null, alreadyBaked).then((image) {
          if (!mounted || generation != _sheetGeneration) {
            image.dispose();
            return;
          }
          setState(() => _baked = image);
        }),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _baked?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paperColor = Theme.of(context).colorScheme.surface;

    return ScreenScaffold(
      title: 'Draw',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = _fitToSheet(constraints.biggest);

                return Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Listener(
                      onPointerDown: (event) => _onPointerDown(event, size),
                      onPointerMove: (event) => _onPointerMove(event, size),
                      onPointerUp: (event) => _endStroke(event.pointer),
                      onPointerCancel: (event) => _endStroke(event.pointer),
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => CustomPaint(
                            size: size,
                            painter: DrawingPainter(
                              baked: _baked,
                              liveStrokes: [
                                ..._pendingBakes,
                                ..._controller.liveStrokes,
                              ],
                              current: _controller.current,
                              paperColor: paperColor,
                              colorOf: _colorOf,
                              widthOf: _widthOf,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => ToolRow(
              sizeIndex: _sizeIndex,
              colorIndex: _colorIndex,
              isEraser: _isEraser,
              onSizeSelected: (index) => setState(() {
                _sizeIndex = index;
                _isEraser = false;
              }),
              onColorSelected: (index) => setState(() {
                _colorIndex = index;
                _isEraser = false;
              }),
              onEraserSelected: () => setState(() => _isEraser = true),
              canUndo: _controller.canUndo,
              canRedo: _controller.canRedo,
              onUndo: _controller.undo,
              onRedo: _controller.redo,
              onNewSheet: _startNewSheet,
            ),
          ),
        ],
      ),
    );
  }

  /// The largest `sheetWidth` x `sheetHeight`-proportioned box that fits
  /// [available] — a phone and a tablet then draw the same picture
  /// (`PLAN-phase-8.md` §1), the same rule `sudoku_grid_view.dart` fits a
  /// square board with, for a sheet that is not square.
  Size _fitToSheet(Size available) {
    var width = available.width;
    var height = width * sheetHeight / sheetWidth;
    if (height > available.height) {
      height = available.height;
      width = height * sheetWidth / sheetHeight;
    }
    return Size(width, height);
  }

  Offset _toSheetPoint(PointerEvent event, Size displaySize) {
    final dx = (event.localPosition.dx * sheetWidth / displaySize.width).clamp(
      0.0,
      sheetWidth,
    );
    final dy = (event.localPosition.dy * sheetHeight / displaySize.height)
        .clamp(0.0, sheetHeight);
    return Offset(dx, dy);
  }

  void _onPointerDown(PointerDownEvent event, Size displaySize) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    final point = _toSheetPoint(event, displaySize);
    _lastSampled = point;
    _controller.beginStroke(
      colorIndex: _isEraser ? Stroke.eraserColorIndex : _colorIndex,
      sizeIndex: _sizeIndex,
      point: point,
    );
  }

  void _onPointerMove(PointerMoveEvent event, Size displaySize) {
    if (event.pointer != _activePointer) return;
    final point = _toSheetPoint(event, displaySize);
    final last = _lastSampled;
    if (last != null && (point - last).distance <= drawSampleDistance) {
      return;
    }
    _lastSampled = point;
    _controller.extendStroke(point);
  }

  void _endStroke(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    _lastSampled = null;
    _controller.endStroke();
  }

  void _onControllerChanged() {
    final justBaked = _controller.takeBaked();
    if (justBaked == null) return;
    _pendingBakes.add(justBaked);
    final generation = _sheetGeneration;
    // Chained rather than started directly: `_baked` a moment from now is
    // whatever the last-scheduled bake leaves it as, not whatever it is the
    // instant this stroke was reported (`_bakeChain`'s own doc comment).
    _bakeChain = _bakeChain.then((_) => _applyBake(justBaked, generation));
  }

  /// Composites [stroke] onto the current [_baked] and replaces it with the
  /// result — the bake `PLAN-phase-8.md` §4.3 describes. Only ever reached
  /// through [_bakeChain], so `_baked` here is always what the previous bake
  /// left it as.
  ///
  /// [generation] is what [_sheetGeneration] was when this bake was
  /// scheduled. If [_startNewSheet] has run since, this bake's picture no
  /// longer exists — the composited image is dropped rather than applied to
  /// the blank sheet that replaced it.
  Future<void> _applyBake(Stroke stroke, int generation) async {
    final image = await _composeImage(_baked, [stroke]);
    _pendingBakes.removeWhere((pending) => identical(pending, stroke));

    if (!mounted || generation != _sheetGeneration) {
      image.dispose();
      return;
    }
    final old = _baked;
    setState(() => _baked = image);
    old?.dispose();
  }

  /// Draws [strokes] onto [onto] (or a blank sheet, when null) and returns
  /// the composited image. Pure: callers own applying the result to
  /// [_baked].
  Future<ui.Image> _composeImage(ui.Image? onto, List<Stroke> strokes) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (onto case final image?) drawBakedImage(canvas, image);
    for (final stroke in strokes) {
      paintStroke(canvas, stroke, colorOf: _colorOf, widthOf: _widthOf);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      sheetWidth.round(),
      sheetHeight.round(),
    );
    picture.dispose();
    return image;
  }

  /// Files the current drawing away and starts a blank one
  /// (`PLAN-phase-8.md` §1, §4.7 — the gallery filing itself is PR 4's; this
  /// screen alone has nowhere to file it to yet).
  ///
  /// Bumps [_sheetGeneration] before swapping the controller, so a bake still
  /// compositing for the sheet just left cannot land on the blank one that
  /// replaces it.
  void _startNewSheet() {
    final oldController = _controller;
    final oldOwned = _ownsController;
    oldController.removeListener(_onControllerChanged);

    setState(() {
      _sheetGeneration++;
      _pendingBakes.clear();
      _bakeChain = Future<void>.value();
      _baked?.dispose();
      _baked = null;
      _controller = DrawingController();
      _ownsController = true;
    });

    _controller.addListener(_onControllerChanged);
    if (oldOwned) oldController.dispose();
  }
}
