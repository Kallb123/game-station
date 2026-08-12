import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/providers.dart';
import 'core/ui/theme.dart';
import 'features/home/home_screen.dart';
import 'features/placeholders/coming_soon_screen.dart';
import 'features/profiles/profile_screen.dart';
import 'routes.dart';

/// The application root.
///
/// A `Navigator` with an `onGenerateRoute` table rather than `go_router`
/// (PLAN-phase-1.md §3): the value of a routing package is deep linking and
/// browser URL sync, and an offline app with five screens gets neither.
///
/// It is stateful only to hold the [AppLifecycleListener] that flushes pending
/// writes when the app goes away. Without it, the last 500 ms of changes — the
/// debounce window in `progress_repository.dart` — die with the process.
class GameStationApp extends ConsumerStatefulWidget {
  const GameStationApp({super.key});

  @override
  ConsumerState<GameStationApp> createState() => _GameStationAppState();
}

class _GameStationAppState extends ConsumerState<GameStationApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // `paused` is the last callback Android and iOS guarantee before a
      // process can be killed, and `detached` covers the desktop window closing
      // without an exit request.
      onPause: _flush,
      onDetach: _flush,
      onExitRequested: _flushThenExit,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Station',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.day(),
      darkTheme: AppTheme.night(),
      initialRoute: AppRoutes.home,
      onGenerateRoute: _generateRoute,
    );
  }

  /// Fire and forget: the platform is not waiting for us here, and a write that
  /// fails is recorded on the repository rather than thrown
  /// (`progress_repository.dart`).
  void _flush() => unawaited(ref.read(progressRepositoryProvider).flush());

  /// Desktop asks before it closes, so here the write can actually be waited
  /// for. [ProgressRepository.flush] never throws, so the answer is always
  /// "yes, exit" — refusing to close an app a parent is trying to shut down
  /// because a save failed would be worse than losing the save.
  Future<AppExitResponse> _flushThenExit() async {
    await ref.read(progressRepositoryProvider).flush();
    return AppExitResponse.exit;
  }
}

/// Builds the route for [settings], falling back to home for a name no screen
/// is registered under.
///
/// The assert is the real handling: an unknown name can only come from a typo
/// in this repository, because nothing outside the app can name a route. It
/// fails loudly in debug and in tests, and in release it puts the child on the
/// home screen instead of on a grey error page.
Route<void> _generateRoute(RouteSettings settings) {
  final screen = _screenFor(settings.name);
  assert(screen != null, 'no screen is registered for route ${settings.name}');

  return MaterialPageRoute<void>(
    builder: screen ?? (context) => const HomeScreen(),
    settings: settings,
  );
}

/// The screen behind each route name, or null for a name with no screen.
///
/// `/settings` is a placeholder until the next pull request fills it in; the
/// route name is already the one that screen will answer to, so wiring it is a
/// one-line change there rather than a change here as well.
WidgetBuilder? _screenFor(String? name) => switch (name) {
  AppRoutes.home => (context) => const HomeScreen(),
  AppRoutes.profiles => (context) => const ProfileScreen(),
  AppRoutes.settings => (context) => const ComingSoonScreen(
    title: 'Settings',
    icon: Icons.settings,
  ),
  AppRoutes.sudoku => (context) => const ComingSoonScreen(
    title: 'Sudoku',
    icon: homeSudokuIcon,
  ),
  AppRoutes.arcade => (context) => const ComingSoonScreen(
    title: 'Arcade',
    icon: homeArcadeIcon,
  ),
  _ => null,
};
