// [ToolRow]'s own done criteria (`PLAN-phase-8.md` §6, PR 3): every control
// meets its tap-target floor, selection reads from a border's width rather
// than its colour, every control has a spoken label, a disabled undo says so
// to a screen reader as well as to the eye, and none of it overflows at 200%
// text scale in either orientation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/draw/model/palette.dart';
import 'package:zibo_games/features/draw/ui/tool_row.dart';

import '../../../core/ui/ui_harness.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    int sizeIndex = 0,
    int colorIndex = 0,
    bool isEraser = false,
    bool canUndo = false,
    bool canRedo = false,
    VoidCallback? onUndo,
    VoidCallback? onRedo,
    VoidCallback? onNewSheet,
    ValueChanged<int>? onSizeSelected,
    ValueChanged<int>? onColorSelected,
    VoidCallback? onEraserSelected,
    Axis axis = Axis.horizontal,
    double textScale = 1,
  }) => pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: ToolRow(
          sizeIndex: sizeIndex,
          colorIndex: colorIndex,
          isEraser: isEraser,
          onSizeSelected: onSizeSelected ?? (_) {},
          onColorSelected: onColorSelected ?? (_) {},
          onEraserSelected: onEraserSelected ?? () {},
          canUndo: canUndo,
          canRedo: canRedo,
          onUndo: onUndo ?? () {},
          onRedo: onRedo ?? () {},
          onNewSheet: onNewSheet ?? () {},
          axis: axis,
        ),
      ),
    ),
    theme: AppTheme.day(),
    textScale: textScale,
  );

  /// The outermost [Container] under [key] — the one whose fixed size is the
  /// control's tap target and whose border is the selection ring, as opposed
  /// to the smaller inner one that only some controls draw.
  Container outerContainer(WidgetTester tester, Key key) =>
      tester.widget<Container>(
        find
            .descendant(of: find.byKey(key), matching: find.byType(Container))
            .first,
      );

  double borderWidthOf(WidgetTester tester, Key key) {
    final decoration = outerContainer(tester, key).decoration! as BoxDecoration;
    return decoration.border!.top.width;
  }

  testWidgets('every control meets its tap-target floor', (tester) async {
    await pumpRow(tester);

    for (var i = 0; i < DrawPencils.widths.length; i++) {
      final size = tester.getSize(find.byKey(ToolRow.sizeKey(i)));
      expect(
        size.width,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: 'size $i',
      );
      expect(
        size.height,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: 'size $i',
      );
    }
    for (var i = 0; i < DrawPalette.colors.length; i++) {
      final size = tester.getSize(find.byKey(ToolRow.colorKey(i)));
      expect(
        size.width,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: 'color $i',
      );
      expect(
        size.height,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: 'color $i',
      );
    }
    expect(
      tester.getSize(find.byKey(ToolRow.eraserKey)).width,
      greaterThanOrEqualTo(AppTapTargets.min),
    );
    expect(
      tester.getSize(find.byKey(ToolRow.newSheetKey)).width,
      greaterThanOrEqualTo(AppTapTargets.min),
    );

    // Undo and redo get the higher, primary floor — tapped repeatedly and in
    // a hurry (`PLAN-phase-8.md` §1).
    expect(
      tester.getSize(find.byKey(ToolRow.undoKey)).width,
      greaterThanOrEqualTo(AppTapTargets.primary),
    );
    expect(
      tester.getSize(find.byKey(ToolRow.redoKey)).width,
      greaterThanOrEqualTo(AppTapTargets.primary),
    );
  });

  testWidgets(
    'a selected size dot carries a wider border than an unselected one',
    (tester) async {
      await pumpRow(tester, sizeIndex: 1);

      expect(borderWidthOf(tester, ToolRow.sizeKey(1)), AppBorders.selected);
      expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.hairline);
      expect(borderWidthOf(tester, ToolRow.sizeKey(2)), AppBorders.hairline);
    },
  );

  testWidgets(
    'a selected colour swatch carries a wider border than an unselected one',
    (tester) async {
      await pumpRow(tester, colorIndex: 3);

      expect(borderWidthOf(tester, ToolRow.colorKey(3)), AppBorders.selected);
      expect(borderWidthOf(tester, ToolRow.colorKey(0)), AppBorders.hairline);
    },
  );

  testWidgets('the eraser carries the same ring when active', (tester) async {
    await pumpRow(tester);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.hairline);

    await pumpRow(tester, isEraser: true);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.selected);
    // Nothing else reads as selected while the eraser is active, whatever
    // index it was left on.
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.colorKey(0)), AppBorders.hairline);
  });

  testWidgets('a size dot grows when selected, on top of the border', (
    tester,
  ) async {
    await pumpRow(tester);
    final unselected = tester.getSize(
      find
          .descendant(
            of: find.byKey(ToolRow.sizeKey(2)),
            matching: find.byType(Container),
          )
          .last,
    );

    await pumpRow(tester, sizeIndex: 2);
    final selected = tester.getSize(
      find
          .descendant(
            of: find.byKey(ToolRow.sizeKey(2)),
            matching: find.byType(Container),
          )
          .last,
    );

    expect(selected.width, greaterThan(unselected.width));
  });

  testWidgets('every pencil size and colour has a spoken name', (tester) async {
    await pumpRow(tester);

    for (var i = 0; i < DrawPencils.names.length; i++) {
      expect(
        tester.getSemantics(find.byKey(ToolRow.sizeKey(i))),
        isSemantics(label: DrawPencils.names[i], isButton: true),
      );
    }
    for (var i = 0; i < DrawPalette.names.length; i++) {
      expect(
        tester.getSemantics(find.byKey(ToolRow.colorKey(i))),
        isSemantics(label: DrawPalette.names[i], isButton: true),
      );
    }
    expect(
      tester.getSemantics(find.byKey(ToolRow.eraserKey)),
      isSemantics(label: 'Eraser', isButton: true),
    );
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.byTooltip('New sheet'), findsOneWidget);
  });

  testWidgets(
    'undo with nothing to undo reports disabled to the semantics tree, not only to the eye',
    (tester) async {
      await pumpRow(tester, canUndo: false);

      expect(
        tester.getSemantics(find.byKey(ToolRow.undoKey)),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );

      await pumpRow(tester, canUndo: true);

      expect(
        tester.getSemantics(find.byKey(ToolRow.undoKey)),
        isSemantics(hasEnabledState: true, isEnabled: true),
      );
    },
  );

  testWidgets(
    'tapping a size, a colour, the eraser and the action buttons calls back',
    (tester) async {
      int? tappedSize;
      int? tappedColor;
      var erased = false;
      var undone = false;
      var redone = false;
      var newSheet = false;

      await pumpRow(
        tester,
        canUndo: true,
        canRedo: true,
        onSizeSelected: (i) => tappedSize = i,
        onColorSelected: (i) => tappedColor = i,
        onEraserSelected: () => erased = true,
        onUndo: () => undone = true,
        onRedo: () => redone = true,
        onNewSheet: () => newSheet = true,
      );

      await tester.tap(find.byKey(ToolRow.sizeKey(2)));
      await tester.tap(find.byKey(ToolRow.colorKey(5)));
      await tester.tap(find.byKey(ToolRow.eraserKey));
      await tester.tap(find.byKey(ToolRow.undoKey));
      await tester.tap(find.byKey(ToolRow.redoKey));
      await tester.tap(find.byKey(ToolRow.newSheetKey));

      expect(tappedSize, 2);
      expect(tappedColor, 5);
      expect(erased, isTrue);
      expect(undone, isTrue);
      expect(redone, isTrue);
      expect(newSheet, isTrue);
    },
  );

  for (final orientation in {
    'portrait': const Size(360, 640),
    'landscape': const Size(640, 360),
  }.entries) {
    testWidgets(
      'lays out without overflow at 200% text scale, ${orientation.key}',
      (tester) async {
        tester.view.physicalSize = orientation.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpRow(tester, textScale: 2);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
