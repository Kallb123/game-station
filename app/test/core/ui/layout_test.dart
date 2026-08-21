// `ContentWidthCap`'s own tests. The window sizes here are the ones the
// widget's two branches turn on, and the narrow one is the regression: a
// tablet is `AppFormFactor.expanded` by its short side, so a 600 dp-wide
// window in portrait is expanded while having less room than
// `maxContentWidth` — the case where a cap applied as a width rather than as
// a maximum drew the difference off the right-hand edge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/layout.dart';
import 'package:zibo_games/core/ui/theme.dart';

import 'ui_harness.dart';

/// The content [ContentWidthCap] is measured through: full-bleed in both
/// axes, so whatever it ends up being given is what gets measured.
const Widget _child = SizedBox.expand(key: _childKey);

const Key _childKey = Key('capped content');

/// Sizes the window to [size] for the duration of the test.
void _useWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the cap alone in a window [width] wide, in a box [room] wide — the
/// room a screen's padding leaves it, which is what the cap has to fit into
/// and not what the window measures.
Future<Rect> _pumpCap(
  WidgetTester tester, {
  required double width,
  required double room,
}) async {
  _useWindow(tester, Size(width, 1024));
  await pumpApp(
    tester,
    Center(
      child: SizedBox(
        width: room,
        height: 800,
        child: const ContentWidthCap(child: _child),
      ),
    ),
    theme: AppTheme.day(),
  );

  expect(tester.takeException(), isNull);
  return tester.getRect(find.byKey(_childKey));
}

void main() {
  testWidgets('draws its child unchanged on a compact window', (tester) async {
    final rect = await _pumpCap(tester, width: 360, room: 312);

    expect(rect.width, 312);
    expect(rect.height, 800, reason: 'the child keeps the height it had');
  });

  testWidgets('caps the child once the window has more room than the cap', (
    tester,
  ) async {
    final rect = await _pumpCap(tester, width: 834, room: 786);

    expect(rect.width, maxContentWidth);
    expect(rect.height, 800, reason: 'the child keeps the height it had');
    expect(
      rect.center.dx,
      closeTo(834 / 2, 0.5),
      reason: 'the capped child is centred in the room it was given',
    );
  });

  // The regression. `AppFormFactor` reads the short side, so this window is
  // expanded and takes the capping branch, with 552 dp of room for a 640 dp
  // cap. The cap is a maximum: the child gets the room there is, and none of
  // it is drawn past the edge.
  testWidgets('fits an expanded window narrower than the cap', (tester) async {
    final rect = await _pumpCap(tester, width: 600, room: 552);

    expect(rect.width, 552);
    expect(rect.height, 800, reason: 'the child keeps the height it had');
    expect(rect.right, lessThanOrEqualTo(600));
  });
}
