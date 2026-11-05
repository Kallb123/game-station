// Reads the quiz bank out of the asset bundle into a [QuizCatalog].
//
// The only part of the catalog that needs Flutter (`PLAN-phase-10-quiz.md`
// §4.2, §5); parsing and validation are the pure-Dart `parseQuizPack`, so the
// content test and this loader apply the same rules.
//
// `load` never throws. `AGENTS.md`: never surface an internal error to a
// child, and a boot loop over a bad pack is worse than a missing shelf. A
// broken pack is logged with `debugPrint` and skipped, and the content test is
// what makes that a CI failure long before a device sees it.
//
// Not wired into app start-up here: that, and the providers, are PR 6's.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/quiz_catalog.dart';
import '../model/quiz_pack.dart';

/// Loads the bank once; construct with a fake [AssetBundle] in tests.
class QuizCatalogLoader {
  /// Creates a loader. [bundle] defaults to [rootBundle]; [checkedOnly]
  /// defaults to [kReleaseMode], so release builds drop unchecked questions
  /// and debug builds keep drafts for play-testing (§4.2).
  QuizCatalogLoader({AssetBundle? bundle, bool? checkedOnly})
    : _bundle = bundle ?? rootBundle,
      _checkedOnly = checkedOnly ?? kReleaseMode;

  final AssetBundle _bundle;
  final bool _checkedOnly;

  /// The catalog: store series first, then private, each in index order.
  ///
  /// Never throws; whatever cannot be read is left out.
  Future<QuizCatalog> load() async {
    try {
      final series = <QuizSeries>[];
      final withdrawn = <String>{};
      final seenSeries = <String>{};

      for (final audience in QuizAudience.values) {
        final index = await _loadIndex(audience);
        if (index == null) continue;
        withdrawn.addAll(index.withdrawnTitles);
        for (final id in index.series) {
          final pack = await _loadPack(audience, id);
          if (pack == null) continue;
          // A series in both directories would put its titles on the shelf
          // twice; store wins. Title ids need no check of their own, because
          // the parser holds each to its series' prefix.
          if (!seenSeries.add(pack.id)) {
            debugPrint(
              'Quiz: skipped ${audience.name}/$id.json: duplicate series',
            );
            continue;
          }
          series.add(pack);
        }
      }

      final catalog = QuizCatalog(series: series, withdrawnTitles: withdrawn);
      return _checkedOnly ? catalog.withCheckedOnly() : catalog;
    } catch (e) {
      debugPrint('Quiz: catalog load failed: $e');
      return QuizCatalog.empty();
    }
  }

  Future<QuizIndex?> _loadIndex(QuizAudience audience) async {
    final path = 'assets/quiz/${audience.name}/index.json';
    final String text;
    try {
      text = await _bundle.loadString(path);
    } catch (e) {
      // A store build has no private directory at all; that is normal, not
      // news (§4.9).
      if (audience == QuizAudience.store) {
        debugPrint('Quiz: could not read $path: $e');
      }
      return null;
    }
    try {
      return parseQuizIndex(text);
    } on QuizFormatException catch (e) {
      debugPrint('Quiz: skipped $path: ${e.problems.join('; ')}');
      return null;
    }
  }

  Future<QuizSeries?> _loadPack(QuizAudience audience, String id) async {
    final path = 'assets/quiz/${audience.name}/$id.json';
    try {
      final text = await _bundle.loadString(path);
      return parseQuizPack(text, seriesId: id, audience: audience);
    } on QuizFormatException catch (e) {
      debugPrint('Quiz: skipped $path: ${e.problems.join('; ')}');
    } catch (e) {
      debugPrint('Quiz: could not read $path: $e');
    }
    return null;
  }
}
