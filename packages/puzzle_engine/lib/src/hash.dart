import 'dart:convert';

import 'uint32.dart';

/// FNV-1a, 32-bit, over the UTF-8 bytes of [input].
///
/// This is what turns a puzzle ID into a seed (`PLAN.md` §3.2), so it is frozen
/// for the same reason `Rng` is: the ID is what a save file stores, and a
/// different hash is a different puzzle behind the same name.
///
/// Puzzle IDs are ASCII by construction, so the UTF-8 bytes and the UTF-16 code
/// units of an ID coincide; `test/hash_test.dart` asserts that for every ID
/// shape, so the distinction cannot quietly begin to matter. UTF-8 is the
/// definition regardless, because it is the one that does not depend on how
/// Dart happens to represent a string.
///
/// Not exported from `puzzle_engine.dart` — see `rng.dart` for why.
int fnv1a32(String input) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(input)) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash;
}
