class ProductoModel {
  final int productoId;
  final String skuCodigo;
  final String nombre;
  final String? descripcion;
  final double precioVenta;
  final double costoPromedio;
  final int stockActual;
  final int stockMinimo;
  final int? categoriaId;
  final bool activo;

  ProductoModel({
    required this.productoId,
    required this.skuCodigo,
    required this.nombre,
    this.descripcion,
    required this.precioVenta,
    required this.costoPromedio,
    required this.stockActual,
    required this.stockMinimo,
    this.categoriaId,
    this.activo = true,
  });

  int get id => productoId;
  double get precio => precioVenta;

  /// Convierte a num un valor que puede llegar como int, double o String
  /// (Prisma serializa los campos DECIMAL de MySQL como cadenas, p. ej. "15.00").
  static num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return num.tryParse(s);
  }

  static double _toDouble(dynamic v) => (_asNum(v) ?? 0).toDouble();

  static int _toInt(dynamic v) => (_asNum(v) ?? 0).toInt();

  static int? _toIntNullable(dynamic v) => _asNum(v)?.toInt();

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    return v?.toString().toLowerCase() == 'true';
  }

  factory ProductoModel.fromJson(Map<String, dynamic> json) {
    return ProductoModel(
      productoId:
          _toInt(json['productoId'] ?? json['Producto_ID'] ?? json['id']),
      skuCodigo:
          (json['skuCodigo'] ?? json['SKU_Codigo'] ?? json['sku'] ?? '').toString(),
      nombre: (json['nombre'] ?? json['Nombre'] ?? '').toString(),
      descripcion: json['descripcion']?.toString() ??
          json['Descripcion']?.toString(),
      precioVenta: _toDouble(
        json['precioVenta'] ?? json['Precio_Venta'] ?? json['precio'],
      ),
      costoPromedio: _toDouble(json['costoPromedio'] ?? json['Costo_Promedio']),
      stockActual:
          _toInt(json['stockActual'] ?? json['Stock_Actual'] ?? json['stock']),
      stockMinimo: _toInt(json['stockMinimo'] ?? json['Stock_Minimo']),
      categoriaId: _toIntNullable(json['categoriaId'] ?? json['Categoria_ID']),
      activo: _toBool(json['activo'] ?? json['Activo'] ?? true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Producto_ID': productoId,
      'SKU_Codigo': skuCodigo,
      'Nombre': nombre,
      'Descripcion': descripcion,
      'Precio_Venta': precioVenta,
      'Costo_Promedio': costoPromedio,
      'Stock_Actual': stockActual,
      'Stock_Minimo': stockMinimo,
      'Categoria_ID': categoriaId,
      'Activo': activo,
    };
  }
}
