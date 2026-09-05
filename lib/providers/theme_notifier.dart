import 'package:flutter/material.dart';

/// Notificador global del tema claro / oscuro.
/// Usa [ChangeNotifier] para que Provider reconstruya el MaterialApp al conmutar.
class ThemeNotifier extends ChangeNotifier {
  bool _isDark = true;

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setDark(bool value) {
    if (_isDark != value) {
      _isDark = value;
      notifyListeners();
    }
  }

  ThemeData get theme => _isDark ? _darkTheme : _lightTheme;

  static final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    cardColor: const Color(0xFF1E293B),
    dividerColor: const Color(0xFF334155),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF10B981),
      error: Color(0xFFEF4444),
      surface: Color(0xFF1E293B),
      onSurface: Color(0xFFE2E8F0),
      onPrimary: Colors.white,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F172A),
      elevation: 0,
    ),
    cardTheme: const CardThemeData(color: Color(0xFF1E293B)),
    dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E293B)),
    drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF0F172A)),
    hintColor: const Color(0xFFCBD5E1),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFF1F5F9)),
      bodyMedium: TextStyle(color: Color(0xFFE2E8F0)),
      bodySmall: TextStyle(color: Color(0xFFB0BED0)),
      titleLarge: TextStyle(color: Color(0xFFF8FAFC)),
      titleMedium: TextStyle(color: Color(0xFFF1F5F9)),
      titleSmall: TextStyle(color: Color(0xFFE2E8F0)),
      labelMedium: TextStyle(color: Color(0xFFCBD5E1)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF1E293B),
      selectedColor: const Color(0xFF3B82F6),
      secondarySelectedColor: const Color(0xFF3B82F6),
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: Color(0xFFE2E8F0)),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      side: const BorderSide(color: Color(0xFF334155)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFFCBD5E1),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF3B82F6)
              : const Color(0xFF1E293B),
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: Color(0xFF475569)),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
      labelStyle: TextStyle(color: Color(0xFFCBD5E1)),
    ),
  );

  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE2E8F0),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF10B981),
      error: Color(0xFFEF4444),
      surface: Colors.white,
      onSurface: Color(0xFF1E293B),
      onPrimary: Colors.white,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      foregroundColor: Color(0xFF1E293B),
    ),
    cardTheme: const CardThemeData(color: Colors.white),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFFF8FAFC)),
    hintColor: const Color(0xFF94A3B8),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF334155)),
      bodySmall: TextStyle(color: Color(0xFF64748B)),
      titleLarge: TextStyle(color: Color(0xFF0F172A)),
      titleMedium: TextStyle(color: Color(0xFF1E293B)),
      titleSmall: TextStyle(color: Color(0xFF334155)),
      labelMedium: TextStyle(color: Color(0xFF64748B)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF3B82F6),
      secondarySelectedColor: const Color(0xFF3B82F6),
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: Color(0xFF334155)),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFF64748B),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF3B82F6)
              : Colors.white,
        ),
        side: WidgetStateProperty.all(
          const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: Color(0xFF94A3B8)),
      labelStyle: TextStyle(color: Color(0xFF64748B)),
    ),
  );
}

