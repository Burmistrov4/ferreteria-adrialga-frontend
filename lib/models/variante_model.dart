/// Modelos del inventario matricial (Tarea 5.2): variantes de producto con
/// atributos cruzados (ej. Color=Gris, Talla=M).
class ProductoVariante {
  final int varianteId;
  final String sku;
  final double precio;
  final double costo;
  final int stock;
  final bool activo;
  final Map<String, String> atributos;

  /// Margen propio de la variante (null → hereda del producto/categoría).
  final double? margenPropio;

  /// Margen resuelto por la cascada en el GET (para mostrar como referencia).
  final double margenEfectivo;

  const ProductoVariante({
    required this.varianteId,
    required this.sku,
    required this.precio,
    required this.costo,
    required this.stock,
    this.activo = true,
    this.atributos = const {},
    this.margenPropio,
    this.margenEfectivo = 0,
  });

  static double _d(dynamic v) =>
      (v == null) ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  factory ProductoVariante.fromJson(Map<String, dynamic> json) {
    return ProductoVariante(
      varianteId: int.tryParse(
              (json['varianteId'] ?? json['Variante_ID']).toString()) ??
          0,
      sku: (json['sku'] ?? json['SKU_Variante'] ?? '').toString(),
      precio: _d(json['precio'] ?? json['Precio_Venta']),
      costo: _d(json['costo'] ?? json['Costo_Unitario']),
      stock: int.tryParse((json['stock'] ?? json['Stock_Actual']).toString()) ?? 0,
      activo: json['activo'] is bool ? json['activo'] as bool : true,
      atributos: json['atributos'] is Map
          ? (json['atributos'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      margenPropio: json['margenPropio'] == null
          ? null
          : _d(json['margenPropio']),
      margenEfectivo: _d(json['margenEfectivo']),
    );
  }

  ProductoVariante copyWith({int? stock, double? costo, double? precio, bool? activo}) =>
      ProductoVariante(
        varianteId: varianteId,
        sku: sku,
        precio: precio ?? this.precio,
        costo: costo ?? this.costo,
        stock: stock ?? this.stock,
        activo: activo ?? this.activo,
        atributos: atributos,
      );
}

/// Respuesta agregada del endpoint GET /productos/:id/variantes:
/// matriz de combinaciones + ejes (atributo → valores posibles) ordenados.
class MatrizVariantes {
  final int productoId;
  final String skuBase;
  final String nombre;
  final List<ProductoVariante> matriz;

  /// Ejes ordenados: { 'Color': ['Gris', 'Azul'], 'Talla': ['S', 'M', 'L'] }.
  final Map<String, List<String>> ejes;

  const MatrizVariantes({
    required this.productoId,
    required this.skuBase,
    required this.nombre,
    required this.matriz,
    required this.ejes,
  });

  factory MatrizVariantes.fromJson(Map<String, dynamic> json) {
    final ejesRaw = json['ejes'] is Map
        ? (json['ejes'] as Map).map(
            (k, v) => MapEntry(
              k.toString(),
              (v as List).map((e) => e.toString()).toList(),
            ),
          )
        : <String, List<String>>{};
    return MatrizVariantes(
      productoId: int.tryParse('${json['productoId']}') ?? 0,
      skuBase: (json['skuBase'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      matriz: (json['matriz'] is List)
          ? (json['matriz'] as List)
              .whereType<Map<String, dynamic>>()
              .map(ProductoVariante.fromJson)
              .toList()
          : [],
      ejes: ejesRaw,
    );
  }
}
