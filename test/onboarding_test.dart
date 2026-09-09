// test/onboarding_test.dart
// Tests de la persistencia del estado del tutorial (has_completed_onboarding).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adrialga_frontend/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PreferencesService — onboarding', () {
    test('Por defecto el tutorial NO está completado (false)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PreferencesService.getOnboardingDone(), isFalse);
    });

    test('Tras persistir true, la lectura devuelve true', () async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.setOnboardingDone(true);
      expect(await PreferencesService.getOnboardingDone(), isTrue);
    });

    test('Un valor persistido inválido/tipo no-bool degrada a false', () async {
      // Simula una clave corrupta (por ejemplo, un string en lugar de bool).
      SharedPreferences.setMockInitialValues({'has_completed_onboarding': 'si'});
      expect(await PreferencesService.getOnboardingDone(), isFalse);
    });

    test('resetOnboarding() vuelve a false (reactiva el tutorial)', () async {
      SharedPreferences.setMockInitialValues({});
      await PreferencesService.setOnboardingDone(true);
      await PreferencesService.resetOnboarding();
      expect(await PreferencesService.getOnboardingDone(), isFalse);
    });
  });
}