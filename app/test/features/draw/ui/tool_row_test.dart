// [ToolRow]'s own done criteria (`PLAN-phase-8.md` §6, PR 3): every control
// meets its tap-target floor, selection reads from a border's width rather
// than its colour, every control has a spoken label, a disabled undo says so
// to a screen reader as well as to the eye, and none of it overflows at 200%
// text scale in either orientation — with the colours behind one palette
// button that opens `palette_popup.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/draw/model/palette.dart';
import 'package:zibo_games/features/draw/ui/palette_popup.dart';
import 'package:zibo_games/features/draw/ui/tool_row.dart';

import '../../../core/ui/ui_harness.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    int sizeIndex = 0,
    int colorIndex = DrawPalette.defaultIndex,
    bool isEraser = false,
    bool isDropper = false,
    bool canUndo = false,
    bool canRedo = false,
    VoidCallback? onUndo,
    VoidCallback? onRedo,
    VoidCallback? onNewSheet,
    ValueChanged<int>? onSizeSelected,
    ValueChanged<int>? onColorSelected,
    VoidCallback? onEraserSelected,
    VoidCallback? onDropperSelected,
    ToolRowLayout layout = ToolRowLayout.band,
    double? width,
    double textScale = 1,
  }) => pumpApp(
    tester,
    Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ToolRow(
            sizeIndex: sizeIndex,
            colorIndex: colorIndex,
            isEraser: isEraser,
            isDropper: isDropper,
            onSizeSelected: onSizeSelected ?? (_) {},
            onColorSelected: onColorSelected ?? (_) {},
            onEraserSelected: onEraserSelected ?? () {},
            onDropperSelected: onDropperSelected ?? () {},
            canUndo: canUndo,
            canRedo: canRedo,
            onUndo: onUndo ?? () {},
            onRedo: onRedo ?? () {},
            onNewSheet: onNewSheet ?? () {},
            layout: layout,
          ),
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
    for (final key in [ToolRow.paletteKey, ToolRow.eraserKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(
        size.width,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: '$key',
      );
      expect(
        size.height,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: '$key',
      );
    }
    expect(
      tester.getSize(find.byKey(ToolRow.dropperKey)).width,
      greaterThanOrEqualTo(AppTapTargets.min),
    );
    expect(
      tester.getSize(find.byKey(ToolRow.dropperKey)).height,
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

  testWidgets('the palette button carries the ring while the pencil is the '
      'tool, and grows with it', (tester) async {
    double dotSize() => tester
        .getSize(
          find
              .descendant(
                of: find.byKey(ToolRow.paletteKey),
                matching: find.byType(Container),
              )
              .at(1),
        )
        .width;

    await pumpRow(tester);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.selected);
    final selected = dotSize();

    await pumpRow(tester, isEraser: true);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
    expect(dotSize(), lessThan(selected));

    await pumpRow(tester, isDropper: true);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
  });

  testWidgets('the palette button shows the colour in use, even while the '
      'eraser is the tool', (tester) async {
    Color? dotColor() {
      final dot = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ToolRow.paletteKey),
              matching: find.byType(Container),
            )
            .at(1),
      );
      return (dot.decoration! as BoxDecoration).color;
    }

    final blueIndex = DrawPalette.gridIndex(8, 10);
    await pumpRow(tester, colorIndex: blueIndex);
    expect(dotColor(), DrawPalette.colorAt(blueIndex));

    await pumpRow(tester, colorIndex: blueIndex, isEraser: true);
    expect(dotColor(), DrawPalette.colorAt(blueIndex));
  });

  testWidgets('the eraser carries the same ring when active', (tester) async {
    await pumpRow(tester);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.hairline);

    await pumpRow(tester, isEraser: true);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.selected);
    // Nothing else reads as selected while the eraser is active, whatever
    // index it was left on.
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
  });

  testWidgets('the dropper carries the same ring when active, and nothing '
      'else reads as selected', (tester) async {
    await pumpRow(tester);
    expect(borderWidthOf(tester, ToolRow.dropperKey), AppBorders.hairline);
    // The pencil is the default tool, so its size and colour are selected.
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.selected);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.selected);

    await pumpRow(tester, isDropper: true);
    expect(borderWidthOf(tester, ToolRow.dropperKey), AppBorders.selected);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
  });

  testWidgets('the dropper\'s glyph grows when selected, on top of the ring', (
    tester,
  ) async {
    double glyphSize() => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(ToolRow.dropperKey),
            matching: find.byIcon(Icons.colorize),
          ),
        )
        .size!;

    await pumpRow(tester);
    final unselected = glyphSize();

    await pumpRow(tester, isDropper: true);
    expect(glyphSize(), greaterThan(unselected));
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

  testWidgets('every pencil size, the palette button and the tools have a '
      'spoken name', (tester) async {
    await pumpRow(tester);

    for (var i = 0; i < DrawPencils.names.length; i++) {
      expect(
        tester.getSemantics(find.byKey(ToolRow.sizeKey(i))),
        isSemantics(label: DrawPencils.names[i], isButton: true),
      );
    }
    expect(
      tester.getSemantics(find.byKey(ToolRow.paletteKey)),
      isSemantics(
        label: 'Colours',
        value: DrawPalette.nameAt(DrawPalette.defaultIndex),
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(ToolRow.eraserKey)),
      isSemantics(label: 'Eraser', isButton: true),
    );
    expect(
      tester.getSemantics(find.byKey(ToolRow.dropperKey)),
      isSemantics(label: 'Colour dropper', isButton: true),
    );
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.byTooltip('New sheet'), findsOneWidget);
  });

  testWidgets('the palette button names the colour in use and reports selected '
      'to the semantics tree', (tester) async {
    final index = DrawPalette.gridIndex(3, 5);
    await pumpRow(tester, colorIndex: index, isEraser: true);
    expect(
      tester.getSemantics(find.byKey(ToolRow.paletteKey)),
      isSemantics(
        label: 'Colours',
        value: DrawPalette.nameAt(index),
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
  });

  testWidgets('the dropper reports selected to the semantics tree, not only to '
      'the eye', (tester) async {
    await pumpRow(tester);
    expect(
      tester.getSemantics(find.byKey(ToolRow.dropperKey)),
      isSemantics(
        label: 'Colour dropper',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );

    await pumpRow(tester, isDropper: true);
    expect(
      tester.getSemantics(find.byKey(ToolRow.dropperKey)),
      isSemantics(
        label: 'Colour dropper',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
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
    'tapping a size, a colour from the popup, the eraser, the dropper and the '
    'action buttons '
    'calls back',
    (tester) async {
      int? tappedSize;
      int? tappedColor;
      var erased = false;
      var dropped = false;
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
        onDropperSelected: () => dropped = true,
        onUndo: () => undone = true,
        onRedo: () => redone = true,
        onNewSheet: () => newSheet = true,
      );

      await tester.tap(find.byKey(ToolRow.sizeKey(2)));
      final chosen = DrawPalette.gridIndex(5, 5);
      await tester.tap(find.byKey(ToolRow.paletteKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PalettePopup.squareKey(chosen)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ToolRow.eraserKey));
      await tester.tap(find.byKey(ToolRow.dropperKey));
      await tester.tap(find.byKey(ToolRow.undoKey));
      await tester.tap(find.byKey(ToolRow.redoKey));
      await tester.tap(find.byKey(ToolRow.newSheetKey));

      expect(tappedSize, 2);
      expect(tappedColor, DrawPalette.gridIndex(5, 5));
      expect(erased, isTrue);
      expect(dropped, isTrue);
      expect(undone, isTrue);
      expect(redone, isTrue);
      expect(newSheet, isTrue);
    },
  );

  testWidgets('the palette button opens the popup, ringed on the colour in '
      'use, and dismissing it calls nothing back', (tester) async {
    int? tapped;
    final index = DrawPalette.gridIndex(2, 9);
    await pumpRow(
      tester,
      colorIndex: index,
      onColorSelected: (i) => tapped = i,
    );
    expect(find.byType(PalettePopup), findsNothing);

    await tester.tap(find.byKey(ToolRow.paletteKey));
    await tester.pumpAndSettle();
    expect(find.byType(PalettePopup), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(PalettePopup.highlightKey)),
      tester.getCenter(find.byKey(PalettePopup.squareKey(index))),
    );

    await tester.tap(find.byKey(PalettePopup.closeKey));
    await tester.pumpAndSettle();
    expect(find.byType(PalettePopup), findsNothing);
    expect(tapped, isNull);
  });

  for (final orientation in {
    'portrait': (size: const Size(360, 640), layout: ToolRowLayout.band),
    'landscape': (size: const Size(640, 360), layout: ToolRowLayout.rail),
  }.entries) {
    testWidgets(
      'lays out without overflow at 200% text scale, ${orientation.key}',
      (tester) async {
        tester.view.physicalSize = orientation.value.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpRow(tester, textScale: 2, layout: orientation.value.layout);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  /// The vertical centres of [keys], rounded to whole pixels and in the order
  /// they appear — two controls sharing a line share a centre, which is what
  /// [Wrap]'s [WrapCrossAlignment.center] gives a 56 dp control beside a
  /// 72 dp one.
  List<double> lineCentres(WidgetTester tester, List<Key> keys) => [
    for (final key in keys)
      tester.getCenter(find.byKey(key)).dy.roundToDouble(),
  ];

  /// The three tools, which share a line.
  const toolKeys = [ToolRow.paletteKey, ToolRow.eraserKey, ToolRow.dropperKey];

  /// The actions, which share the line below.
  const actionKeys = [ToolRow.undoKey, ToolRow.redoKey, ToolRow.newSheetKey];

  group('the rail', () {
    testWidgets('puts the four sizes on one line, the three tools on the next '
        'and the actions below them', (tester) async {
      await pumpRow(tester, layout: ToolRowLayout.rail, canUndo: true);

      expect(tester.getSize(find.byType(ToolRow)).width, ToolRow.railWidth);

      final sizes = lineCentres(tester, [
        for (var i = 0; i < DrawPencils.widths.length; i++) ToolRow.sizeKey(i),
      ]);
      expect(sizes.toSet(), hasLength(1), reason: 'sizes: $sizes');

      final tools = lineCentres(tester, toolKeys);
      expect(tools.toSet(), hasLength(1), reason: 'tools: $tools');
      expect(tools.first, greaterThan(sizes.first));

      final actions = lineCentres(tester, actionKeys);
      expect(actions.toSet(), hasLength(1), reason: 'actions: $actions');
      expect(actions.first, greaterThan(tools.first));
    });

    testWidgets('keeps the actions together on a rail as narrow as a half '
        'window of 640 dp allows', (tester) async {
      await pumpRow(
        tester,
        layout: ToolRowLayout.rail,
        width: ToolRow.railWidthFor(640),
        canUndo: true,
      );

      final actions = lineCentres(tester, actionKeys);
      expect(actions.toSet(), hasLength(1), reason: 'actions: $actions');
    });

    test('takes half the window at most, and no more than its own width', () {
      expect(ToolRow.railWidthFor(1280), ToolRow.railWidth);
      // Half of this is more than the rail needs.
      expect(ToolRow.railWidthFor(640), ToolRow.railWidth);
      // Narrower than the rail, and half is all it gets.
      expect(ToolRow.railWidthFor(400), 200);
    });
  });

  testWidgets('the band puts the tools below the sizes and the actions below '
      'the tools, the order the rail uses', (tester) async {
    await usePhoneSurface(tester);
    await pumpRow(tester);

    final sizes = tester.getCenter(find.byKey(ToolRow.sizeKey(0))).dy;
    final tools = lineCentres(tester, toolKeys);
    final actions = lineCentres(tester, actionKeys);
    expect(tools.toSet(), hasLength(1), reason: 'tools: $tools');
    expect(actions.toSet(), hasLength(1), reason: 'actions: $actions');
    expect(tools.first, greaterThan(sizes));
    expect(actions.first, greaterThan(tools.first));
  });
}
