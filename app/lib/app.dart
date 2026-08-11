import 'package:flutter/material.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

/// Placeholder seed colour, until the phase 1 design tokens replace it.
const Color _seedColor = Color(0xFF3F6FD8);

/// The application root.
///
/// Phase 0 scaffold: one placeholder screen, no router and no design tokens.
/// Phase 1 replaces [ScaffoldHomePage] with the real home screen and moves
/// theming into `core/ui/`.
class GameStationApp extends StatelessWidget {
  const GameStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Station',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seedColor, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
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
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Game Station',
                  style: theme.textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'No ads. No network. No tracking.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
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
