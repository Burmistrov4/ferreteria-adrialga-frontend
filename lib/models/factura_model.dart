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
  final String? clienteDireccion;
  final String? clienteTelefono;
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
    this.clienteDireccion,
    this.clienteTelefono,
    this.usuarioNombre,
    this.detalles = const [],
    this.pagos = const [],
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  static int _i(dynamic v) => (v == null) ? 0 : int.tryParse(v.toString()) ?? 0;
  static String _s(dynamic v) => (v ?? '').toString();

  factory FacturaModel.fromJson(Map<String, dynamic> json) {
    // FASE 3: `as List<dynamic>?` lanzaba TypeError si el backend respondia
    // un Map de error o null. Ahora se verifica el tipo con `is`.
    final detallesRawRaw = json['detalle_facturas'] ??
        json['Detalle_Facturas'] ??
        json['detalles'];
    final List<dynamic> detallesRaw =
        detallesRawRaw is List ? detallesRawRaw : const <dynamic>[];

    // Misma proteccion para los pagos: nunca se castea a ciegas.
    final pagosRawRaw = json['pagos'] ?? json['Pagos'];
    final List<dynamic> pagosRaw =
        pagosRawRaw is List ? pagosRawRaw : const <dynamic>[];

    // Relaciones embebidas (`clientes`, `usuarios`). Si llegan como List o
    // como escalar, `?['campo']` lanza NoSuchMethodError; se normaliza a Map.
    Map<dynamic, dynamic> rel(String clave) {
      final v = json[clave] ?? json[clave.toLowerCase()];
      return v is Map ? v : const <dynamic, dynamic>{};
    }

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
        rel('clientes')['Razon_Social'] ?? rel('clientes')['razonSocial'] ?? '',
      ),
      clienteRif: _s(
        rel('clientes')['RIF_Cedula'] ?? rel('clientes')['rifCedula'] ?? '',
      ),
      clienteDireccion: _s(
        rel('clientes')['Direccion'] ?? rel('clientes')['direccion'] ?? '',
      ),
      clienteTelefono: _s(
        rel('clientes')['Telefono'] ?? rel('clientes')['telefono'] ?? '',
      ),
      usuarioNombre: _s(
        rel('usuarios')['Nombre'] ?? rel('usuarios')['nombre'] ?? '',
      ),
      // FASE 3: se descartan los elementos que no son Map en vez de
      // propagar el casteo dinamico (antes: `fromJson(d)` con d:dynamic).
      detalles: detallesRaw
          .whereType<Map>()
          .map((d) => DetalleFacturaModel.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
      pagos: pagosRaw
          .whereType<Map>()
          .map((e) => PagoFacturaModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
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

  /// SKU de la variante vendida (null = producto lineal).
  final String? varianteSku;

  /// Etiqueta de atributos de la variante, ej: "Color: Gris · Talla: M".
  final String? varianteEtiqueta;

  DetalleFacturaModel({
    required this.detalleId,
    required this.productoId,
    required this.productoNombre,
    required this.productoSkU,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.varianteSku,
    this.varianteEtiqueta,
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
  static int _i(dynamic v) => (v == null) ? 0 : int.tryParse(v.toString()) ?? 0;
  static String _s(dynamic v) => (v ?? '').toString();

  factory DetalleFacturaModel.fromJson(Map<String, dynamic> json) {
    // Variante embebida: { SKU_Variante, atributos: [{Atributo, Valor}, ...] }
    final vp = json['producto_variantes'];
    String? sku;
    String? etiqueta;
    if (vp is Map) {
      sku = _s(vp['SKU_Variante']);
      final attrs = vp['atributos'];
      if (attrs is List && attrs.isNotEmpty) {
        etiqueta = attrs
            .map((a) => a is Map ? '${_s(a['Atributo'])}: ${_s(a['Valor'])}' : '')
            .where((s) => s != '')
            .join(' · ');
      }
    }
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
      varianteSku: (sku?.isNotEmpty ?? false) ? sku : null,
      varianteEtiqueta: (etiqueta?.isNotEmpty ?? false) ? etiqueta : null,
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