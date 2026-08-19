// A fake for tests that assert *what* would have buzzed, not just that
// nothing crashed. `SilentHaptics` alone cannot answer that — it remembers
// nothing — so this wraps the same no-op behaviour with a log
// (`PLAN-phase-5.md` §4.5).

import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/save_data.dart';

/// One entry per call to [selectionClick], [lightImpact] or [mediumImpact],
/// in order, instead of a buzz. `haptics: false` in [applySettings] silences
/// it exactly as the real wrapper is silenced, so a test can assert an empty
/// log rather than reading the setting itself.
class RecordingHaptics implements AppHaptics {
  final List<String> calls = [];
  bool _haptics = true;

  @override
  void selectionClick() {
    if (_haptics) calls.add('selectionClick');
  }

  @override
  void lightImpact() {
    if (_haptics) calls.add('lightImpact');
  }

  @override
  void mediumImpact() {
    if (_haptics) calls.add('mediumImpact');
  }

  @override
  void applySettings(AppSettings settings) => _haptics = settings.haptics;
}
