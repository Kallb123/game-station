// A fake for tests that assert *what* would have buzzed, not just that
// nothing crashed. `SilentHaptics` alone cannot answer that — it remembers
// nothing — so this wraps the same no-op behaviour with a log
// (`PLAN-phase-5.md` §4.5).
//
// Records which event fired, not which underlying `HapticFeedback` call it
// became: that mapping moves with `AppSettings.hapticsLevel`
// (`core/haptics.dart`'s ladder), so a test asserting it needs the real
// `SystemHaptics` against a mocked platform channel — `core/haptics_test.dart`
// — rather than a fake that only pretends to be one.

import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/save_data.dart';

/// One entry per call to [tap], [mistake] or [impact], in order, instead of a
/// buzz. [HapticsLevel.off] in [applySettings] silences it exactly as the
/// real wrapper is silenced, so a test can assert an empty log rather than
/// reading the setting itself.
class RecordingHaptics implements AppHaptics {
  final List<String> calls = [];
  HapticsLevel _level = HapticsLevel.low;

  @override
  void tap() => _record('tap');

  @override
  void mistake() => _record('mistake');

  @override
  void impact() => _record('impact');

  void _record(String name) {
    if (_level != HapticsLevel.off) calls.add(name);
  }

  @override
  void applySettings(AppSettings settings) => _level = settings.hapticsLevel;
}
