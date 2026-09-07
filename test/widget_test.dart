// test/widget_test.dart
// Tests de widgets esenciales de Adrialga (persistencia de tema y parseo).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adrialga_frontend/providers/theme_notifier.dart';
import 'package:adrialga_frontend/utils/parseo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adrialga — lógica esencial', () {
    test('Persistencia: tema se restaura desde SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'theme_mode_preference': 'dark'});
      final notifier = await ThemeNotifier.create();
      expect(notifier.preference, ThemeModePreference.dark);
    });

    test('Parseo seguro: maneja Decimals de Prisma sin excepciones', () {
      expect(numD('12.3400'), closeTo(12.34, 0.001));
      expect(numD(null), 0.0);
      expect(numD('abc'), 0.0);
    });
  });
}
