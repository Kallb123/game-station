// How much room a screen has, and where its content stops growing
// (`PLAN.md` §6, `PLAN-phase-5.md` §4.8) — the one file every screen reads
// rather than inventing its own breakpoint.

import 'package:flutter/widgets.dart';

/// How much room a window has, by its short side.
///
/// Read from `MediaQuery.sizeOf`, not from the physical device: a phone in
/// landscape and a tablet in a split-screen window are the same problem, and
/// the short side is the one that does not flip between the two.
enum AppFormFactor {
  compact,
  expanded;

  /// 600 dp is Material's own compact/medium boundary, and the number a
  /// "phone or tablet" question actually turns on.
  static const double _expandedBreakpoint = 600;

  /// The form factor of the window [context] is drawn in.
  static AppFormFactor of(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= _expandedBreakpoint
      ? AppFormFactor.expanded
      : AppFormFactor.compact;
}

/// The widest a column of content is allowed to get: 640 dp.
///
/// A settings list stretched across a 10" tablet is a 900 dp-wide switch
/// whose label is at one end and whose control is at the other.
const double maxContentWidth = 640;

/// The widest the Sudoku board is drawn, however much room there is: 560 dp.
const double maxBoardSide = 560;

/// Whether the window is wider than it is tall.
///
/// A screen and a physical device rotating are the same event as far as this
/// is concerned — both change what `MediaQuery.sizeOf` reports, and nothing
/// here reads the platform's own rotation state.
bool isLandscapeWindow(BuildContext context) =>
    MediaQuery.orientationOf(context) == Orientation.landscape;

/// Centres [child] and caps its width at [maxContentWidth] once the window is
/// [AppFormFactor.expanded]; otherwise draws [child] unchanged.
///
/// A `Row` with a single, capped child rather than `Center` on its own:
/// `Center` loosens both axes, which would let [child] collapse to its own
/// height too — every screen this wraps already has the height it needs from
/// its own `Expanded`, and only the width is what a wide window leaves too
/// much of.
class ContentWidthCap extends StatelessWidget {
  const ContentWidthCap({required this.child, super.key});

  /// The content to cap. Given the same height it would have had, and no more
  /// than [maxContentWidth] of width.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppFormFactor.of(context) != AppFormFactor.expanded) return child;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: child,
        ),
      ],
    );
  }
}
