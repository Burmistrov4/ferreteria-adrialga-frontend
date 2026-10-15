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

    test('deficit sub-centavo (<=0.005): aun es pagoCompleto (tolerancia ajustada)', () {
      final cargo = calcularCobro(subtotal: 100.0, tasa: tasa).totalUSD; // sin IGTF (sin USD)
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoBs: (cargo - 0.004) * tasa, // falta 0.004 <= tolerancia 0.005
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

  // ── Céntimos fantasma: redondeo a centavos y tolerancia calibrada ────────

  group('Precisión de centavos (céntimo fantasma)', () {
    test('redondearCentavos normaliza residuos de coma flotante', () {
      expect(redondearCentavos(0.40000000000000036), equals(0.40));
      expect(redondearCentavos(0.40), equals(0.40));
      // El redondeo es determinista sobre el valor real guardado (no sobre
      // el "label" matemático imposible: 1.005 en realidad equivale a
      // 1.004999… en IEEE754, y truncar a centavos debe reflejarlo).
      expect(redondearCentavos(redondearCentavos(123.4567)),
          equals(redondearCentavos(123.46)));
    });

    test('deficit de medio centavo tras división por tasa compleja: tolerado', () {
      const tasaRara = 329.33;
      final cargoUSD = 0.40;
      final r = calcularCobro(
        subtotal: cargoUSD / 1.16,
        tasa: tasaRara,
        efectivoBs: redondearCentavos(cargoUSD * tasaRara),
      );
      expect(r.pagoCompleto, isTrue);
    });

    test('deuda real de 1 centavo USD bloquea el cobro', () {
      final cargo = calcularCobro(subtotal: 100.0, tasa: tasa).totalUSD;
      final r = calcularCobro(
        subtotal: 100.0,
        tasa: tasa,
        efectivoBs: redondearCentavos((cargo - 0.01) * tasa),
      );
      expect(r.pagoCompleto, isFalse);
      expect(r.vueltoUSD, equals(0.0));
    });

    test('vuelto nunca reporta céntimos fantasma (0.41 ≠ 0.40)', () {
      // Cargo 5.00 USD pagado en Bs con tasa 842.2067 (Bs exactos a 2dp).
      const tasaV = 842.2067;
      final cargoUSD = 5.00;
      final r = calcularCobro(
        subtotal: cargoUSD / 1.16,
        tasa: tasaV,
        efectivoBs: redondearCentavos(cargoUSD * tasaV),
      );
      expect(r.pagoCompleto, isTrue);
      expect(r.vueltoUSD, lessThan(0.005));
      expect(r.vueltoVES, lessThan(0.01));
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

  // ── MISIÓN 4: motor de céntimos enteros (ResultadoCobroCents) ────────────
  // Erradica el "céntimo fantasma" del double nativo de Dart: toda decisión de
  // UI (faltaCents / pagoCompleto / vueltoCents) se toma en int; los double
  // solo se usan para pintar en pantalla. Tasa BCV de prueba = 36.50 Bs/$.

  group('ResultadoCobroCents — céntimos enteros (Misión 4)', () {
    const tasaC = 36.50;

    test('M1: montos exactos USD (1192.95 / 9941.41) sin céntimo fantasma', () {
      for (final monto in [1192.95, 9941.41]) {
        final usdCents = (monto * 100).round();
        // Para que el "cargo total incl. IGTF" sea exactamente el monto tecleado,
        // el cargo base debe ser monto - 3%IGTF sobre el USD efectivamente pagado.
        final r = calcularCobroCents(
          cargoBaseUSD: monto * 0.97,
          tasa: tasaC,
          usdEfectivoCents: usdCents,
        );
        expect(r.cargoTotalCents, equals(usdCents),
            reason: 'cargo total == monto tecleado ($monto)');
        expect(r.faltaCents, equals(0));
        expect(r.pagoCompleto, isTrue);
        expect(r.diferenciaCents, equals(0));
        expect(r.vueltoCents, equals(0));
      }
    });

    test('M2: pago mixto USD + VES (tasa BCV) sin descalce de 1 céntimo', () {
      const cargoBase = 500.00;
      final usdCents = 30000; // 300 USD en efectivo
      final bsCents = (200.0 * tasaC * 100).round(); // resto 200 USD en Bs = 730000
      final r = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
        bsRecibidoCents: bsCents,
      );
      // recibidoUsdCents = usd + round(bs/tasa) = 30000 + 20000 = 50000
      expect(r.recibidoUsdCents, equals(50000));
      // El faltante exacto es el IGTF (entero); NO 1 céntimo de más/menos.
      expect(r.faltaCents, equals(r.igtfCents));
      expect(r.pagoCompleto, isFalse); // aún no cubre el IGTF

      // Cubrir también el IGTF en Bs -> pago completo, 0 falta.
      final bsTotal = ((r.cargoTotalCents - usdCents) * tasaC).round();
      final r2 = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
        bsRecibidoCents: bsTotal,
      );
      expect(r2.faltaCents, equals(0));
      expect(r2.pagoCompleto, isTrue);
    });

    test('M3: IGTF 3% sobre USD en céntimos con redondeo entero exacto', () {
      // usdCents -> igtfCents esperado (banker's: (n*3 + 50) ~/ 100).
      final casos = <int, int>{
        10000: 300,    // 100.00 -> 3.00
        119295: 3579,  // 1192.95 -> 35.79
        994141: 29824, // 9941.41 -> 298.24
        3333: 100,     // 33.33 -> 1.00
        50: 2,         // 0.50 -> 0.02
        1: 0,          // 0.01 -> 0.00
      };
      casos.forEach((usd, igtfEsperado) {
        final r = calcularCobroCents(
          cargoBaseUSD: usd / 100,
          tasa: tasaC,
          usdEfectivoCents: usd,
        );
        expect(r.igtfCents, equals(igtfEsperado), reason: 'USD=${usd / 100}');
        expect(r.igtfUSD, equals(igtfEsperado / 100));
      });
    });

    test('M4: faltan 1 céntimo -> faltaCents==1 y pagoCompleto==false', () {
      // REGLA TRIBUTARIA: el IGTF (3%) se calcula sobre el EFECTIVO EN DIVISAS
      // (usdEfectivoCents). Por eso el faltante NO puede simularse restando
      // céntimos al USD: al bajar la base imponible el IGTF se recalcula a la
      // baja y el déficit se dispara a 10 céntimos (bug de DISEÑO del test, no
      // del motor). Solución: congelar el USD y simular el faltante en Bs (VES),
      // que NO genera IGTF y por tanto deja el cargo total inalterado.
      const cargoBase = 100.00;
      final usdCents = 10000; // 100.00 USD efectivo (base imponible del IGTF)
      final rBase = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
      );
      // cargoTotal = base(10000) + IGTF(300) = 10300 céntimos.
      final faltanteRealCents = rBase.cargoTotalCents - usdCents; // 300
      // Pagamos en Bs exactamente 1 céntimo (equivalente USD) menos que el
      // faltante: 299 céntimos -> 2.99 USD x 36.50 = 109.135 Bs -> 10914 céntimos Bs.
      final bsPagadoCents = ((faltanteRealCents - 1) / 100 * tasaC * 100).round();

      final r = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
        bsRecibidoCents: bsPagadoCents,
      );
      expect(r.faltaCents, equals(1));
      expect(r.pagoCompleto, isFalse);
      expect(r.diferenciaCents, equals(-1));

      // El pago exacto del faltante en Bs completa el cobro sin vuelto espurio.
      final bsExacto = (faltanteRealCents / 100 * tasaC * 100).round();
      final r2 = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
        bsRecibidoCents: bsExacto,
      );
      expect(r2.faltaCents, equals(0));
      expect(r2.pagoCompleto, isTrue);
      expect(r2.vueltoCents, equals(0));
    });

    test('M5: vuelto/cambio en USD y VES es exacto', () {
      // REGLA TRIBUTARIA: el IGTF (3%) se cobra sobre el EFECTIVO FÍSICO
      // transado en divisas (aquí, los 250.00 USD entregados), NO sobre la base
      // del carrito. El test original calculaba el cargo con base 200.00
      // (IGTF=6.00) pero luego pagaba 250.00 (IGTF=7.50): ese descalce de base
      // producía 4400 en vez de los 4250 reales. Cálculo estricto:
      //   IGTF       = 3% de 250.00        =   7.50 USD
      //   CargoTotal = 200.00 + 7.50       = 207.50 USD
      //   Vuelto     = 250.00 - 207.50     =  42.50 USD = 4250 céntimos
      const cargoBase = 200.00;
      final r = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: 25000, // 250.00 USD efectivo
      );
      expect(r.igtfCents, equals(750)); // 7.50 USD
      expect(r.cargoTotalCents, equals(20750)); // 207.50 USD
      expect(r.vueltoCents, equals(4250));
      expect(r.vueltoUSD, equals(42.50));
      expect(r.vueltoVES, equals(1551.25)); // 42.50 x 36.50
      expect(r.diferenciaCents, equals(4250));
      expect(r.pagoCompleto, isTrue);
    });

    test('M5b: vuelto mixto (USD + Bs) mantiene exactitud en céntimos', () {
      const cargoBase = 150.00;
      final usdCents = 10000;
      final parcial = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
      );
      final bsCents = ((parcial.cargoTotalCents - usdCents) * tasaC).round();
      final r = calcularCobroCents(
        cargoBaseUSD: cargoBase,
        tasa: tasaC,
        usdEfectivoCents: usdCents,
        bsRecibidoCents: bsCents,
      );
      expect(r.faltaCents, equals(0));
      expect(r.pagoCompleto, isTrue);
      expect(r.vueltoCents, equals(0));
    });
  });
}
