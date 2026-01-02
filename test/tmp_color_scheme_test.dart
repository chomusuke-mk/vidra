import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('print color schemes', () {
    final light = ColorScheme.fromSeed(seedColor: Colors.blue);
    final dark = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    );
    debugPrint('LIGHT:${_describe(light)}');
    debugPrint('DARK:${_describe(dark)}');
  });
}

String _describe(ColorScheme scheme) {
  final entries = <String, int>{
    'primary': scheme.primary.toARGB32(),
    'onPrimary': scheme.onPrimary.toARGB32(),
    'primaryContainer': scheme.primaryContainer.toARGB32(),
    'onPrimaryContainer': scheme.onPrimaryContainer.toARGB32(),
    'secondary': scheme.secondary.toARGB32(),
    'onSecondary': scheme.onSecondary.toARGB32(),
    'surface': scheme.surface.toARGB32(),
    'onSurface': scheme.onSurface.toARGB32(),
    'surfaceVariant': scheme.surfaceContainerHighest.toARGB32(),
    'onSurfaceVariant': scheme.onSurfaceVariant.toARGB32(),
    'outline': scheme.outline.toARGB32(),
    'tertiary': scheme.tertiary.toARGB32(),
    'outlineVariant': scheme.outlineVariant.toARGB32(),
    'background': scheme.surface.toARGB32(),
    'onBackground': scheme.onSurface.toARGB32(),
  };
  return entries.entries
      .map((entry) => '${entry.key}=0x${entry.value.toRadixString(16)}')
      .join(',');
}
