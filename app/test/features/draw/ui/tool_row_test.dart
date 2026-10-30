// [ToolRow]'s own done criteria (`PLAN-phase-8.md` §6, PR 3): every control
// meets its tap-target floor, selection reads from a border's width rather
// than its colour, every control has a spoken label, a disabled undo says so
// to a screen reader as well as to the eye, and none of it overflows at 200%
// text scale in either orientation — with the twelve paint-box colours as
// swatches in the row and the rest behind one palette button that opens
// `palette_popup.dart`, and exactly one of the two ringed at a time.

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
    for (final key in [
      ToolRow.paletteKey,
      ToolRow.eraserKey,
      for (final i in DrawPalette.rowIndices) ToolRow.colorKey(i),
    ]) {
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

  /// A popup colour: a grid square the row has no swatch for.
  final popupColor = DrawPalette.gridIndex(8, 10);

  testWidgets('a selected colour swatch carries a wider border than an '
      'unselected one, and grows', (tester) async {
    double swatchSize(int i) => tester
        .getSize(
          find
              .descendant(
                of: find.byKey(ToolRow.colorKey(i)),
                matching: find.byType(Container),
              )
              .last,
        )
        .width;

    await pumpRow(tester, colorIndex: 3);

    expect(borderWidthOf(tester, ToolRow.colorKey(3)), AppBorders.selected);
    expect(borderWidthOf(tester, ToolRow.colorKey(0)), AppBorders.hairline);
    expect(swatchSize(3), greaterThan(swatchSize(0)));
  });

  testWidgets('the row shows the twelve paint-box colours in order, and not '
      'the skin tones', (tester) async {
    await pumpRow(tester);

    for (final i in DrawPalette.rowIndices) {
      final swatch = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ToolRow.colorKey(i)),
              matching: find.byType(Container),
            )
            .last,
      );
      expect(
        (swatch.decoration! as BoxDecoration).color,
        DrawPalette.colorAt(i),
        reason: DrawPalette.nameAt(i),
      );
    }
    for (var i = DrawPalette.rowCount; i < DrawPalette.colors.length; i++) {
      expect(find.byKey(ToolRow.colorKey(i)), findsNothing, reason: '$i');
    }
  });

  testWidgets('a row colour rings its swatch and not the palette button', (
    tester,
  ) async {
    for (final i in DrawPalette.rowIndices) {
      await pumpRow(tester, colorIndex: i);

      expect(
        borderWidthOf(tester, ToolRow.colorKey(i)),
        AppBorders.selected,
        reason: DrawPalette.nameAt(i),
      );
      expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
    }
  });

  testWidgets('a popup colour rings the palette button and no swatch', (
    tester,
  ) async {
    for (final i in [popupColor, 12, 17, DrawPalette.gridStart]) {
      await pumpRow(tester, colorIndex: i);

      expect(
        borderWidthOf(tester, ToolRow.paletteKey),
        AppBorders.selected,
        reason: DrawPalette.nameAt(i),
      );
      for (final swatch in DrawPalette.rowIndices) {
        expect(
          borderWidthOf(tester, ToolRow.colorKey(swatch)),
          AppBorders.hairline,
          reason: '${DrawPalette.nameAt(i)}: ${DrawPalette.nameAt(swatch)}',
        );
      }
    }
  });

  testWidgets('never more than one of the swatches and the palette button is '
      'ringed, whichever colour is in use', (tester) async {
    for (var i = 0; i < DrawPalette.colors.length; i += 7) {
      await pumpRow(tester, colorIndex: i);

      final ringed = [
        for (final swatch in DrawPalette.rowIndices)
          if (borderWidthOf(tester, ToolRow.colorKey(swatch)) ==
              AppBorders.selected)
            swatch,
        if (borderWidthOf(tester, ToolRow.paletteKey) == AppBorders.selected)
          -1,
      ];
      expect(ringed, hasLength(1), reason: DrawPalette.nameAt(i));
    }
  });

  testWidgets('while the eraser or the dropper is the tool, neither a swatch '
      'nor the palette button is ringed', (tester) async {
    for (final colorIndex in [3, popupColor]) {
      for (final (eraser, dropper) in [(true, false), (false, true)]) {
        await pumpRow(
          tester,
          colorIndex: colorIndex,
          isEraser: eraser,
          isDropper: dropper,
        );

        expect(borderWidthOf(tester, ToolRow.paletteKey), AppBorders.hairline);
        for (final swatch in DrawPalette.rowIndices) {
          expect(
            borderWidthOf(tester, ToolRow.colorKey(swatch)),
            AppBorders.hairline,
            reason: 'colour $colorIndex, ${DrawPalette.nameAt(swatch)}',
          );
        }
      }
    }
  });

  group('the palette button', () {
    /// The outer button's descendants that draw a coloured dot: the second
    /// [Container] under it, after the ring itself, when there is a dot.
    Finder containers() => find.descendant(
      of: find.byKey(ToolRow.paletteKey),
      matching: find.byType(Container),
    );

    Finder glyph(IconData icon) => find.descendant(
      of: find.byKey(ToolRow.paletteKey),
      matching: find.byIcon(icon),
    );

    testWidgets('shows a popup colour as a dot, and grows it with the ring', (
      tester,
    ) async {
      double dotSize() => tester.getSize(containers().at(1)).width;
      Color? dotColor() =>
          (tester.widget<Container>(containers().at(1)).decoration!
                  as BoxDecoration)
              .color;

      await pumpRow(tester, colorIndex: popupColor);
      expect(dotColor(), DrawPalette.colorAt(popupColor));
      final selected = dotSize();

      await pumpRow(tester, colorIndex: popupColor, isEraser: true);
      expect(dotSize(), lessThan(selected));
      // Still that colour while the eraser is the tool, so a child can see
      // what the pencil will be when they put it back.
      expect(dotColor(), DrawPalette.colorAt(popupColor));
    });

    testWidgets('shows a palette glyph beside a dot for a popup colour', (
      tester,
    ) async {
      await pumpRow(tester, colorIndex: popupColor);

      expect(glyph(Icons.palette), findsOneWidget);
    });

    testWidgets('is the palette glyph alone, with no dot, for a row colour', (
      tester,
    ) async {
      await pumpRow(tester, colorIndex: 3);

      // The ring is the only container: no dot of the row colour, so that two
      // controls do not show the same one.
      expect(containers(), findsOneWidget);
      expect(glyph(Icons.palette), findsOneWidget);
      expect(tester.getSize(glyph(Icons.palette)).width, AppIconSizes.standard);
    });
  });

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

  testWidgets('the dropper carries the same ring when active, and nothing '
      'else reads as selected', (tester) async {
    await pumpRow(tester);
    expect(borderWidthOf(tester, ToolRow.dropperKey), AppBorders.hairline);
    // The pencil is the default tool, so its size and colour are selected.
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.selected);
    expect(borderWidthOf(tester, ToolRow.colorKey(0)), AppBorders.selected);

    await pumpRow(tester, isDropper: true);
    expect(borderWidthOf(tester, ToolRow.dropperKey), AppBorders.selected);
    expect(borderWidthOf(tester, ToolRow.eraserKey), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.sizeKey(0)), AppBorders.hairline);
    expect(borderWidthOf(tester, ToolRow.colorKey(0)), AppBorders.hairline);
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

  testWidgets('every pencil size, colour and tool has a spoken name', (
    tester,
  ) async {
    await pumpRow(tester);

    for (var i = 0; i < DrawPencils.names.length; i++) {
      expect(
        tester.getSemantics(find.byKey(ToolRow.sizeKey(i))),
        isSemantics(label: DrawPencils.names[i], isButton: true),
      );
    }
    for (final i in DrawPalette.rowIndices) {
      expect(
        tester.getSemantics(find.byKey(ToolRow.colorKey(i))),
        isSemantics(
          label: DrawPalette.names[i],
          isButton: true,
          hasSelectedState: true,
          isSelected: i == DrawPalette.defaultIndex,
        ),
        reason: DrawPalette.names[i],
      );
    }
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

  testWidgets('the palette button names the popup colour in use and reports '
      'selected to the semantics tree', (tester) async {
    await pumpRow(tester, colorIndex: popupColor);
    expect(
      tester.getSemantics(find.byKey(ToolRow.paletteKey)),
      isSemantics(
        label: 'More colours',
        value: DrawPalette.nameAt(popupColor),
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    await pumpRow(tester, colorIndex: popupColor, isEraser: true);
    expect(
      tester.getSemantics(find.byKey(ToolRow.paletteKey)),
      isSemantics(
        label: 'More colours',
        value: DrawPalette.nameAt(popupColor),
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
  });

  testWidgets('the palette button has no value and is not selected while a '
      'row colour is in use', (tester) async {
    await pumpRow(tester, colorIndex: 4);

    expect(
      tester.getSemantics(find.byKey(ToolRow.paletteKey)),
      isSemantics(
        label: 'More colours',
        value: '',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(ToolRow.colorKey(4))),
      isSemantics(
        label: 'Teal',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
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
    'tapping a size, a swatch, a colour from the popup, the eraser, the dropper '
    'and the action buttons calls back',
    (tester) async {
      int? tappedSize;
      final tappedColors = <int>[];
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
        onColorSelected: tappedColors.add,
        onEraserSelected: () => erased = true,
        onDropperSelected: () => dropped = true,
        onUndo: () => undone = true,
        onRedo: () => redone = true,
        onNewSheet: () => newSheet = true,
      );

      await tester.tap(find.byKey(ToolRow.sizeKey(2)));
      await tester.tap(find.byKey(ToolRow.colorKey(5)));
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
      expect(tappedColors, [5, DrawPalette.gridIndex(5, 5)]);
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

  testWidgets('the popup opens unringed while a row colour is in use', (
    tester,
  ) async {
    await pumpRow(tester, colorIndex: 0);

    await tester.tap(find.byKey(ToolRow.paletteKey));
    await tester.pumpAndSettle();

    expect(find.byType(PalettePopup), findsOneWidget);
    expect(find.byKey(PalettePopup.highlightKey), findsNothing);
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

  /// Which line each of [keys] landed on, as its count per shared centre, in
  /// the order the lines run down the widget.
  Map<double, int> rowsOf(WidgetTester tester, List<Key> keys) {
    final rows = <double, int>{};
    for (final centre in lineCentres(tester, keys)) {
      rows[centre] = (rows[centre] ?? 0) + 1;
    }
    return rows;
  }

  /// The three tools, which share a line.
  const toolKeys = [ToolRow.paletteKey, ToolRow.eraserKey, ToolRow.dropperKey];

  /// The actions, which share the line below.
  const actionKeys = [ToolRow.undoKey, ToolRow.redoKey, ToolRow.newSheetKey];

  final colorKeys = [
    for (final i in DrawPalette.rowIndices) ToolRow.colorKey(i),
  ];

  Future<void> useWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('the rail', () {
    testWidgets('puts the four sizes on one line, the three tools on the next, '
        'the actions below them and the colours last', (tester) async {
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

      expect(
        rowsOf(tester, colorKeys).keys.first,
        greaterThan(actions.first),
        reason: 'the colours come after the actions',
      );
    });

    testWidgets('folds the twelve colours into two rows of six on the wide '
        'rail', (tester) async {
      await pumpRow(tester, layout: ToolRowLayout.rail);

      final rows = rowsOf(tester, colorKeys);
      expect(rows.values, [6, 6], reason: 'rows: $rows');
    });

    testWidgets('folds them into three rows of four on the narrow rail, with '
        'the actions still on one line', (tester) async {
      await pumpRow(
        tester,
        layout: ToolRowLayout.rail,
        width: ToolRow.narrowRailWidth,
        canUndo: true,
      );

      final rows = rowsOf(tester, colorKeys);
      expect(rows.values, [4, 4, 4], reason: 'rows: $rows');
      expect(
        lineCentres(tester, actionKeys).toSet(),
        hasLength(1),
        reason: 'actions',
      );
      expect(
        lineCentres(tester, toolKeys).toSet(),
        hasLength(1),
        reason: 'tools',
      );
      expect(
        lineCentres(tester, [
          for (var i = 0; i < DrawPencils.widths.length; i++)
            ToolRow.sizeKey(i),
        ]).toSet(),
        hasLength(1),
        reason: 'sizes',
      );
    });

    test('takes half the window at most, and one of its two widths', () {
      expect(ToolRow.railWidthFor(1280), ToolRow.railWidth);
      expect(ToolRow.railWidthFor(ToolRow.railWidth * 2), ToolRow.railWidth);
      // A 640 dp phone: half is 320, between the two widths, so the wide rail
      // would take more than half the window and the narrow one is what fits.
      expect(ToolRow.railWidthFor(640), ToolRow.narrowRailWidth);
      expect(ToolRow.railWidthFor(700), ToolRow.narrowRailWidth);
      // Narrower than either, and half is all it gets.
      expect(ToolRow.railWidthFor(400), 200);
    });

    test('the narrow rail is four swatches wide, the wide one six', () {
      expect(ToolRow.narrowRailWidth, 4 * 56 + 3 * 8);
      expect(ToolRow.railWidth, 6 * 56 + 5 * 8);
    });
  });

  group('the band', () {
    testWidgets('puts the tools below the sizes, the actions below the tools '
        'and the colours below the actions, the order the rail uses', (
      tester,
    ) async {
      await useWindow(tester, const Size(800, 900));
      await pumpRow(tester);

      final sizes = tester.getCenter(find.byKey(ToolRow.sizeKey(0))).dy;
      final tools = lineCentres(tester, toolKeys);
      final actions = lineCentres(tester, actionKeys);
      expect(tools.toSet(), hasLength(1), reason: 'tools: $tools');
      expect(actions.toSet(), hasLength(1), reason: 'actions: $actions');
      expect(tools.first, greaterThan(sizes));
      expect(actions.first, greaterThan(tools.first));
      expect(rowsOf(tester, colorKeys).keys.first, greaterThan(actions.first));
    });

    testWidgets('a window with room for six swatches folds the colours into '
        'two rows of six', (tester) async {
      await useWindow(tester, const Size(800, 900));
      await pumpRow(tester);

      expect(rowsOf(tester, colorKeys).values, [6, 6]);
    });

    testWidgets('a phone held upright gets three rows of four, not five, '
        'five and two', (tester) async {
      // 312 dp is a 360 dp phone less the screen's 24 dp padding each side:
      // room for five swatches, not six, so an unbounded group would fold
      // 5 + 5 + 2.
      await pumpRow(tester, width: 312);

      final rows = rowsOf(tester, colorKeys);
      expect(rows.values, [4, 4, 4], reason: 'rows: $rows');
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps each row of the colours centred under the others', (
      tester,
    ) async {
      await pumpRow(tester, width: 312);

      // The four swatches of a row are as wide as the group, which is centred
      // in the band: the row's two outer swatches mirror about the centre.
      final first = tester.getCenter(find.byKey(ToolRow.colorKey(0))).dx;
      final fourth = tester.getCenter(find.byKey(ToolRow.colorKey(3))).dx;
      expect(
        (first + fourth) / 2,
        closeTo(tester.getCenter(find.byType(ToolRow)).dx, 0.5),
      );
    });

    test('colorColumnsFor is six where six fit and four otherwise', () {
      expect(ToolRow.colorColumnsFor(ToolRow.railWidth), 6);
      expect(ToolRow.colorColumnsFor(ToolRow.railWidth - 1), 4);
      expect(ToolRow.colorColumnsFor(312), 4);
      expect(ToolRow.colorColumnsFor(double.infinity), 6);
    });
  });
}
