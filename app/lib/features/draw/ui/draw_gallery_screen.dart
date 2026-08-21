// The screen `/draw` opens: every drawing this profile has made, newest
// first, with a way to start another (`PLAN-phase-8.md` §4.7, §6 PR 4).
//
// Loaded once into memory rather than watched through a provider — a
// directory listing is not something Riverpod invalidates on its own, so
// this screen reloads it by hand after anything that could have changed it:
// coming back from the sheet, and a delete.
//
// A thumbnail shows the whole picture, imported photo included: a drawing over
// a backdrop is mostly backdrop, so a strokes-only tile is a handful of marks
// floating on blank paper and a child cannot tell their drawings apart by
// looking at them. The photos are decoded here, at a fraction of their stored
// resolution ([_thumbnailBackdropScale]), rather than in the tiles.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../model/palette.dart';
import '../model/stroke.dart';
import 'draw_sheet_screen.dart';
import 'drawing_painter.dart';

/// The widest a gallery tile is allowed to get — narrow enough that a phone
/// shows two across and a tablet several, wide enough that a thumbnail still
/// reads as a picture rather than a swatch.
const double _tileMaxExtent = 176;

/// The fraction of its stored resolution a thumbnail's backdrop is decoded at.
///
/// A tile is at most [_tileMaxExtent] points wide, so on a 3x screen it has
/// about 530 physical pixels to show the sheet's full 1600 units in: a third
/// of a backdrop that fills the sheet is 533 pixels across, which is that
/// same tile to within a rounding error. Decoding the full photo instead
/// would cost 7.7 MB of RGBA for a 1600 x 1200 one, times however many of
/// them a profile's 64 MB of drawings holds (`PLAN-phase-8.md` §4.5).
const double _thumbnailBackdropScale = 1 / 3;

Color _colorOf(int colorIndex) => DrawPalette.colorAt(colorIndex);

double _widthOf(int sizeIndex) => DrawPencils.widthAt(sizeIndex);

/// Every drawing this profile has made, and the way to start another.
class DrawGalleryScreen extends ConsumerStatefulWidget {
  const DrawGalleryScreen({super.key});

  @override
  ConsumerState<DrawGalleryScreen> createState() => _DrawGalleryScreenState();
}

class _DrawGalleryScreenState extends ConsumerState<DrawGalleryScreen> {
  /// Null while the first listing is still being read.
  List<Drawing>? _drawings;

  /// The decoded backdrop of every listed drawing that has one, by drawing id.
  ///
  /// Owned here rather than decoded inside a tile: `GridView.builder` throws
  /// away a tile that scrolls out of view and builds it again on the way back,
  /// so a tile that owned its own decode would pay for another one every time
  /// a child scrolled the grid past it.
  final Map<String, SheetBackdrop> _backdrops = {};

  /// The profile [_backdrops] holds photos for. Drawing ids restart per
  /// profile (`"d1"`, `"d2"`, … — `drawing_repository.dart`), so a cache
  /// carried across a profile switch would hand one child's photo to another
  /// child's drawing that happens to share an id.
  String? _backdropProfileId;

