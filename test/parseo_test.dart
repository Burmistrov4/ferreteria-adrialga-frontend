// test/parseo_test.dart
// Tests del parseo seguro de Decimals de Prisma (regla de manejo de datos).
import 'package:flutter_test/flutter_test.dart';

import 'package:adrialga_frontend/utils/parseo.dart';

void main() {
  group('numD — parseo seguro de Decimals', () {
    test('Parsea strings decimales de Prisma ("12.3400")', () {
      expect(numD('12.3400'), closeTo(12.34, 0.001));
    });

    test('Parsea numéricos nativos', () {
      expect(numD(7), closeTo(7.0, 0.001));
      expect(numD(3.15), closeTo(3.15, 0.001));
    });

    test('Parsea negativos y decimales con signo', () {
      expect(numD('-45.5'), closeTo(-45.5, 0.001));
    });

    test('null → 0.0 (nunca excepción)', () {
      expect(numD(null), 0.0);
    });

    test('String no numérico → 0.0 (nunca excepción)', () {
      expect(numD('abc'), 0.0);
      expect(numD(''), 0.0);
    });

    test('Objetos arbitrarios (Decimal serializado) → 0.0 sin crash', () {
      expect(numD({'raro': true}), 0.0);
    });

    test('Los montos del arqueo redondean a 2 decimales de forma estable', () {
      final saldo = numD('125.4999');
      expect(saldo.toStringAsFixed(2), '125.50');
    });
  });
}