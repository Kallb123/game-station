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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/storage/save_data.dart' show PadSide;
import '../../../core/ui/layout.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../data/drawing_repository.dart';
import '../data/providers.dart';
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
  /// controller, or a drawing resumed from disk (`DrawSheetRoute`, below).
  const DrawSheetScreen({
    this.controller,
    this.onControllerChanged,
    this.padSide = PadSide.right,
    super.key,
  });

  /// The drawing this screen starts on. Owned by the caller when given: only
  /// a screen that created its own disposes it. Tapping **New sheet**
  /// (`tool_row.dart`) always switches to an internally-created controller
  /// from then on, because [DrawingController] has no way to clear a picture
  /// in place (`PLAN-phase-8.md` §2 — no destructive clear) — the given
  /// controller's own strokes are left exactly as they were, just no longer
  /// on screen.
  final DrawingController? controller;

  /// Told which controller is active right now: once, synchronously, for
  /// whichever one this screen starts on, and again every time **New sheet**
  /// swaps in a fresh internal one.
  ///
  /// Optional, and unused by anything that only wants to draw — it exists so
  /// that [DrawSheetRoute] can keep autosaving the picture actually on
  /// screen without this screen having to know anything about a repository.
  /// A screen that reads it twice in a row without an intervening New sheet
  /// never happens: this screen only ever calls it once for a given
  /// controller instance.
  final ValueChanged<DrawingController>? onControllerChanged;

  /// Which side the tool row sits on in landscape — the same profile setting
  /// the arcade's on-screen pad reads, so a child does not set handedness
  /// twice (`PLAN-phase-8.md` §4.7). Unused in portrait, where the row is
  /// always the band below the sheet.
  final PadSide padSide;

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
    widget.onControllerChanged?.call(_controller);
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
    final landscape = isLandscapeWindow(context);

    return ScreenScaffold(
      title: 'Draw',
      child: landscape ? _landscapeLayout(context) : _portraitLayout(context),
    );
  }

  /// The band below the sheet, unchanged from before this screen knew about
  /// orientation.
  Widget _portraitLayout(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _canvas(context)),
      const SizedBox(height: AppSpacing.lg),
      _toolRow(Axis.horizontal),
    ],
  );

  /// A rail beside the sheet, on [DrawSheetScreen.padSide] — the same split
  /// `sudoku_play_screen.dart`'s `_boardAndKeypad` draws for its own keypad,
  /// and for the same reason: a control column with a floor on every button
  /// scrolls instead of being squeezed into a flex fraction that does not fit
  /// it (`PLAN-phase-8.md` §4.7).
  Widget _landscapeLayout(BuildContext context) {
    final rail = IntrinsicWidth(
      child: SingleChildScrollView(child: _toolRow(Axis.vertical)),
    );
    final canvas = Expanded(child: _canvas(context));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.padSide == PadSide.left
          ? [rail, const SizedBox(width: AppSpacing.lg), canvas]
          : [canvas, const SizedBox(width: AppSpacing.lg), rail],
    );
  }

  Widget _canvas(BuildContext context) {
    final paperColor = Theme.of(context).colorScheme.surface;

    return LayoutBuilder(
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
    );
  }

  Widget _toolRow(Axis axis) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => ToolRow(
      axis: axis,
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
  );

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
    widget.onControllerChanged?.call(_controller);
    if (oldOwned) oldController.dispose();
  }
}

/// How long after a stroke is committed before it is written to disk.
///
/// `PLAN.md` §5.3, in its own words: "a finished drawing stroke is the same
/// event, debounced the same way" a Sudoku move is.
const Duration drawAutosaveDebounce = Duration(milliseconds: 500);

/// What `/draw/sheet` is pushed with.
@immutable
class DrawSheetArgs {
  /// Resumes [drawingId], or opens a blank sheet when it is null.
  const DrawSheetArgs({this.drawingId});

  /// Which drawing to open, or null for a new one.
  final String? drawingId;
}

/// The route `/draw/sheet` opens: [DrawSheetScreen] plus everything about
/// *persisting* the picture it draws — loading `args.drawingId` from disk,
/// autosaving a finished stroke, and filing the sheet away when the app
/// leaves the foreground, the screen is popped, or **New sheet** is tapped
/// (`PLAN.md` §5.3, `PLAN-phase-8.md` §4.5, §4.7).
///
/// [DrawSheetScreen] itself knows nothing about a repository or a profile —
/// see its own doc comment — so all of that lives here, the same split
/// `sudoku_play_screen.dart` draws around `SudokuGridView`.
class DrawSheetRoute extends ConsumerStatefulWidget {
  const DrawSheetRoute({required this.args, super.key});

  /// Which drawing this route opens.
  final DrawSheetArgs args;

  @override
  ConsumerState<DrawSheetRoute> createState() => _DrawSheetRouteState();
}

class _DrawSheetRouteState extends ConsumerState<DrawSheetRoute> {
  /// Captured once, the same reasoning `sudoku_play_screen.dart` gives for
  /// its own: `dispose` saves through it, and a `ref` is not something to
  /// reach for while the tree is coming down.
  late final DrawingRepository _repository;
  late final ProgressRepository _progress;
  late final DateTime Function() _now;
  late final AppLifecycleListener _lifecycle;

