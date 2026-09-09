// test/cobro_engine_test.dart
// Tests unitarios del motor de cobro (IVA, IGTF, cambio, casos limite).
// Ejecutar con: flutter test test/cobro_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:adrialga_frontend/utils/cobro_engine.dart';
import 'package:adrialga_frontend/utils/parseo.dart';

void main() {
  const double epsilon = 0.0001;
  const double tasa = 36.50;

  // ── calcularSubtotal ─────────────────────────────────────────────────────

  group('calcularSubtotal', () {
    test('carrito vacio devuelve 0', () {
      expect(calcularSubtotal([]), equals(0.0));
    });

    test('un item: 3 x 10.00 = 30.00', () {
      expect(
        calcularSubtotal([{'precio': 10.0, 'cantidad': 3}]),
        closeTo(30.0, epsilon),
      );
    });

    test('multiples items se suman correctamente', () {
      final items = [
        {'precio': 5.0, 'cantidad': 2},   // 10.00
        {'precio': 3.50, 'cantidad': 4},  // 14.00
        {'precio': 1.25, 'cantidad': 1},  // 1.25
      ];
      expect(calcularSubtotal(items), closeTo(25.25, epsilon));
    });

    test('valores nulos o ausentes no lanzan excepcion', () {
      final items = [
        {'precio': null, 'cantidad': 2},
        {'precio': 5.0, 'cantidad': null},
      ];
      expect(calcularSubtotal(items), closeTo(0.0, epsilon));
    });
  });

  // ── calcularCobro — IVA y totales ─────────────────────────────────────────

  group('calcularCobro — IVA', () {
    test('IVA 16% se aplica sobre el subtotal', () {
      final r = calcularCobro(subtotal: 100.0, tasa: tasa);
      expect(r.iva, closeTo(16.0, epsilon));
    });

    test('totalUSD = subtotal + IVA', () {
      final r = calcularCobro(subtotal: 100.0, tasa: tasa);
      expect(r.totalUSD, closeTo(116.0, epsilon));
    });

    test('totalVES = totalUSD x tasa', () {
      final r = calcularCobro(subtotal: 100.0, tasa: tasa);
      expect(r.totalVES, closeTo(116.0 * tasa, epsilon));
    });

    test('subtotal cero devuelve todos los montos en cero', () {
      final r = calcularCobro(subtotal: 0.0, tasa: tasa);
      expect(r.totalUSD, closeTo(0.0, epsilon));
      expect(r.iva, closeTo(0.0, epsilon));
    });
  });

  // ── calcularCobro — IGTF ─────────────────────────────────────────────────

  group('calcularCobro — IGTF', () {
    test('sin divisas: IGTF es 0', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoBs: 100.0 * 1.16 * tasa,
      );
      expect(r.igtfUSD, closeTo(0.0, epsilon));
      expect(r.cargoTotalUSD, closeTo(116.0, epsilon));
    });

    test('pago exacto en USD: IGTF = 3% del efectivoUSD', () {
      // Total = 116 USD; cliente paga exacto en USD.
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 116.0,
      );
      expect(r.igtfUSD, closeTo(116.0 * 0.03, epsilon));
      expect(r.cargoTotalUSD, closeTo(116.0 + 116.0 * 0.03, epsilon));
    });

    test('IGTF en VES = igtfUSD x tasa', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 116.0,
      );
      expect(r.igtfVES, closeTo(r.igtfUSD * tasa, epsilon));
    });
  });

  // ── calcularCobro — vuelto y diferencia ──────────────────────────────────

  group('calcularCobro — vuelto y diferencia', () {
    test('pago exacto en USD: vuelto 0, pagoCompleto true', () {
      // El IGTF se aplica sobre el USD realmente entregado, por lo que el pago
      // "exacto" en divisas satisface: efectivoUSD = cargoTotalUSD.
      // cargoTotalUSD = totalUSD + 0.03*efectivoUSD  =>  efectivoUSD = totalUSD / 0.97.
      final totalUSD = 100.0 * 1.16; // 116 USD (subtotal + IVA)
      final efectivoUSD = totalUSD / 0.97;
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: efectivoUSD,
      );
      expect(r.pagoCompleto, isTrue);
      expect(r.vueltoUSD, closeTo(0.0, epsilon));
    });

    test('cliente paga de mas: vuelto correcto', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 150.0, // sobrepaga
      );
      expect(r.pagoCompleto, isTrue);
      expect(r.vueltoUSD, greaterThan(0.0));
      expect(r.vueltoVES, greaterThan(0.0));
      expect(r.vueltoVES, closeTo(r.vueltoUSD * tasa, epsilon));
    });

    test('pago insuficiente: pagoCompleto false, vuelto 0', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 10.0, // insuficiente
      );
      expect(r.pagoCompleto, isFalse);
      expect(r.vueltoUSD, closeTo(0.0, epsilon));
      expect(r.vueltoVES, closeTo(0.0, epsilon));
    });

    test('deficit de exactamente 1 centavo: aun es pagoCompleto (tolerancia)', () {
      final cargo = calcularCobro(subtotal: 100.0, tasa: tasa).totalUSD; // sin IGTF (sin USD)
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoBs: (cargo - 0.009) * tasa, // falta 0.009 < tolerancia 0.01
      );
      expect(r.pagoCompleto, isTrue);
    });

    test('pago multipago: mitad USD + mitad Bs', () {
      final total = 100.0 * 1.16; // 116 USD
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: total / 2,        // 58 USD
        efectivoBs: (total / 2) * tasa, // 58 USD en Bs equivalentes
      );
      // IGTF aplica solo sobre los 58 USD
      expect(r.igtfUSD, closeTo(58.0 * 0.03, epsilon));
      // pagoCompleto depende de si el total recibido cubre cargoTotal
      // Si cubre: true
      expect(r.totalRecibidoUSD, closeTo(116.0, epsilon));
    });
  });

  // ── Casos limite extremos ─────────────────────────────────────────────────

  group('Casos limite', () {
    test('tasa muy alta (hiperinflacion): no overflow', () {
      final r = calcularCobro(
        subtotal: 1000.0,
        tasa: 999999.0,
        efectivoUSD: 1000.0 * 1.16 * 1.03,
      );
      expect(r.totalVES.isFinite, isTrue);
      expect(r.diferenciaVES.abs().isFinite, isTrue);
    });

    test('subtotal con muchos decimales: redondeo estable', () {
      // 3 items de 1/3 = 1.0 exacto
      final items = [
        {'precio': 1 / 3, 'cantidad': 3},
      ];
      final sub = calcularSubtotal(items);
      expect(sub, closeTo(1.0, epsilon));
    });
  });

  // ── Integración: parseo seguro de Decimals (Prisma) → motor de cobro ──────

  group('Integración parseo seguro → cobro', () {
    test('cargo expresado en Bs (Decimal string) alimenta totalVES', () {
      // El backend envía tasa y montos como cadenas decimales "36.5000".
      final tasaD = numD('36.5000');
      final subtotalD = numD('100.0000');
      final r = calcularCobro(subtotal: subtotalD, tasa: tasaD);
      expect(r.totalVES, closeTo(116.0 * tasaD, epsilon));
    });

    test('pago de mas exclusivamente en Bs: vueltoVES es correcto en Bs', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 0.0,
        efectivoBs: 116.0 * tasa + (3.0 * tasa), // sobrepaga 3 USD en Bs
      );
      expect(r.pagoCompleto, isTrue);
      expect(r.vueltoUSD, closeTo(3.0, epsilon));
      expect(r.vueltoVES, closeTo(3.0 * tasa, epsilon));
    });

    test('totalRecibidoUSD combina USD + Bs convertidos a su equivalencia', () {
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoUSD: 58.0,
        efectivoBs: 58.0 * tasa,
      );
      expect(r.totalRecibidoUSD, closeTo(116.0, epsilon));
    });

    test('montos mal formateados ("---", "") degradan a 0 y no rompen el motor', () {
      final tasaD = numD('36.50');
      final r = calcularCobro(
        subtotal: numD('abc'),
        tasa: tasaD,
        efectivoUSD: numD('---'),
        efectivoBs: numD(''),
      );
      expect(r.totalUSD, closeTo(0.0, epsilon));
      expect(r.pagoCompleto, isTrue);
    });
  });
}