  /// Bumped by every [_reload], so a decode still in flight from an earlier
  /// one is dropped rather than landing on the listing that replaced it — the
  /// same guard `draw_sheet_screen.dart` keeps over its own bake.
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    for (final backdrop in _backdrops.values) {
      backdrop.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    // Guards `ref` itself, not only the `setState` below: every caller past
    // `initState` reaches this after an `await` (a pushed sheet returning, a
    // delete's confirm dialog), and `ref` throws if the widget went away
    // during either.
    if (!mounted) return;
    final generation = ++_reloadGeneration;
    final repository = ref.read(drawingRepositoryProvider);
    final profileId = ref.read(activeProfileProvider).id;
    // Copied rather than sorted in place: an empty profile's `listDecodable`
    // returns a `const []` (`drawing_repository.dart`), which a direct `sort`
    // would throw against.
    final drawings = [...await repository.listDecodable(profileId)];
    // Newest first (`PLAN-phase-8.md` §4.7). A corrupted file is already
    // missing from this list — `listDecodable` skips what it cannot decode
    // rather than surfacing it (`drawing_repository.dart`) — so the rest of
    // the gallery shows with no error card for it.
    drawings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted || generation != _reloadGeneration) return;
    _pruneBackdrops(profileId, drawings);
    setState(() => _drawings = drawings);
    await _decodeBackdrops(drawings, generation);
  }

  /// Disposes the photos of drawings this listing no longer has — a delete, or
  /// a profile switch, which is every one of them at once.
  ///
  /// A photo still listed is kept rather than decoded again: a backdrop is
  /// locked once imported (`PLAN-phase-8.md` §4.6), so the bytes behind an id
  /// cannot change, and a second decode of the same picture would only cost a
  /// child the wait for it to reappear.
  void _pruneBackdrops(String profileId, List<Drawing> drawings) {
    final listed = profileId == _backdropProfileId
        ? {for (final drawing in drawings) drawing.id}
        : const <String>{};
    _backdropProfileId = profileId;
    _backdrops.removeWhere((id, backdrop) {
      if (listed.contains(id)) return false;
      backdrop.dispose();
      return true;
    });
  }

  /// Decodes the backdrop of every listed drawing that has one and is not
  /// cached already, in grid order — newest first, so the tiles a child is
  /// looking at fill in before the ones below the fold.
  ///
  /// One `setState` per photo rather than one at the end: every tile is
  /// already on screen with its strokes, and batching would make the first
  /// photo wait for the slowest decode.
  Future<void> _decodeBackdrops(List<Drawing> drawings, int generation) async {
    for (final drawing in drawings) {
      final bytes = drawing.backdrop;
      if (bytes == null || _backdrops.containsKey(drawing.id)) continue;

      final SheetBackdrop backdrop;
      try {
        backdrop = await decodeBackdrop(bytes, scale: _thumbnailBackdropScale);
      } on Exception {
        // A photo that will not decode leaves its tile showing the strokes
        // alone, for the reason `listDecodable` leaves a drawing it cannot
        // read out of the grid entirely (`drawing_repository.dart`): a child
        // never sees an internal error, and a thumbnail is self-explanatory
        // in a way an error card is not.
        continue;
      }
      if (!mounted || generation != _reloadGeneration) {
        backdrop.dispose();
        return;
      }
      setState(() => _backdrops[drawing.id] = backdrop);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawings = _drawings;

    return ScreenScaffold(
      title: 'Draw',
      child: drawings == null
          ? const SizedBox.expand()
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _tileMaxExtent,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                // The sheet's own 1600 x 1200 proportions (`stroke.dart`), so
                // a tile crops nothing off the picture it is a thumbnail of.
                childAspectRatio: sheetWidth / sheetHeight,
              ),
              itemCount: drawings.length + 1,
              itemBuilder: (context, index) => index == 0
                  ? _NewSheetTile(onTap: _openNew)
                  : _DrawingTile(
                      drawing: drawings[index - 1],
                      backdrop: _backdrops[drawings[index - 1].id],
                      onTap: () => _open(drawings[index - 1]),
                      onDelete: () => _delete(drawings[index - 1]),
                    ),
            ),
    );
  }

  Future<void> _openNew() => _pushSheet(const DrawSheetArgs());

  Future<void> _open(Drawing drawing) =>
      _pushSheet(DrawSheetArgs(drawingId: drawing.id));

  Future<void> _pushSheet(DrawSheetArgs args) async {
    await Navigator.of(context).pushNamed(AppRoutes.drawSheet, arguments: args);
    // The sheet autosaves on its own way out (`draw_sheet_screen.dart`'s
    // `DrawSheetRoute`), so by the time this returns whatever changed is
    // already on disk — this reload is what shows it here.
    await _reload();
  }

  Future<void> _delete(Drawing drawing) async {
    // Read before the confirm dialog's own `await`, not after: `ref` throws
    // once this widget is unmounted, and `_confirmDelete` is exactly the kind
    // of gap that could see it go.
    final repository = ref.read(drawingRepositoryProvider);
    final progress = ref.read(progressRepositoryProvider);

    if (!await _confirmDelete(context)) return;
    if (!mounted) return;

    final profileId = progress.activeProfile.id;
    await repository.delete(profileId, drawing.id);
    progress.recordDrawingDeleted(
      drawingId: drawing.id,
      totalBytes: repository.profileBytes(profileId),
    );
    await _reload();
  }
}

/// Asks once more before a picture is gone for good — the one destructive
/// action left in the draw feature (`PLAN-phase-8.md` §1), the same shape
/// `profile_screen.dart`'s own confirmation dialog is.
Future<bool> _confirmDelete(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this drawing?'),
      content: const Text('It will be gone for good.'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The first tile: always there, and always a valid thing to tap
/// (`tool_row.dart`'s own `onNewSheet` carries the same "never disabled"
/// note for the control inside the sheet).
class _NewSheetTile extends StatelessWidget {
  const _NewSheetTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'New sheet',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: AppIconSizes.large,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// One drawing: a thumbnail, tapped to reopen it and long-pressed to delete
/// it.
class _DrawingTile extends StatelessWidget {
  const _DrawingTile({
    required this.drawing,
    required this.backdrop,
    required this.onTap,
    required this.onDelete,
  });

  final Drawing drawing;

  /// [Drawing.backdrop] decoded, or null when this drawing has no photo or
  /// its photo has not been decoded yet — the tile paints the strokes either
  /// way, and the photo appears under them when it lands.
  final SheetBackdrop? backdrop;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Drawing, made ${_shortDate(drawing.createdAt)}',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          // Rendered straight from the strokes and the photo rather than a
          // cached `<id>.thumb.png` (`PLAN-phase-8.md` §4.5): a drawing has at
          // most a few hundred strokes, which `drawing_painter_test.dart`
          // already shows painting inside a frame budget, so caching would
          // trade a PNG encode and a second file on disk for a cost this
          // already pays. The photo is the one part that is not free to redraw
          // from its source, which is why the decode is cached in the screen's
          // own state instead. Worth revisiting once PR 7's device pass has a
          // gallery large enough to measure it against.
          child: CustomPaint(
            painter: DrawingPainter(
              baked: null,
              backdrop: backdrop,
              liveStrokes: drawing.strokes,
              current: null,
              paperColor: colors.surface,
              colorOf: _colorOf,
              widthOf: _widthOf,
            ),
          ),
        ),
      ),
    );
  }
}

/// `8/20/2026` — no [intl] dependency for one field nobody reads back
/// (`PLAN.md` §2 keeps the dependency count to the one phase 8 already
/// spends on `gal`).
String _shortDate(DateTime createdAt) {
  final local = createdAt.toLocal();
  return '${local.month}/${local.day}/${local.year}';
}
