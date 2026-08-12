import 'package:flutter/material.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import 'core/ui/theme.dart';
import 'core/ui/tokens.dart';

/// The application root.
///
/// The themes are the phase 1 ones. The rest is still the phase 0 scaffold:
/// one placeholder screen and no router. A later phase 1 pull request replaces
/// [ScaffoldHomePage] with the real home screen and adds `onGenerateRoute`,
/// and takes the theme choice from the saved settings rather than always
/// following the system.
class GameStationApp extends StatelessWidget {
  const GameStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Station',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.day(),
      darkTheme: AppTheme.night(),
      home: const ScaffoldHomePage(),
    );
  }
}

/// Placeholder home screen, standing in until the phase 1 home screen lands.
///
/// It reads [generatorVersion] so that the app-to-engine path dependency is
/// exercised by running the app, not only by the analyzer.
class ScaffoldHomePage extends StatelessWidget {
  const ScaffoldHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Game Station',
                  style: theme.textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No ads. No network. No tracking.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Scaffold — puzzle engine v$generatorVersion',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
