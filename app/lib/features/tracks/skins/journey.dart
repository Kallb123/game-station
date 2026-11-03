// The solve animation as one timeline (`PLAN-phase-9-tracks.md` §4.8): the
// journey runs `t` from 0 to 1, then the goal's `arrival` from 0 to 1. Pure
// arithmetic on a duration, so the play screen's ticker only supplies elapsed
// time and a test can ask what the board shows at any moment without pumping
// frames.

import 'package:flutter/foundation.dart' show immutable;

import 'track_geometry.dart';
import 'track_skin.dart';

/// Where the solve animation is: journey [t] and goal [arrival], each 0..1.
@immutable
class JourneyFrame {
  const JourneyFrame(this.t, this.arrival);

  /// Nothing has moved: the traveller at the start, the goal waiting. What
  /// every unsolved board shows.
  static const JourneyFrame waiting = JourneyFrame(0, 0);

  /// The traveller at the goal and the goal arrived. Where `reduceMotion`
  /// jumps straight to.
  static const JourneyFrame arrived = JourneyFrame(1, 1);

  /// 0 at the start port, 1 at the goal port.
  final double t;

  /// 0 while the goal waits, 1 once it has changed.
  final double arrival;

  @override
  bool operator ==(Object other) =>
      other is JourneyFrame && other.t == t && other.arrival == arrival;

  @override
  int get hashCode => Object.hash(t, arrival);

  @override
  String toString() => 'JourneyFrame(t: $t, arrival: $arrival)';
}

/// How long the traveller takes to run [route] under [skin].
Duration travelDuration(TrackSkin skin, TrackGeometry route) => Duration(
  microseconds:
      (route.length / skin.cellsPerSecond * Duration.microsecondsPerSecond)
          .round(),
);

/// The whole animation: travel, then arrival.
Duration journeyDuration(TrackSkin skin, TrackGeometry route) =>
    travelDuration(skin, route) + skin.arrivalDuration;

/// The frame [elapsed] after the board was solved. Linear in time on both
/// halves: the traveller keeps one speed, which is what makes `cellsPerSecond`
/// mean what it says, and the goal's sprite frames step evenly.
JourneyFrame journeyFrameAt(
  TrackSkin skin,
  TrackGeometry route,
  Duration elapsed,
) {
  if (elapsed <= Duration.zero) return JourneyFrame.waiting;
  final travel = travelDuration(skin, route);
  if (elapsed < travel) {
    return JourneyFrame(elapsed.inMicroseconds / travel.inMicroseconds, 0);
  }
  final arriving = elapsed - travel;
  final arrival = skin.arrivalDuration;
  if (arrival <= Duration.zero || arriving >= arrival) {
    return JourneyFrame.arrived;
  }
  return JourneyFrame(1, arriving.inMicroseconds / arrival.inMicroseconds);
}
