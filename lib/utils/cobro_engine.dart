// lib/utils/cobro_engine.dart
// Motor de calculo de cobro, cambio e IGTF -- sin dependencias de Flutter UI.
// Clase pura (solo logica matematica), testeable con flutter test.

/// Constantes fiscales venezolanas (SENIAT).
const double kIvaAliquota = 0.16;
const double kIgtfAliquota = 0.03;
const double kToleranciaVuelto = 0.01; // Margen de 1 centavo USD

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
  bool get pagoCompleto => diferenciaUSD >= -kToleranciaVuelto;

  /// Vuelto a devolver en USD (0 si hubo deficit).
  double get vueltoUSD => diferenciaUSD > 0 ? diferenciaUSD : 0.0;

  /// Vuelto expresado en bolivares (0 si hubo deficit).
  double get vueltoVES => diferenciaVES > 0 ? diferenciaVES : 0.0;

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
