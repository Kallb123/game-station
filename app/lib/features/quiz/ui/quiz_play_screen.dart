import 'package:flutter/material.dart';

import '../../../core/ui/screen_scaffold.dart';
import 'quiz_style.dart';

/// Which round to play: a mix of the shelf, or one title
/// (`PLAN-phase-10-quiz.md` §4.5).
///
/// A typed object for the reason `TracksPlayArgs` is: `arguments` is
/// `Object?`, and the route table checks the type rather than casting.
@immutable
class QuizPlayArgs {
  /// A round drawn from every ticked title.
  const QuizPlayArgs.mixed() : titleId = null;

  /// A round over the one title [titleId] names.
  const QuizPlayArgs.title(String this.titleId);

  /// The title to play, or null for a mixed round.
  final String? titleId;

  @override
  bool operator ==(Object other) =>
      other is QuizPlayArgs && other.titleId == titleId;

  @override
  int get hashCode => titleId.hashCode;
}

// Placeholder: replaced by the screen agents.
class QuizPlayScreen extends StatelessWidget {
  const QuizPlayScreen({required this.args, super.key});

  final QuizPlayArgs args;

  @override
  Widget build(BuildContext context) =>
      const ScreenScaffold(title: quizTitle, child: SizedBox.shrink());
}
