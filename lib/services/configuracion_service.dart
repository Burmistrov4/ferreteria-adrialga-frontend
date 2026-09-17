import 'api_service.dart';

/// Datos legales de la tienda (encabezado de PDFs y tickets térmicos).
class ConfiguracionTienda {
  final String nombre;
  final String rif;
  final String direccion;
  final String telefono;
  final String mensajePie;

  const ConfiguracionTienda({
    required this.nombre,
    required this.rif,
    required this.direccion,
    required this.telefono,
    required this.mensajePie,
  });

  /// Fallback local en caso de backend inalcanzable (nunca un PDF vacío).
  static const fallback = ConfiguracionTienda(
    nombre: 'FERRETERÍA ADRIALGA C.A.',
    rif: 'J-00000000-0',
    direccion: 'Dirección no configurada',
    telefono: '',
    mensajePie: 'Gracias por su compra',
  );

  factory ConfiguracionTienda.fromJson(Map<String, dynamic> j) =>
      ConfiguracionTienda(
        nombre: (j['nombre'] ?? fallback.nombre).toString(),
        rif: (j['rif'] ?? fallback.rif).toString(),
        direccion: (j['direccion'] ?? fallback.direccion).toString(),
        telefono: (j['telefono'] ?? '').toString(),
        mensajePie: (j['mensajePie'] ?? '').toString(),
      );
}

/// Caché en memoria de la configuración de tienda.
/// `obtener()` consulta backend una sola vez; los errores degradan
/// silenciosamente a [ConfiguracionTienda.fallback] para no bloquear PDFs.
class ConfiguracionService {
  ConfiguracionService._();

  static ConfiguracionTienda? _cache;

  static Future<ConfiguracionTienda> obtener() async {
    if (_cache != null) return _cache!;
    try {
      final data = await ApiService.getConfiguracionTienda();
      _cache = ConfiguracionTienda.fromJson(data);
    } catch (_) {
      _cache = ConfiguracionTienda.fallback;
    }
    return _cache!;
  }

  /// Invalida la caché; llamando a esto tras editar la config en Ajustes.
  static void invalidar() => _cache = null;
}
