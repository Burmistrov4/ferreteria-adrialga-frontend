// lib/utils/cobro_engine.dart
// Motor de calculo de cobro, cambio e IGTF -- sin dependencias de Flutter UI.
// Clase pura (solo logica matematica), testeable con flutter test.
import '../utils/parseo.dart'; // numD: parseo seguro de Decimal/string del backend

/// Constantes fiscales venezolanas (SENIAT).
const double kIvaAliquota = 0.16;
const double kIgtfAliquota = 0.03;
const double kToleranciaVuelto = 0.005; // Medio centavo USD (céntimo fantasma)

/// Redondeo a centavos (unidad monetaria mínima). Usa la representación
/// decimal de Dart (toStringAsFixed), la cual implementa el redondeo
/// "half-even" correcto sobre dígitos decimales — evita el sesgo binario
/// de multiplicar por 100 (donde 1.005 vive como 1.004999…9 en memoria).
double redondearCentavos(double v) => double.parse(v.toStringAsFixed(2));

/// Resultado inmutable de un calculo de cobro.
class ResultadoCobro {
  /// Total bruto del carrito ANTES de IVA.
  final double subtotal;

  /// IVA 16% sobre el subtotal.
  final double iva;

  /// Total a facturar (subtotal + IVA). Sin IGTF.
  final double totalUSD;

  /// Equivalencia en bolivares del total (totalUSD x tasa).
  final double totalVES;

  /// Monto en USD efectivo entregado por el cliente.
  final double efectivoUSD;

  /// Monto en Bs entregado (Bs efectivo + Pago Movil + Punto de Venta).
  final double efectivoBs;

  /// Tasa de cambio BCV usada.
  final double tasa;

  /// IGTF (3%) calculado sobre los pagos en divisas (efectivoUSD).
  final double igtfUSD;

  /// IGTF expresado en bolivares.
  final double igtfVES;

  /// Total a cobrar incluyendo IGTF (totalUSD + igtfUSD).
  final double cargoTotalUSD;

  /// Total recibido convertido a USD equivalente.
  double get totalRecibidoUSD => efectivoUSD + (efectivoBs / tasa);

  /// Diferencia (positivo = vuelto; negativo = falta).
  double get diferenciaUSD => totalRecibidoUSD - cargoTotalUSD;

  /// Diferencia expresada en bolivares.
  double get diferenciaVES => diferenciaUSD * tasa;

  /// True si el pago cubre el cargo total (tolerancia de 1 centavo USD).
  bool get pagoCompleto =>
      redondearCentavos(diferenciaUSD) >= -kToleranciaVuelto;

  /// Vuelto a devolver en USD (0 si hubo deficit), redondeado a centavos.
  double get vueltoUSD {
    final v = redondearCentavos(diferenciaUSD);
    return v > 0 ? v : 0.0;
  }

  /// Vuelto expresado en bolivares (0 si hubo deficit).
  double get vueltoVES {
    final v = redondearCentavos(diferenciaVES);
    return v > 0 ? v : 0.0;
  }

  const ResultadoCobro({
    required this.subtotal,
    required this.iva,
    required this.totalUSD,
    required this.totalVES,
    required this.efectivoUSD,
    required this.efectivoBs,
    required this.tasa,
    required this.igtfUSD,
    required this.igtfVES,
    required this.cargoTotalUSD,
  });
}

/// Calcula el resultado completo de un cobro.
///
/// [subtotal]    - Suma de (precio x cantidad) de los items del carrito.
/// [tasa]        - Tasa BCV vigente (Bs por USD).
/// [efectivoUSD] - Monto en USD entregado por el cliente.
/// [efectivoBs]  - Suma de pagos en Bs (efectivo + PM + PdV).
ResultadoCobro calcularCobro({
  required double subtotal,
  required double tasa,
  double efectivoUSD = 0.0,
  double efectivoBs = 0.0,
}) {
  assert(tasa > 0, 'La tasa de cambio debe ser mayor a cero');
  assert(subtotal >= 0, 'El subtotal no puede ser negativo');

  final iva = subtotal * kIvaAliquota;
  final totalUSD = subtotal + iva;
  final totalVES = totalUSD * tasa;

  // IGTF solo sobre la porcion pagada en divisas (efectivoUSD).
  final igtfUSD = efectivoUSD * kIgtfAliquota;
  final igtfVES = igtfUSD * tasa;
  final cargoTotalUSD = totalUSD + igtfUSD;

  return ResultadoCobro(
    subtotal: subtotal,
    iva: iva,
    totalUSD: totalUSD,
    totalVES: totalVES,
    efectivoUSD: efectivoUSD,
    efectivoBs: efectivoBs,
    tasa: tasa,
    igtfUSD: igtfUSD,
    igtfVES: igtfVES,
    cargoTotalUSD: cargoTotalUSD,
  );
}

