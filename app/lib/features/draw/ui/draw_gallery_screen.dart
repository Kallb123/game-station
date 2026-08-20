// The screen `/draw` opens: every drawing this profile has made, newest
// first, with a way to start another (`PLAN-phase-8.md` §4.7, §6 PR 4).
//
// Loaded once into memory rather than watched through a provider — a
// directory listing is not something Riverpod invalidates on its own, so
// this screen reloads it by hand after anything that could have changed it:
// coming back from the sheet, and a delete.

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

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    // Guards `ref` itself, not only the `setState` below: every caller past
    // `initState` reaches this after an `await` (a pushed sheet returning, a
    // delete's confirm dialog), and `ref` throws if the widget went away
    // during either.
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() => _drawings = drawings);
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
    required this.onTap,
    required this.onDelete,
  });

  final Drawing drawing;
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
          // Rendered straight from the strokes rather than a cached
          // `<id>.thumb.png` (`PLAN-phase-8.md` §4.5): a drawing has at most
          // a few hundred of them, which `drawing_painter_test.dart` already
          // shows painting inside a frame budget, so caching would trade a
          // PNG encode and a second file on disk for a cost this already
          // pays. Worth revisiting once PR 7's device pass has a gallery
          // large enough to measure it against.
          child: CustomPaint(
            painter: DrawingPainter(
              baked: null,
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
