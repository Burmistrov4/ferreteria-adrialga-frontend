import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de tema elegida por el usuario.
///
/// - [system]: sigue el brillo del sistema operativo.
/// - [light] / [dark]: modo forzado.
enum ThemeModePreference { system, light, dark }

/// Notificador global del tema claro / oscuro.
///
/// Usa [ChangeNotifier] para que Provider reconstruya el MaterialApp al
/// conmutar. La preferencia elegida se persiste en [SharedPreferences] para
/// que el modo (claro/oscuro/sistema) se conserve entre sesiones y en cada
/// inicio de la aplicación se restaure antes del primer frame (sin parpadeo).
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier._(this._preference, this._isDark);

  static const String _keyPreference = 'theme_mode_preference';

  ThemeModePreference _preference;
  bool _isDark;

  ThemeModePreference get preference => _preference;
  bool get isDark => _isDark;

  /// Restaura la preferencia persistida. Se invoca en `main()` antes de
  /// `runApp` para aplicar el tema correcto desde el primer frame.
  static Future<ThemeNotifier> create() async {
    var pref = ThemeModePreference.system;
    try {
      final prefs = await SharedPreferences.getInstance();
      pref = switch (prefs.getString(_keyPreference)) {
        'light' => ThemeModePreference.light,
        'dark' => ThemeModePreference.dark,
        _ => ThemeModePreference.system,
      };
    } catch (_) {
      // Sin acceso a preferencias → predeterminado "seguir sistema".
    }
    return ThemeNotifier._(pref, _efectivoPara(pref));
  }

  static bool _efectivoPara(ThemeModePreference pref) {
    switch (pref) {
      case ThemeModePreference.dark:
        return true;
      case ThemeModePreference.light:
        return false;
      case ThemeModePreference.system:
        final dispatch = WidgetsBinding.instance.platformDispatcher;
        return dispatch.platformBrightness == Brightness.dark;
    }
  }

  /// Conmuta entre claro y oscuro. Si la preferencia era "seguir sistema",
  /// se hace explícita con el valor resultante.
  void toggle() {
    _aplicarYPersistir(!_isDark
        ? ThemeModePreference.dark
        : ThemeModePreference.light);
  }

  /// Fija un modo explícito (claro / oscuro).
  void setDark(bool value) {
    _aplicarYPersistir(
        value ? ThemeModePreference.dark : ThemeModePreference.light);
  }

  /// Cambia la preferencia de tema (seguir sistema, claro u oscuro).
  void setPreference(ThemeModePreference mode) {
    _aplicarYPersistir(mode);
  }

  void _aplicarYPersistir(ThemeModePreference modo) {
    final nuevo = _efectivoPara(modo);
    _preference = modo;
    if (_isDark != nuevo) {
      _isDark = nuevo;
      notifyListeners();
    } else {
      notifyListeners();
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_keyPreference, _preference.name);
    }).catchError((_) {});
  }

  ThemeData get theme => _isDark ? _darkTheme : _lightTheme;
static final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    cardColor: const Color(0xFF1E293B),
    dividerColor: const Color(0xFF334155),
    canvasColor: const Color(0xFF0F172A),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF3B82F6),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1D4ED8),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF10B981),
      onSecondary: Color(0xFF062B1D),
      error: Color(0xFFEF4444),
      onError: Colors.white,
      surface: Color(0xFF1E293B),
      onSurface: Color(0xFFE2E8F0),
      onSurfaceVariant: Color(0xFFCBD5E1),
      outline: Color(0xFF64748B),
      outlineVariant: Color(0xFF334155),
      surfaceContainerLowest: Color(0xFF0B1220),
      surfaceContainerLow: Color(0xFF1E293B),
      surfaceContainer: Color(0xFF263345),
      surfaceContainerHigh: Color(0xFF2E3D52),
      surfaceContainerHighest: Color(0xFF37495F),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F172A),
      elevation: 0,
      foregroundColor: Color(0xFFF8FAFC),
      titleTextStyle: TextStyle(
        color: Color(0xFFF8FAFC),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF1E293B),
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E293B)),
    drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF0F172A)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E293B),
    ),
    hintColor: const Color(0xFFCBD5E1),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Color(0xFFF8FAFC)),
      displayMedium: TextStyle(color: Color(0xFFF8FAFC)),
      displaySmall: TextStyle(color: Color(0xFFF8FAFC)),
      headlineMedium: TextStyle(color: Color(0xFFF8FAFC)),
      headlineSmall: TextStyle(color: Color(0xFFF8FAFC)),
      titleLarge: TextStyle(color: Color(0xFFF8FAFC)),
      titleMedium: TextStyle(color: Color(0xFFF1F5F9)),
      titleSmall: TextStyle(color: Color(0xFFE2E8F0)),
      bodyLarge: TextStyle(color: Color(0xFFF1F5F9)),
      bodyMedium: TextStyle(color: Color(0xFFE2E8F0)),
      bodySmall: TextStyle(color: Color(0xFFB0BED0)),
      labelLarge: TextStyle(color: Color(0xFFE2E8F0)),
      labelMedium: TextStyle(color: Color(0xFFCBD5E1)),
      labelSmall: TextStyle(color: Color(0xFF94A3B8)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF263345),
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
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
      filled: true,
      fillColor: const Color(0xFF16213A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Color(0xFFE2E8F0),
      iconColor: Color(0xFFCBD5E1),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF3B82F6)
            : const Color(0xFF64748B),
      ),
    ),
  );
static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE2E8F0),
    canvasColor: const Color(0xFFF8FAFC),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF3B82F6),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: Color(0xFF10B981),
      onSecondary: Colors.white,
      error: Color(0xFFEF4444),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1E293B),
      onSurfaceVariant: Color(0xFF475569),
      outline: Color(0xFF94A3B8),
      outlineVariant: Color(0xFFE2E8F0),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFF1F5F9),
      surfaceContainer: Color(0xFFF8FAFC),
      surfaceContainerHigh: Color(0xFFE2E8F0),
      surfaceContainerHighest: Color(0xFFD3DCE6),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      foregroundColor: Color(0xFF0F172A),
      titleTextStyle: TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFFF8FAFC)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
    ),
    hintColor: const Color(0xFF94A3B8),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: Color(0xFF0F172A)),
      displayMedium: TextStyle(color: Color(0xFF0F172A)),
      displaySmall: TextStyle(color: Color(0xFF0F172A)),
      headlineMedium: TextStyle(color: Color(0xFF0F172A)),
      headlineSmall: TextStyle(color: Color(0xFF0F172A)),
      titleLarge: TextStyle(color: Color(0xFF0F172A)),
      titleMedium: TextStyle(color: Color(0xFF1E293B)),
      titleSmall: TextStyle(color: Color(0xFF334155)),
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF334155)),
      bodySmall: TextStyle(color: Color(0xFF64748B)),
      labelLarge: TextStyle(color: Color(0xFF1E293B)),
      labelMedium: TextStyle(color: Color(0xFF475569)),
      labelSmall: TextStyle(color: Color(0xFF64748B)),
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
              : const Color(0xFF475569),
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
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      labelStyle: const TextStyle(color: Color(0xFF475569)),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Color(0xFF1E293B),
      iconColor: Color(0xFF475569),
    ),
  );
}