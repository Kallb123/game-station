// `SnakeRules.moveTicksAt` and the `normal`/`easy` tuning
// (`PLAN-phase-7-snake.md` §4.2, §4.4).

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_rules.dart';

void main() {
  group('moveTicksAt', () {
    test('starts at startMoveTicks on level 1 with nothing eaten', () {
      expect(
        SnakeRules.normal.moveTicksAt(1, 0),
        SnakeRules.normal.startMoveTicks,
      );
    });

    test('shrinks by levelRampTicks per level and perTargetTicks per eat', () {
      const rules = SnakeRules.normal;
      expect(
        rules.moveTicksAt(2, 3),
        rules.startMoveTicks - rules.levelRampTicks - rules.perTargetTicks * 3,
      );
    });

    test('hits the floor and never goes under it', () {
      const rules = SnakeRules.normal;
      expect(rules.moveTicksAt(50, 50), rules.minMoveTicks);
      expect(
        rules.moveTicksAt(1000000, 1000000),
        greaterThanOrEqualTo(rules.minMoveTicks),
      );
    });
  });

  group('easy mode, by construction rather than by branch', () {
    test('shows fewer targets on the field than normal', () {
      expect(
        SnakeRules.easy.visibleTargets,
        lessThan(SnakeRules.normal.visibleTargets),
      );
      expect(SnakeRules.easy.visibleTargets, 2);
      expect(SnakeRules.normal.visibleTargets, 3);
    });

    test('wraps walls where normal does not', () {
      expect(SnakeRules.easy.wrapWalls, isTrue);
      expect(SnakeRules.normal.wrapWalls, isFalse);
    });
  });
}
