// test/theme_notifier_test.dart
// Tests de la persistencia del tema (claro/oscuro/sistema).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adrialga_frontend/providers/theme_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Por defecto sigue al sistema (modo sistema)', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = await ThemeNotifier.create();
    expect(notifier.preference, ThemeModePreference.system);
  });

  test('Restaura el modo oscuro persistido de la sesión anterior', () async {
    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'dark'});
    final notifier = await ThemeNotifier.create();
    expect(notifier.preference, ThemeModePreference.dark);
    expect(notifier.isDark, isTrue);
  });

  test('Restaura el modo claro persistido de la sesión anterior', () async {
    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'light'});
    final notifier = await ThemeNotifier.create();
    expect(notifier.preference, ThemeModePreference.light);
    expect(notifier.isDark, isFalse);
  });

  test('Un valor corrupto/persistido inválido degrada a "sistema"', () async {
    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'xyz'});
    final notifier = await ThemeNotifier.create();
    expect(notifier.preference, ThemeModePreference.system);
  });

  test('setPreference(dark) notifica y persiste la elección', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = await ThemeNotifier.create();
    var notificado = false;
    notifier.addListener(() => notificado = true);

    notifier.setPreference(ThemeModePreference.dark);
    expect(notifier.preference, ThemeModePreference.dark);
    expect(notifier.isDark, isTrue);
    expect(notificado, isTrue);

    // La persistencia es asíncrona (fire-and-forget): esperar el microtask.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode_preference'), 'dark');
  });

  test('toggle() conmuta el brillo efectivo', () async {
    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'light'});
    final notifier = await ThemeNotifier.create();
    final antes = notifier.isDark;
    notifier.toggle();
    expect(notifier.isDark, !antes);
  });

  test('Los temas generados tienen el brillo correcto', () async {
    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'dark'});
    final oscuro = await ThemeNotifier.create();
    expect(oscuro.theme.brightness, Brightness.dark);

    SharedPreferences.setMockInitialValues({'theme_mode_preference': 'light'});
    final claro = await ThemeNotifier.create();
    expect(claro.theme.brightness, Brightness.light);
  });
}