  /// Null until [_load] resolves — a JSON file, not a generated puzzle, so
  /// there is nothing here worth a spinner for (`sudoku_play_screen.dart`'s
  /// own `puzzleSpinnerDelay`).
  DrawingController? _controller;

  /// The id [_controller]'s picture is currently saved under, or null before
  /// its first stroke has been written — see [ProgressRepository.nextDrawingId].
  String? _drawingId;
  DateTime? _createdAt;

  /// [DrawingController.strokes]'s length as of the last write this screen
  /// started. What [_onChanged] compares against to tell a committed stroke —
  /// [DrawingController.endStroke], [DrawingController.undo] or
  /// [DrawingController.redo] — from a point still moving under the finger,
  /// which the same notifier also fires for.
  int _savedStrokeCount = 0;
  bool _dirty = false;
  Timer? _saveTimer;

  /// Bumped by [_bind]. A write already in flight for a sheet **New sheet**
  /// has since left checks this before touching [_drawingId] and its
  /// neighbours, so that write cannot land on the bookkeeping for the sheet
  /// that replaced it (`_writeOnce`'s own note).
  int _generation = 0;

  /// **One write at a time, latest wins** — the same rule
  /// `progress_repository.dart` keeps for `save.json`, and for the same
  /// reason: two `writeFileAtomically` calls racing over the same drawing
  /// file is the one way that design still corrupts one.
  bool _writing = false;
  bool _writeAgain = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(drawingRepositoryProvider);
    _progress = ref.read(progressRepositoryProvider);
    _now = ref.read(nowProvider);
    _lifecycle = AppLifecycleListener(onPause: _flushNow, onDetach: _flushNow);
    unawaited(_load());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _lifecycle.dispose();
    _controller?.removeListener(_onChanged);
    // A write still in the debounce window is started rather than dropped —
    // the same reasoning `sudoku_play_screen.dart`'s own dispose gives: a
    // screen that has gone has no later stroke to coalesce it with.
    unawaited(_writeNow());
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.args.drawingId;
    final loaded = id == null
        ? null
        : await _repository.load(_progress.activeProfile.id, id);
    if (!mounted) return;

    final controller = DrawingController(strokes: loaded?.strokes ?? const []);
    setState(
      () => _bind(
        controller,
        drawingId: loaded != null ? id : null,
        createdAt: loaded?.createdAt,
      ),
    );
  }

  /// Called by [DrawSheetScreen] once for whichever controller this screen
  /// starts on — already bound by [_load], so a no-op here — and again every
  /// time **New sheet** swaps in a fresh one.
  void _onControllerSwapped(DrawingController controller) {
    if (identical(controller, _controller)) return;
    _flushNow(); // Files the sheet just left, if it holds anything to save.
    _bind(controller, drawingId: null);
  }

  void _bind(
    DrawingController controller, {
    required String? drawingId,
    DateTime? createdAt,
  }) {
    _controller?.removeListener(_onChanged);
    controller.addListener(_onChanged);
    _controller = controller;
    _drawingId = drawingId;
    _createdAt = createdAt;
    _savedStrokeCount = controller.strokes.length;
    _dirty = false;
    _generation++;
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.strokes.length == _savedStrokeCount) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(drawAutosaveDebounce, _flushNow);
  }

  void _flushNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_writeNow());
  }

  Future<void> _writeNow() async {
    if (_writing) {
      _writeAgain = true;
      return;
    }
    _writing = true;
    try {
      await _writeOnce();
    } finally {
      _writing = false;
      if (_writeAgain) {
        _writeAgain = false;
        await _writeNow();
      }
    }
  }

  /// Writes the picture currently bound, if it is dirty and holds at least
  /// one stroke — a sheet opened and left untouched should not burn an id or
  /// leave an empty file behind.
  Future<void> _writeOnce() async {
    final controller = _controller;
    if (controller == null || !_dirty) return;
    final strokes = controller.strokes;
    if (strokes.isEmpty) {
      _dirty = false;
      return;
    }

    final generation = _generation;
    final profileId = _progress.activeProfile.id;
    final isNew = _drawingId == null;
    final id = _drawingId ?? _progress.nextDrawingId();
    final createdAt = _createdAt ?? _now().toUtc();

    await _repository.save(
      profileId,
      Drawing(id: id, createdAt: createdAt, strokes: strokes),
    );
    final totalBytes = _repository.profileBytes(profileId);
    _progress.recordDrawingSaved(
      drawingId: id,
      isNew: isNew,
      totalBytes: totalBytes,
    );

    // New sheet swapped in a different picture while this write was in
    // flight — that picture's own [_bind] already set what this would
    // otherwise stomp back to the sheet that is no longer on screen.
    if (generation != _generation) return;
    _drawingId = id;
    _createdAt = createdAt;
    _savedStrokeCount = strokes.length;
    _dirty = false;
  }

  void _onPopped(bool didPop, Object? result) {
    if (didPop) _flushNow();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();

    return PopScope(
      onPopInvokedWithResult: _onPopped,
      child: DrawSheetScreen(
        controller: controller,
        onControllerChanged: _onControllerSwapped,
        padSide: _progress.activeProfile.padSide,
      ),
    );
  }
}
