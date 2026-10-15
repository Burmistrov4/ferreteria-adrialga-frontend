import '../utils/parseo.dart';

class CategoriaModel {
  final int categoriaId;
  final String nombreCategoria;
  final String? descripcion;
  final bool activo;

  /// Margen sugerido (%) aplicado por defecto a los productos de la
  /// categoría. null = vinieron sin datos o no aplica (cascada detiene).
  final double? margenSugerido;

  /// Prefijo técnico de SKU (ej. PIN, TAL.) que precede al número correlativo.
  final String? prefijoSku;

  /// FASE C: id de la categoría padre (null = raíz). Habilita el filtro en
  /// árbol `Categoría Padre -> Subcategoría -> Productos` del inventario.
  final int? categoriaPadreId;

  CategoriaModel({
    required this.categoriaId,
    required this.nombreCategoria,
    this.descripcion,
    this.activo = true,
    this.margenSugerido,
    this.prefijoSku,
    this.categoriaPadreId,
  });

  int get id => categoriaId;
  String get nombre => nombreCategoria;

  factory CategoriaModel.fromJson(Map<String, dynamic> json) {
    // FASE 3 - null-safety real:
    //  * `categoriaId` es `final int`, pero el backend puede mandar "12"
    //    (BIGINT serializado como string) -> el casteo implicito lanza
    //    TypeError en runtime y revienta la pantalla. numI nunca lanza.
    //  * `activo` puede llegar como 1/0 (tinyint) o "1"/"0"; un `?? true`
    //    sobre un entero 0 devuelve 0, no false -> tambien revienta.
    //  * `descripcion` se normaliza: '' -> null para no guardar vacios.
    return CategoriaModel(
      categoriaId: numI(
        json['categoriaId'] ?? json['Categoria_ID'] ?? json['id'],
      ),
      nombreCategoria:
          json['nombreCategoria'] ?? json['Nombre'] ?? json['nombre'] ?? '',
      descripcion: textoO(json['descripcion'] ?? json['Descripcion']),
      activo: numB(json['activo'] ?? json['Activo']),
      margenSugerido: double.tryParse(
          (json['margenSugerido'] ?? json['Margen_Sugerido'] ?? '')
              .toString()),
      prefijoSku: textoO(json['prefijoSku'] ?? json['Prefijo_SKU']),
      categoriaPadreId: _toIntNullable(
        json['categoriaPadreId'] ?? json['Categoria_Padre_ID'],
      ),
    );
  }

  /// Convierte a int? de forma segura (el backend puede mandar "12" o null).
  static int? _toIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
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
