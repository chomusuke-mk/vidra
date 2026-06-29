// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // Tema Claro
  static ThemeData get lightTheme {
    return ThemeData.light().copyWith(
      primaryColor: Colors.blue,
      scaffoldBackgroundColor: Colors.white,
      // Define aquí tus colores, tipografías, estilos de botones, etc.
    );
  }

  // Tema Oscuro
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      primaryColor: Colors.blueGrey,
      scaffoldBackgroundColor: const Color(0xFF121212),
      // Configuraciones para el modo oscuro...
    );
  }
}
