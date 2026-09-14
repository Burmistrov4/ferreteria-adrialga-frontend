class CategoriaModel {
  final int categoriaId;
  final String nombreCategoria;
  final String? descripcion;
  final bool activo;

  /// Margen sugerido (%) aplicado por defecto a los productos de la
  /// categoría. null = vinieron sin datos o no aplica (cascada detiene).
  final double? margenSugerido;

  CategoriaModel({
    required this.categoriaId,
    required this.nombreCategoria,
    this.descripcion,
    this.activo = true,
    this.margenSugerido,
  });

  int get id => categoriaId;
  String get nombre => nombreCategoria;

  factory CategoriaModel.fromJson(Map<String, dynamic> json) {
    return CategoriaModel(
      categoriaId:
          json['categoriaId'] ?? json['Categoria_ID'] ?? json['id'] ?? 0,
      nombreCategoria:
          json['nombreCategoria'] ?? json['Nombre'] ?? json['nombre'] ?? '',
      descripcion: json['descripcion'] ?? json['Descripcion'],
      activo: json['activo'] ?? json['Activo'] ?? true,
      margenSugerido: double.tryParse(
          (json['margenSugerido'] ?? json['Margen_Sugerido'] ?? '')
              .toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Categoria_ID': categoriaId,
      'Nombre': nombreCategoria,
      'Descripcion': descripcion,
      'Activo': activo,
    };
  }
}
