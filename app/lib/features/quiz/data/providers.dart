import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/quiz_catalog.dart';

/// The question bank, loaded once at start-up (`main.dart`).
///
/// Defaults to an empty catalog rather than throwing, as `saveStoreProvider`
/// does: a missing catalog is a valid state (a failed load yields one, and the
/// Quiz card then simply does not appear), and defaulting means every test that
/// builds its own scope without a quiz sees no quiz and needs no change.
final Provider<QuizCatalog> quizCatalogProvider = Provider<QuizCatalog>(
  (ref) => QuizCatalog.empty(),
);
