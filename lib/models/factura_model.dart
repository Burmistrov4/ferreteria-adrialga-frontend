/// Modelo de una factura emitida (venta) para el registro de facturas.
class FacturaModel {
  final int facturaId;
  final String? numeroControl;
  final DateTime? fechaEmision;
  final double subtotal;
  final double totalIva;
  final double montoIgtf;
  final double? tasaCambio;
  final double totalGeneral;
  final String estatus;
  final int clienteId;
  final int usuarioId;
  final String? clienteNombre;
  final String? clienteRif;
  final String? usuarioNombre;
  final List<DetalleFacturaModel> detalles;
  final List<PagoFacturaModel> pagos;

  FacturaModel({
    required this.facturaId,
    this.numeroControl,
    this.fechaEmision,
    required this.subtotal,
    required this.totalIva,
    this.montoIgtf = 0.0,
    this.tasaCambio,
    required this.totalGeneral,
    required this.estatus,
    required this.clienteId,
    required this.usuarioId,
    this.clienteNombre,
    this.clienteRif,
    this.usuarioNombre,
    this.detalles = const [],
    this.pagos = const [],
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  static int _i(dynamic v) => (v == null) ? 0 : int.tryParse(v.toString()) ?? 0;
  static String _s(dynamic v) => (v ?? '').toString();

  factory FacturaModel.fromJson(Map<String, dynamic> json) {
    final detallesRaw = (json['detalle_facturas'] ?? json['Detalle_Facturas'] ??
            json['detalles'] ??
            [])
        as List<dynamic>? ?? [];

    return FacturaModel(
      facturaId: _i(json['Factura_ID'] ?? json['facturaId'] ?? json['id']),
      numeroControl: _s(json['Numero_Control'] ?? json['numeroControl']),
      fechaEmision: DateTime.tryParse(
        _s(json['Fecha_Emision'] ?? json['fechaEmision']),
      ),
      subtotal: _d(json['Subtotal'] ?? json['subtotal']),
      totalIva: _d(json['Total_IVA'] ?? json['totalIva']),
      montoIgtf: _d(json['Monto_IGTF'] ?? json['montoIgtf']),
      tasaCambio: _d(json['Tasa_Cambio'] ?? json['tasaCambio']),
      totalGeneral: _d(json['Total_General'] ?? json['totalGeneral']),
      estatus: _s(json['Estatus'] ?? json['estatus'] ?? 'Completada'),
      clienteId: _i(json['Cliente_ID'] ?? json['clienteId']),
      usuarioId: _i(json['Usuario_ID'] ?? json['usuarioId']),
      clienteNombre: _s(
        json['clientes']?['Razon_Social'] ??
            json['clientes']?['razonSocial'] ??
            '',
      ),
      clienteRif: _s(
        json['clientes']?['RIF_Cedula'] ??
            json['clientes']?['rifCedula'] ??
            '',
      ),
      usuarioNombre: _s(
        json['usuarios']?['Nombre'] ??
            json['usuarios']?['nombre'] ??
            '',
      ),
      detalles: detallesRaw
          .map((d) => DetalleFacturaModel.fromJson(d))
          .toList(),
      pagos:
          ((json['pagos'] ?? json['Pagos']) as List<dynamic>?)
              ?.map(
                (e) => PagoFacturaModel.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// Detalle de un renglón de la factura (producto, cantidad, precio, subtotal).
class DetalleFacturaModel {
  final int detalleId;
  final int productoId;
  final String productoNombre;
  final String productoSkU;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  DetalleFacturaModel({
    required this.detalleId,
    required this.productoId,
    required this.productoNombre,
    required this.productoSkU,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  static int _i(dynamic v) => (v == null) ? 0 : int.tryParse(v.toString()) ?? 0;
  static String _s(dynamic v) => (v ?? '').toString();

  factory DetalleFacturaModel.fromJson(Map<String, dynamic> json) {
    return DetalleFacturaModel(
      detalleId: _i(json['Detalle_ID'] ?? json['detalleId'] ?? json['id']),
      productoId: _i(json['Producto_ID'] ?? json['productoId']),
      productoNombre: _s(
        json['productos']?['Nombre'] ??
            json['productos']?['nombre'] ??
            '',
      ),
      productoSkU: _s(
        json['productos']?['SKU_Codigo'] ??
            json['productos']?['sku'] ??
            '',
      ),
      cantidad: _i(json['Cantidad'] ?? json['cantidad']),
      precioUnitario: _d(
        json['Precio_Unitario'] ?? json['precioUnitario'] ?? json['precio'],
      ),
      subtotal: _d(
        json['Subtotal'] ?? json['subtotal'] ?? json['sub_total'],
      ),
    );
  }
}

/// Registro de un método de pago aplicado a una factura (multipago).
/// `monto` puede estar en USD (si `esDivisa` es true) o en Bolívares.
/// Base del IGTF 3%: únicamente los pagos en divisas extranjeras.
class PagoFacturaModel {
  final String metodo;
  final double monto;
  final String? referencia;
  final bool esDivisa;
  final double? tasa;

  PagoFacturaModel({
    required this.metodo,
    required this.monto,
    this.referencia,
    this.esDivisa = false,
    this.tasa,
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  static String _s(dynamic v) => (v ?? '').toString();

  factory PagoFacturaModel.fromJson(Map<String, dynamic> json) {
    final tasaRaw = json['Tasa_Cambio'] ?? json['tasaCambio'] ?? json['tasa'];
    return PagoFacturaModel(
      metodo: _s(
        json['Metodo_Pago'] ?? json['metodo'] ?? json['metodoPago'] ?? '',
      ),
      monto: _d(json['Monto'] ?? json['monto']),
      referencia: _s(json['Referencia'] ?? json['referencia']),
      esDivisa: (json['Es_Divisa'] ?? json['esDivisa'] ?? false) == true,
      tasa: tasaRaw == null ? null : _d(tasaRaw),
    );
  }

  /// Equivalente en Bolívares: si ya está en Bs se devuelve el monto;
  /// si es divisa se convierte con su tasa de cambio (o la pasada por fallback).
  double enBolivares(double tasaFallback) {
    final t = (tasa != null && tasa! > 0) ? tasa! : tasaFallback;
    return esDivisa ? monto * t : monto;
  }
}