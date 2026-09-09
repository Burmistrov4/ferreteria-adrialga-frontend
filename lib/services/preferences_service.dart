import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia de preferencias de la app en [SharedPreferences].
///
/// Centraliza los flags de la interfaz para que el resto del código no dependa
/// de claves de SharedPreferences dispersas. Actualmente gestiona el estado del
/// onboarding/tutorial de primer uso.
class PreferencesService {
  PreferencesService._();

  static const String _keyOnboarding = 'has_completed_onboarding';

  /// Indica si el cajero ya completó (u omitió) el tutorial de primer uso.
  /// Un valor ausente se interpreta como `false` (aún no visto).
  static Future<bool> getOnboardingDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyOnboarding) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Fija el estado del tutorial (true = completado, false = pendiente).
  /// Al poner `false` se reactiva el onboarding en la siguiente apertura.
  static Future<void> setOnboardingDone(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOnboarding, value);
    } catch (_) {
      // Fallo de persistencia no bloquea la app: el tutorial simplemente
      // volvería a mostrarse la próxima vez.
    }
  }

  /// Reinicia el estado para que el tutorial vuelva a mostrarse.
  static Future<void> resetOnboarding() => setOnboardingDone(false);
}