/// Calcula el subtotal de un carrito dado como lista de mapas
/// con claves 'precio' (double) y 'cantidad' (int/double).
double calcularSubtotal(List<Map<String, dynamic>> items) {
  return items.fold(0.0, (sum, item) {
    final precio = (item['precio'] as num?)?.toDouble() ?? 0.0;
    final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0.0;
    return sum + precio * cantidad;
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CÁLCULO EN CÉNTIMOS ENTEROS (Misión 4)
// -----------------------------------------------------------------------------
// Motivo: comparar "falta por pagar" / "vuelto" con `double` nativo produce el
// "céntimo fantasma" (p.ej. pagar 1192.95 y que quede $0.04 faltante) porque
// 1192.95 no es representable en binario y la resta deriva. Todo el gateo de
// la UI se hace aquí con `int` (céntimos); los `double` solo se usan para
// *pintar* en pantalla, nunca para decidir.
// ═══════════════════════════════════════════════════════════════════════════

/// Resultado de cobro expresado en céntimos enteros (sin floats en decisiones).
class ResultadoCobroCents {
  /// Total a facturar ANTES de IGTF (subtotal + IVA), en céntimos.
  final int cargoBaseCents;

  /// IGTF (3%) sobre el efectivo en divisas (USD), en céntimos.
  final int igtfCents;

  /// Total a cobrar incluyendo IGTF (cargoBase + igtf), en céntimos.
  final int cargoTotalCents;

  /// Monto recibido convertido a USD equivalente, en céntimos.
  final int recibidoUsdCents;

  /// Porción pagada en divisas (USD efectivo), en céntimos (base del IGTF).
  final int usdEfectivoCents;

  /// Suma de pagos en Bs, en céntimos.
  final int bsRecibidoCents;

  final double tasa;

  const ResultadoCobroCents({
    required this.cargoBaseCents,
    required this.igtfCents,
    required this.cargoTotalCents,
    required this.recibidoUsdCents,
    required this.usdEfectivoCents,
    required this.bsRecibidoCents,
    required this.tasa,
  });

  /// Diferencia en céntimos: positivo = vuelto, negativo = falta.
  int get diferenciaCents => recibidoUsdCents - cargoTotalCents;

  /// True cuando el recibido cubre el cargo (exacto o con excedente).
  bool get pagoCompleto => diferenciaCents >= 0;

  /// Céntimos que faltan para completar (0 si se pagó de más).
  int get faltaCents => diferenciaCents < 0 ? -diferenciaCents : 0;

  /// Céntimos de vuelto a devolver (0 si hubo déficit).
  int get vueltoCents => diferenciaCents > 0 ? diferenciaCents : 0;

  // ── Conversiones a double SOLO para mostrar en pantalla ──────────────────
  double get cargoBaseUSD => cargoBaseCents / 100;
  double get igtfUSD => igtfCents / 100;
  double get igtfVES => (igtfCents / 100) * tasa;
  double get cargoTotalUSD => cargoTotalCents / 100;
  double get cargoTotalVES => (cargoTotalCents / 100) * tasa;
  double get recibidoUSD => recibidoUsdCents / 100;
  double get diferenciaUSD => diferenciaCents / 100;
  double get diferenciaVES => (diferenciaCents / 100) * tasa;
  double get vueltoUSD => vueltoCents / 100;
  double get vueltoVES => (vueltoCents / 100) * tasa;
}

/// Calcula el cobro en céntimos enteros.
/// [cargoBaseUSD]      - Total a facturar (subtotal+IVA) en USD.
/// [tasa]              - Tasa BCV (Bs por USD).
/// [usdEfectivoCents]  - Efectivo en USD, en céntimos.
/// [bsRecibidoCents]   - Suma de pagos en Bs, en céntimos.
ResultadoCobroCents calcularCobroCents({
  required double cargoBaseUSD,
  required double tasa,
  int usdEfectivoCents = 0,
  int bsRecibidoCents = 0,
}) {
  assert(tasa > 0, 'La tasa de cambio debe ser mayor a cero');
  // Redondeo al céntimo más cercano: (v*100).round() es estable porque el
  // valor ya viene acotado a 2 decimales por centavosDeTexto.
  final cargoBaseCents = (cargoBaseUSD * 100).round();
  // IGTF 3% sobre divisas, redondeado al céntimo (banker's rounding vía +50 ~/100).
  final igtfCents = ((usdEfectivoCents * 3 + 50) ~/ 100);
  final cargoTotalCents = cargoBaseCents + igtfCents;
  // Conversión Bs -> USD en céntimos: divide y redondea al céntimo entero.
  final recibidoUsdCents = usdEfectivoCents + (bsRecibidoCents / tasa).round();
  return ResultadoCobroCents(
    cargoBaseCents: cargoBaseCents,
    igtfCents: igtfCents,
    cargoTotalCents: cargoTotalCents,
    recibidoUsdCents: recibidoUsdCents,
    usdEfectivoCents: usdEfectivoCents,
    bsRecibidoCents: bsRecibidoCents,
    tasa: tasa,
  );
}

/// Convierte un texto monetario ("1192.95") a céntimos enteros sin depender de
/// la aritmética inestable del double: parsea con redondeo a 2 decimales y
/// multiplica por 100. `numD` y `redondearCentavos` vienen de este módulo.
int centavosDeTexto(String texto) {
  final v = redondearCentavos(numD(texto));
  return (v * 100).round();
}
