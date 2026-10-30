// [PalettePopup]'s done criteria (`PLAN-phase-8.md` §4.7): every colour the
// picker offers is a square with a spoken name, the one in use is ringed and
// nothing else is, a tap picks and closes, and the whole thing fits a phone
// in either orientation without scrolling.
//
// The twelve paint-box colours are not in the popup: they are swatches in the
// tool row (`tool_row.dart`), and the popup rings nothing for one of them.
//
// The squares are deliberately below the 56 dp tap-target floor — a small
// square palette is what the player asked for (`palette_popup.dart`'s file
// header) — so no test here asserts the floor against them. They assert the
// side they are drawn at instead, so that "small" cannot quietly become
// "unusably small".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/draw/model/palette.dart';
import 'package:zibo_games/features/draw/ui/palette_popup.dart';

import '../../../core/ui/ui_harness.dart';

void main() {
  /// What the last popup returned, and whether it has returned at all.
  int? result;
  var closed = false;

  /// Pumps a screen with one button that opens the popup, taps it and settles
  /// on the open popup.
  Future<void> openPopup(
    WidgetTester tester, {
    int? selectedIndex,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    result = null;
    closed = false;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showPalettePopup(
                  context,
                  selectedIndex: selectedIndex,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
      theme: theme ?? AppTheme.day(),
      textScale: textScale,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> useWindow(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A square's drawn side: its tappable cell less the gap it shares with its
  /// neighbours.
  double sideOf(WidgetTester tester, int index) =>
      tester.getSize(find.byKey(PalettePopup.squareKey(index))).width -
      PalettePopup.gap;

  testWidgets('offers the 256-colour grid and the six skin tones, and no '
      'paint-box colour', (tester) async {
    await openPopup(tester);

    expect(DrawPalette.pickerIndices, hasLength(262));
    for (final index in DrawPalette.pickerIndices) {
      expect(
        find.byKey(PalettePopup.squareKey(index)),
        findsOneWidget,
        reason: DrawPalette.nameAt(index),
      );
    }
    // Exactly those: 0-11 are the tool row's swatches, not the popup's
    // (`DrawPalette.rowIndices`).
    for (var index = 0; index < 12; index++) {
      expect(find.byKey(PalettePopup.squareKey(index)), findsNothing);
    }
    expect(
      find.byWidgetPredicate(
        (w) => w.key.toString().contains('PalettePopup.square.'),
      ),
      findsNWidgets(262),
    );
  });

  testWidgets('lays the grid out by hue across and tint to shade down, with '
      'the skin tones below it', (tester) async {
    await openPopup(tester);

    Offset centre(int row, int column) => tester.getCenter(
      find.byKey(PalettePopup.squareKey(DrawPalette.gridIndex(row, column))),
    );
    final cell = tester.getSize(find.byKey(PalettePopup.squareKey(18))).width;

    expect(centre(0, 1).dx - centre(0, 0).dx, closeTo(cell, 0.01));
    expect(centre(1, 0).dy - centre(0, 0).dy, closeTo(cell, 0.01));
    expect(centre(15, 15).dx, greaterThan(centre(0, 0).dx));
    expect(centre(15, 15).dy, greaterThan(centre(0, 0).dy));

    // The first skin tone sits under the grid's first column, past a gap that
    // sets the tones apart from the grid's last row.
    final skin = tester.getCenter(find.byKey(PalettePopup.squareKey(12)));
    expect(skin.dx, closeTo(centre(15, 0).dx, 0.01));
    expect(
      skin.dy - centre(15, 0).dy,
      closeTo(cell + PalettePopup.sectionGap, 0.01),
    );
    final lastSkin = tester.getCenter(find.byKey(PalettePopup.squareKey(17)));
    expect(lastSkin.dy, closeTo(skin.dy, 0.01));
    expect(lastSkin.dx - skin.dx, closeTo(5 * cell, 0.01));
  });

  testWidgets('every square has a spoken name and is a button', (tester) async {
    final selected = DrawPalette.gridIndex(8, 1);
    await openPopup(tester, selectedIndex: selected);

    for (final index in DrawPalette.pickerIndices) {
      expect(
        tester.getSemantics(find.byKey(PalettePopup.squareKey(index))),
        isSemantics(
          label: DrawPalette.nameAt(index),
          isButton: true,
          hasSelectedState: true,
          isSelected: index == selected,
        ),
        reason: 'square $index',
      );
    }
  });

  group('the highlight', () {
    testWidgets('rings the selected square, with a ${AppBorders.selected} dp '
        'border, and no other', (tester) async {
      final index = DrawPalette.gridIndex(5, 7);
      await openPopup(tester, selectedIndex: index);

      expect(find.byKey(PalettePopup.highlightKey), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(PalettePopup.highlightKey)),
        tester.getCenter(find.byKey(PalettePopup.squareKey(index))),
      );
      final ring = tester.widget<DecoratedBox>(
        find.byKey(PalettePopup.highlightKey),
      );
      final border = (ring.decoration as BoxDecoration).border!;
      expect(border.top.width, AppBorders.selected);

      // Outside the square it is drawn around, clear of its neighbours' own
      // edges only by the gap: it is bigger than the square by its width.
      expect(
        tester.getSize(find.byKey(PalettePopup.highlightKey)).width,
        closeTo(sideOf(tester, index) + 2 * AppBorders.selected, 0.01),
      );
    });

    testWidgets('is drawn in the text colour of either theme, with an inner '
        'line in the surface colour, so it reads on dark and light squares', (
      tester,
    ) async {
      for (final theme in appThemes.values) {
        await openPopup(
          tester,
          selectedIndex: DrawPalette.gridIndex(15, 3),
          theme: theme(),
        );
        final scheme = theme().colorScheme;
        final outer = tester.widget<DecoratedBox>(
          find.byKey(PalettePopup.highlightKey),
        );
        expect(
          ((outer.decoration as BoxDecoration).border! as Border).top.color,
          scheme.onSurface,
        );
        final inner = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byKey(PalettePopup.highlightKey),
                matching: find.byType(DecoratedBox),
              )
              .last,
        );
        expect(
          ((inner.decoration as BoxDecoration).border! as Border).top.color,
          scheme.surface,
        );
        await tester.tap(find.byKey(PalettePopup.closeKey));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('marks a skin tone as it does a grid colour', (tester) async {
      await openPopup(tester, selectedIndex: 14);

      expect(
        tester.getCenter(find.byKey(PalettePopup.highlightKey)),
        tester.getCenter(find.byKey(PalettePopup.squareKey(14))),
      );
    });

    testWidgets('moving the selection moves the ring and nothing else', (
      tester,
    ) async {
      List<Offset> squareCentres() => [
        for (final i in DrawPalette.pickerIndices)
          tester.getCenter(find.byKey(PalettePopup.squareKey(i))),
      ];

      await openPopup(tester, selectedIndex: DrawPalette.gridIndex(0, 0));
      final before = squareCentres();
      final dialogBefore = tester.getRect(find.byType(Dialog));
      await tester.tap(find.byKey(PalettePopup.closeKey));
      await tester.pumpAndSettle();

      await openPopup(tester, selectedIndex: DrawPalette.gridIndex(15, 15));
      expect(squareCentres(), before);
      expect(tester.getRect(find.byType(Dialog)), dialogBefore);
    });

    testWidgets('rings nothing when no colour is in use', (tester) async {
      await openPopup(tester);
      expect(find.byKey(PalettePopup.highlightKey), findsNothing);
    });

    testWidgets('rings nothing for a paint-box colour, which is the tool '
        'row\'s to ring', (tester) async {
      // Ringing the grid square nearest to Red would claim that a different
      // colour is chosen while the row rings Red itself.
      for (final index in DrawPalette.rowIndices) {
        await openPopup(tester, selectedIndex: index);

        expect(
          find.byKey(PalettePopup.highlightKey),
          findsNothing,
          reason: DrawPalette.nameAt(index),
        );
        for (final square in DrawPalette.pickerIndices) {
          expect(
            tester.getSemantics(find.byKey(PalettePopup.squareKey(square))),
            isSemantics(
              label: DrawPalette.nameAt(square),
              isButton: true,
              hasSelectedState: true,
              isSelected: false,
            ),
            reason: '${DrawPalette.nameAt(index)}: square $square',
          );
        }
        await tester.tap(find.byKey(PalettePopup.closeKey));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('rings nothing for an index outside the palette', (
      tester,
    ) async {
      await openPopup(tester, selectedIndex: DrawPalette.colors.length);
      expect(find.byKey(PalettePopup.highlightKey), findsNothing);
    });
  });

  group('choosing', () {
    testWidgets('a tap on a square returns its index and closes the popup', (
      tester,
    ) async {
      await openPopup(tester);
      final index = DrawPalette.gridIndex(9, 12);

      await tester.tap(find.byKey(PalettePopup.squareKey(index)));
      await tester.pumpAndSettle();

      expect(result, index);
      expect(closed, isTrue);
      expect(find.byType(PalettePopup), findsNothing);
    });

    testWidgets('a skin tone is chosen the same way', (tester) async {
      await openPopup(tester);

      await tester.tap(find.byKey(PalettePopup.squareKey(16)));
      await tester.pumpAndSettle();

      expect(result, 16);
    });

    testWidgets('a tap in the gap between two squares still picks one', (
      tester,
    ) async {
      await openPopup(tester);
      final a = DrawPalette.gridIndex(3, 3);
      final b = DrawPalette.gridIndex(3, 4);
      final between =
          (tester.getCenter(find.byKey(PalettePopup.squareKey(a))) +
              tester.getCenter(find.byKey(PalettePopup.squareKey(b)))) /
          2;

      await tester.tapAt(between + const Offset(0.4, 0));
      await tester.pumpAndSettle();

      expect(result, anyOf(a, b));
    });

    testWidgets('the close button closes without choosing', (tester) async {
      await openPopup(tester, selectedIndex: 14);

      await tester.tap(find.byKey(PalettePopup.closeKey));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(closed, isTrue);
      expect(find.byType(PalettePopup), findsNothing);
    });

    testWidgets('a tap on the barrier closes without choosing', (tester) async {
      await openPopup(tester);

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(closed, isTrue);
    });

    testWidgets('the close button is named and meets the tap-target floor', (
      tester,
    ) async {
      await openPopup(tester);

      expect(find.byTooltip('Close'), findsOneWidget);
      final size = tester.getSize(find.byKey(PalettePopup.closeKey));
      expect(size.width, greaterThanOrEqualTo(AppTapTargets.min));
      expect(size.height, greaterThanOrEqualTo(AppTapTargets.min));
    });
  });

  group('fitting', () {
    final windows = {
      'a 360 x 640 portrait phone': const Size(360, 640),
      'a 640 x 360 landscape phone': const Size(640, 360),
      'a 1024 x 768 tablet': const Size(1024, 768),
    };

    for (final window in windows.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${window.key} at ${scale}x text, whole and unscrolled', (
          tester,
        ) async {
          await useWindow(tester, window.value);
          await openPopup(
            tester,
            selectedIndex: DrawPalette.gridIndex(15, 15),
            textScale: scale,
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsNothing);

          // Everything inside the window, ring and close button included.
          final screen = Offset.zero & window.value;
          for (final finder in [
            find.byType(Dialog),
            find.byKey(PalettePopup.closeKey),
            find.byKey(PalettePopup.highlightKey),
            find.byKey(PalettePopup.squareKey(DrawPalette.gridIndex(0, 0))),
            find.byKey(PalettePopup.squareKey(DrawPalette.gridIndex(15, 15))),
            find.byKey(PalettePopup.squareKey(12)),
            find.byKey(PalettePopup.squareKey(17)),
          ]) {
            final rect = tester.getRect(finder);
            expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
            expect(
              screen.contains(rect.bottomRight - const Offset(0.1, 0.1)),
              isTrue,
              reason: '$rect',
            );
          }

          // Small, but not unusably so: the phones are the tightest windows
          // the app supports.
          final side = sideOf(tester, DrawPalette.gridStart);
          expect(side, greaterThanOrEqualTo(14));
          expect(side, lessThanOrEqualTo(PalettePopup.maxSide));
        });
      }
    }

    testWidgets('a roomy window stops growing the squares at their maximum', (
      tester,
    ) async {
      await useWindow(tester, const Size(1600, 1200));
      await openPopup(tester);

      expect(sideOf(tester, 18), PalettePopup.maxSide);
    });

    test('sideFor never asks for more than fits, in either direction', () {
      // Width-bound: 16 columns across 320 dp.
      expect(
        PalettePopup.sideFor(width: 320, height: 2000),
        320 / 16 - PalettePopup.gap,
      );
      // Height-bound: 17 rows and the section gap down 300 dp.
      expect(
        PalettePopup.sideFor(width: 2000, height: 300),
        (300 - PalettePopup.sectionGap) / 17 - PalettePopup.gap,
      );
      // Never negative, however small the room.
      expect(PalettePopup.sideFor(width: 10, height: 10), 0);
    });
  });
}
