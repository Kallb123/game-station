// `sequenceForLevel`'s table (`PLAN-phase-7-snake.md` §4.3): the sequence a
// counting run asks the player to eat, level by level.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/snake/model/counting.dart';

void main() {
  group('ones', () {
    test('runs 1..10 then 11..20', () {
      expect(
        sequenceForLevel(SnakeCounting.ones, 1, 10),
        List<int>.generate(10, (i) => i + 1),
      );
      expect(
        sequenceForLevel(SnakeCounting.ones, 2, 10),
        List<int>.generate(10, (i) => i + 11),
      );
    });

    test('level n runs 10(n-1)+1 .. 10n', () {
      expect(
        sequenceForLevel(SnakeCounting.ones, 5, 10),
        List<int>.generate(10, (i) => 41 + i),
      );
    });
  });

  group('twos', () {
    test('runs 2..20 then 22..40', () {
      expect(
        sequenceForLevel(SnakeCounting.twos, 1, 10),
        List<int>.generate(10, (i) => (i + 1) * 2),
      );
      expect(
        sequenceForLevel(SnakeCounting.twos, 2, 10),
        List<int>.generate(10, (i) => 22 + i * 2),
      );
    });

    test('level n runs 20(n-1)+2 .. 20n', () {
      expect(
        sequenceForLevel(SnakeCounting.twos, 3, 10),
        List<int>.generate(10, (i) => 42 + i * 2),
      );
    });
  });
}
