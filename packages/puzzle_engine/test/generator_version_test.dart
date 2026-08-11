import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:test/test.dart';

void main() {
  test('generatorVersion is 1', () {
    // Not a tautology guard: this test exists so that bumping the version fails
    // here first, next to the comment in generator_version.dart listing what
    // else has to change in the same commit (goldens, the old generator behind
    // the switch, a save migration).
    expect(generatorVersion, 1);
  });
}
