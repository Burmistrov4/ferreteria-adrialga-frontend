class CategoriaModel {
  final int categoriaId;
  final String nombreCategoria;
  final String? descripcion;
  final bool activo;

  CategoriaModel({
    required this.categoriaId,
    required this.nombreCategoria,
    this.descripcion,
    this.activo = true,
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
