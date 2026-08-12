import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/providers.dart';
import 'core/storage/save_data.dart';
import 'core/ui/theme.dart';
import 'features/home/home_screen.dart';
import 'features/placeholders/coming_soon_screen.dart';
import 'features/profiles/profile_screen.dart';
import 'features/settings/settings_screen.dart';
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
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Game Station',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.day(),
      darkTheme: AppTheme.night(),
      themeMode: switch (settings.theme) {
        ThemeChoice.day => ThemeMode.light,
        ThemeChoice.night => ThemeMode.dark,
        ThemeChoice.system => ThemeMode.system,
      },
      initialRoute: AppRoutes.home,
      onGenerateRoute: _generateRoute,
      builder: (context, child) =>
          _ReducedMotion(stored: settings.reduceMotion, child: child!),
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

/// Adds the app's own reduced-motion setting to the device's.
///
/// PLAN-phase-1.md §4.1 asks for the **or** of the stored setting and
/// `MediaQuery.disableAnimations`. That or lives in what the widgets below read
/// rather than in a branch here, because only one of the two halves needs
/// anything doing:
///
/// - The device's half is already in the ambient `MediaQuery`, and Flutter
///   already acts on it: an `AnimationController` cuts its duration to a
///   twentieth when the platform asks for less motion. A child whose tablet is
///   set that way needs nothing from this app's switch.
/// - The stored half is what this adds, into the same `MediaQuery` flag — so a
///   phase-4 animation asks `MediaQuery.disableAnimationsOf(context)` once and
///   has the whole answer, instead of reading a setting and a platform flag and
///   remembering to or them.
///
/// It also takes the only animation phase 1 has — the slide from one screen to
/// the next — off the table, so the setting does something on the day it ships
/// rather than in phase 4.
class _ReducedMotion extends StatelessWidget {
  const _ReducedMotion({required this.stored, required this.child});

  /// The stored half of the decision, from the settings.
  final bool stored;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!stored) return child;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(pageTransitionsTheme: _instantTransitions),
        child: child,
      ),
    );
  }
}

/// Screens that change without moving, on every platform.
///
/// Every target rather than the current one: the map is a fallback table, and a
/// platform missing from it keeps its sliding transition, which is the bug this
/// exists to prevent.
final PageTransitionsTheme _instantTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    for (final platform in TargetPlatform.values)
      platform: const _NoPageTransition(),
  },
);

/// A page transition that does not transition.
class _NoPageTransition extends PageTransitionsBuilder {
  const _NoPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
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
/// `/sudoku` and `/arcade` are placeholders until phases 3 and 4; the route
/// names are already the ones those screens will answer to, so wiring them is a
/// one-line change there rather than a change here as well.
WidgetBuilder? _screenFor(String? name) => switch (name) {
  AppRoutes.home => (context) => const HomeScreen(),
  AppRoutes.profiles => (context) => const ProfileScreen(),
  AppRoutes.settings => (context) => const SettingsScreen(),
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
