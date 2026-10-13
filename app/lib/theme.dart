import 'package:flutter/material.dart';

import 'scan/report.dart';

const _seed = Color(0xFF2E7D6B);

ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
  );
}

/// Colour + icon for each finding severity.
({Color color, IconData icon, String label}) levelStyle(Level level, ColorScheme scheme) {
  return switch (level) {
    Level.ok => (color: const Color(0xFF2E7D32), icon: Icons.check_circle, label: 'OK'),
    Level.warn => (color: const Color(0xFFE09400), icon: Icons.warning_rounded, label: 'Heads up'),
    Level.problem => (color: scheme.error, icon: Icons.error_rounded, label: 'Problem'),
    Level.info => (color: scheme.outline, icon: Icons.info_rounded, label: 'Info'),
  };
}

/// Colour for a cause likelihood (1..5).
Color likelihoodColor(int likelihood, ColorScheme scheme) => switch (likelihood) {
      5 => const Color(0xFFC62828),
      4 => const Color(0xFFE09400),
      3 => scheme.primary,
      _ => scheme.outline,
    };
