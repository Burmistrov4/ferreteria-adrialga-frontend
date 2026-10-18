import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/categoria_model.dart';
import '../models/cliente_model.dart';
import '../models/factura_model.dart';
import '../models/producto_model.dart';
import 'download_service.dart';
import 'login_url.dart';

/// Resultado paginado del inventario (FASE C).
///
/// El catálogo EPA superó los 7.000 ítems: descargar todo al cliente
/// colapsaba la tabla, así que se pagina en servidor y el total del filtro
/// viaja en la cabecera `X-Total-Count`.
class ProductosPaginados {
  final List<ProductoModel> datos;
  final int total;

  const ProductosPaginados({required this.datos, required this.total});

  int get cantidad => datos.length;
  bool get vacio => datos.isEmpty;
}

class ApiService {
  // ─── Configuración de la URL base de la API ───────────────────────────────
  // PRODUCCIÓN (por defecto): backend desplegado en Railway.
  //   URL pública: https://ferreteria-adrialga-backend-production.up.railway.app
  //
  // DESARROLLO LOCAL: compila/ejecuta con el flag de entorno USE_LOCAL_API=true:
  //   flutter run -d chrome --dart-define=USE_LOCAL_API=true
  //
  // SOBRESCRITURA explícita (prioridad máxima): define la URL completa vía
  // --dart-define, útil para apuntar a un backend de staging o pruebas:
  //   flutter run --dart-define=API_BASE_URL=https://mi-api.com/api
  //
  // Prioridad de resolución (jerarquía):
  //   1. API_BASE_URL  → URL explícita (staging/QA/producción custom).
  //   2. USE_LOCAL_API → backend local (emulador o host).
  //   3. Valor por defecto → Railway de producción.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const bool _usarLocal = bool.fromEnvironment('USE_LOCAL_API');

  static const String _urlProduccion =
      'https://ferreteria-adrialga-backend-production.up.railway.app/api';
  static const String _urlLocalWeb = 'http://localhost:3000/api';

  // LAN Wi-Fi: IP fija de la laptop de desarrollo (visible al levantar
  // `npm run dev` — el servidor muestra "🌐 Acceso de red local: http://<ip>:3000").
  static const String _urlLocalLan = 'http://192.168.98.153:3000/api';

  /// URL base seleccionada en tiempo de ejecución (selector de entorno del
  /// Login: "Producción" / "Local con IP manual"). Se persiste en
  /// SharedPreferences; se prioriza sobre la resolución de entorno normal.
  static String? _baseUrlRuntime;

  /// Solo lectura del runtime (por ejemplo para precargar el selector del login).
  static String? get ultimoBaseUrlRuntime => _baseUrlRuntime;

  /// Sets/gets the runtime base URL (used by the login environment selector).
  static void setBaseUrlRuntime(String? apiUrl) {
    _baseUrlRuntime = apiUrl;
    SharedPreferences.getInstance().then((prefs) {
      if (apiUrl == null) {
        prefs.remove('api_base_url');
      } else {
        prefs.setString('api_base_url', apiUrl);
      }
    });
  }

  /// Caché leída al iniciar la app (llamar desde main).
  static Future<void> loadBaseUrlRuntime() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrlRuntime = prefs.getString('api_base_url');
  }

  // Determinación dinámica de la URL base según la plataforma.
  static String get baseUrl {
    // ── WEB ────────────────────────────────────────────────────────────────
    // En el despliegue unificado el frontend lo sirve el MISMO backend Node
    // (puerto :3000), así que la API vive en el MISMO ORIGEN. Se usa una URL
    // RELATIVA para evitar: CORS, el bloqueo de "red local" de Chrome
    // (localhost → 192.168.x) y recompilar cada vez que cambia la IP del
    // Hotspot. Solo si el build define API_BASE_URL (p. ej. GitHub Pages
    // apuntando a Railway) se respeta esa URL absoluta.
    if (kIsWeb) {
      // 1) Selección explícita del selector de entorno (Local Wi-Fi / IP manual).
      //    Permite apuntar la web a un backend DISTINTO del que la sirvió
      //    (p. ej. frontend en la nube + backend en la LAN del Hotspot).
      if (_baseUrlRuntime != null && _baseUrlRuntime!.isNotEmpty) {
        return _normalizarApi(_baseUrlRuntime!);
      }
      // 2) Override por --dart-define (staging / GitHub Pages → Railway).
      if (_baseUrlOverride.isNotEmpty) return _normalizarApi(_baseUrlOverride);
      // 3) Por defecto: MISMO ORIGEN (el backend sirve la web) → LAN automática.
      return _webApiBase;
    }

    // ── NATIVO ─────────────────────────────────────────────────────────────
    String url;
    if (_baseUrlRuntime != null && _baseUrlRuntime!.isNotEmpty) {
      // 1) Selección explícita en el Login (Local Wi-Fi / URL manual).
      url = _baseUrlRuntime!;
    } else if (_baseUrlOverride.isNotEmpty) {
      // 2) Override explícito por --dart-define.
      url = _baseUrlOverride;
    } else if (_usarLocal) {
      // 3) Desarrollo local: emulador Android / dispositivo Wi-Fi / escritorio.
      url = Platform.isAndroid ? _urlLocalLan : _urlLocalWeb;
    } else {
      // 4) Producción (por defecto).
      url = _urlProduccion;
    }
    return _normalizarApi(url);
  }

  /// Garantiza que la URL termine en `/api` sin duplicarlo.
  static String _normalizarApi(String url) {
    if (url.endsWith('/api')) return url;
    return url.endsWith('/') ? '${url}api' : '$url/api';
  }

  /// En web la API vive en el MISMO ORIGEN que la página (el backend Node sirve
  /// el frontend). Se construye la URL absoluta del mismo origen para no
  /// depender de la resolución de rutas relativas del cliente HTTP.
  static String get _webApiBase {
    try {
      final origen = Uri.base.origin; // p. ej. http://localhost:3000
      if (origen.isNotEmpty) return '$origen/api';
    } catch (_) {
      // Uri.base sin origen (about:blank): se usa relativo como respaldo.
    }
    return '/api';
  }

  // Token JWT en memoria, persistido en SharedPreferences para reutilizarlo
  // entre sesiones y adjuntarlo como autorización en cada petición protegida.
  static String? _token;

  // Rol del usuario activo (CAJERO | SUPERVISOR | ADMIN). Se usa para decidir
  // si una acción crítica exige la autorización en caliente por PIN.
  static String? usuarioRol;

  /// True si el usuario activo puede autorizar acciones críticas por sí mismo
  /// (SUPERVISOR/ADMIN). Si se desconoce el rol, se asume que NO puede.
  static bool get esSupervisor {
    final r = usuarioRol?.toUpperCase();
    return r == 'SUPERVISOR' || r == 'ADMIN';
  }

  // Headers para peticiones autenticadas (incluyen el token si existe)
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // Headers para peticiones públicas (login y consultas externas)
  static const Map<String, String> _publicHeaders = {
    'Content-Type': 'application/json',
  };

  /// Carga el token persistido al iniciar la aplicación.
  static Future<void> loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      usuarioRol = prefs.getString('auth_rol');
    } catch (_) {
      _token = null;
    }
  }

  static bool get isLoggedIn => _token != null;

  /// Token de sesión para autenticar el handshake de Socket.IO.
  /// Se mantiene de solo lectura para no duplicar el almacenamiento JWT.
  static String? get socketToken => _token;

  /// Limpia la sesión local (útil al cerrar sesión).
  static Future<void> logout() async {
    _token = null;
    usuarioRol = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('auth_rol');
    } catch (_) {}
  }

  static void _saveToken(String? token) {
    _token = token;
    if (token != null && token.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('auth_token', token);
      });
    }
  }

  /// Persiste el rol del usuario activo para las autorizaciones (override).
  static void _saveRol(String? rol) {
    usuarioRol = rol;
    if (rol != null && rol.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('auth_rol', rol);
      });
    }
  }

  /// Callback global invocado una sola vez cuando el backend reporta la
  /// sesión expirada (401 con `code: TOKEN_EXPIRADO | TOKEN_INVALIDO`).
  /// Lo registra main.dart con el SessionGuard (respaldar carrito + login).
  static void Function()? onSesionExpirada;
  static DateTime? _ultimaExpiracionNotificada;

  /// Interceptor central de sesión fiado en TODAS las llamadas autenticadas:
  /// ante un 401 con código de token vencido/inválido, limpia la sesión y
  /// notifica al UI (con antirrebote de 10 s para ráfagas de llamadas).
  static void _verificarSesion(http.Response response) {
    if (response.statusCode != 401) return;
    String? code;
    try {
      final c = jsonDecode(response.body);
      if (c is Map<String, dynamic>) code = c['code']?.toString();
    } catch (_) {}
    if (code != 'TOKEN_EXPIRADO' && code != 'TOKEN_INVALIDO') return;
    final ahora = DateTime.now();
    if (_ultimaExpiracionNotificada != null &&
        ahora.difference(_ultimaExpiracionNotificada!).inSeconds < 10) {
      return;
    }
    _ultimaExpiracionNotificada = ahora;
    _token = null;
    usuarioRol = null;
    logout(); // limpia SharedPreferences
    onSesionExpirada?.call();
  }

  // --- CLIENTES ---
  /// Búsqueda flexible en el servidor (nombre, RIF o cédula). Consulta
  /// GET /clientes?q=... que filtra con OR en el backend. Devuelve una lista
  /// para que la UI pueda desambiguar coincidencias parciales.
  static Future<List<ClienteModel>> buscarClientes(String query) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/clientes?q=${Uri.encodeComponent(query)}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => ClienteModel.fromJson(json)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// @deprecated Usar [buscarClientes]: /clientes/buscar ahora devuelve una
  /// lista y la búsqueda también acepta nombre.
  static Future<ClienteModel?> buscarClientePorDocumento(String query) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/clientes/buscar?documento=$query'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return ClienteModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> consultarSeniat(
    String tipoDoc,
    String numDoc,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/clientes/consultar-cliente/$tipoDoc$numDoc'),
            headers: _publicHeaders,
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'nombre': data['nombre'] ?? data['razon_social'],
        };
      }
      return {
        'success': false,
        'error': 'No se encontró información en SENIAT',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Error conectando al servicio SENIAT: $e',
      };
    }
  }

  // --- CLIENTES ---
  static Future<Map<String, dynamic>> crearCliente(dynamic cliente) async {
    try {
      final Map<String, dynamic> bodyData = cliente is ClienteModel
          ? cliente.toJson()
          : cliente as Map<String, dynamic>;

      final response = await http
          .post(
            Uri.parse('$baseUrl/clientes'),
            headers: _headers,
            body: jsonEncode(bodyData),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final clienteGuardado = data['cliente'] != null
            ? ClienteModel.fromJson(data['cliente'])
            : ClienteModel.fromJson(data);
        return {'success': true, 'cliente': clienteGuardado};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Devuelve los últimos [limit] clientes registrados (por orden de
  /// registro descendente) para el autoload del selector de clientes del POS.
  static Future<List<ClienteModel>> getUltimosClientes([int limit = 10]) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/clientes?limit=$limit'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => ClienteModel.fromJson(json)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<ClienteModel>> getClientes([String? query]) async {
    final uri = Uri.parse(
      query == null || query.trim().isEmpty
          ? '$baseUrl/clientes'
          : '$baseUrl/clientes?q=${Uri.encodeComponent(query.trim())}',
    );
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ClienteModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar clientes');
  }

  static Future<Map<String, dynamic>> updateCliente(
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/clientes/$id'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteCliente(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/clientes/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- CATEGORÍAS ---
  static Future<List<CategoriaModel>> getCategorias() async {
    final response = await http
        .get(Uri.parse('$baseUrl/categorias'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => CategoriaModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar categorías');
  }

  /// Extrae el `message` del backend de una respuesta de error.
  static String _mensajeErrorRespuesta(
    http.Response response,
    String fallback,
  ) {
    try {
      final body = jsonDecode(response.body);
      final m = body is Map<String, dynamic> ? body['message'] : null;
      return m?.toString().trim().isNotEmpty == true ? m.toString() : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<Map<String, dynamic>> createCategoria(
    String nombre,
    String descripcion,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/categorias'),
            headers: _headers,
            body: jsonEncode({'Nombre': nombre, 'Descripcion': descripcion}),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {
        'success': false,
        'error': _mensajeErrorRespuesta(
          response,
          'Error al crear la categoría',
        ),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Crea una categoría y devuelve el modelo recién creado (`null` si falla).
  /// Reutilizado por el diálogo de producto para crear categorías "in‑line"
  /// sin salir del formulario y seleccionarlas automáticamente.
  /// Expone `ultimoErrorCategoria` para que la UI muestre el mensaje exacto
  /// devuelto por el backend (409 duplicado, 400 validación, etc.).
  static String? ultimoErrorCategoria;

  static Future<CategoriaModel?> createCategoriaConRetorno(
    String nombre,
    String descripcion,
  ) async {
    ultimoErrorCategoria = null;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/categorias'),
            headers: _headers,
            body: jsonEncode({'Nombre': nombre, 'Descripcion': descripcion}),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return CategoriaModel.fromJson(data);
        }
        final catId = (data as num?)?.toInt();
        if (catId != null)
          return CategoriaModel(
            categoriaId: catId,
            nombreCategoria: nombre,
            descripcion: descripcion,
          );
      } else {
        ultimoErrorCategoria = _mensajeErrorRespuesta(
          response,
          'Error al crear la categoría',
        );
      }
      return null;
    } catch (e) {
      ultimoErrorCategoria = e.toString();
      return null;
    }
  }

  static Future<Map<String, dynamic>> updateCategoria(
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/categorias/$id'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteCategoria(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/categorias/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- PRODUCTOS ---
  static Future<List<ProductoModel>> getProductos() async {
    final response = await http
        .get(Uri.parse('$baseUrl/productos'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ProductoModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar productos');
  }

  /// Obtiene un producto concreto para precarga contextual (por ejemplo,
  /// desde una alerta de stock del Dashboard), sin descargar el catálogo.
  static Future<ProductoModel?> getProductoById(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/productos/$id'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return ProductoModel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 404) return null;
    throw Exception('Error al cargar el producto #$id');
  }

  // ───────────────────────── FASE C ─────────────────────────
  // Con el catálogo EPA (>7.000 ítems) ya no es viable descargar todo el
  // inventario al cliente: se pagina y filtra en servidor.

  /// Host sin el sufijo `/api` (para estáticos servidos por el backend,
  /// como las imágenes WebP en `/productos/{sku}.webp`).
  static String get hostUrl {
    final b = baseUrl;
    return b.endsWith('/api') ? b.substring(0, b.length - 4) : b;
  }

  /// URL absoluta de la imagen de un producto. Acepta rutas relativas
  /// (`/productos/SKU.webp`, las del catálogo EPA) y absolutas (http...).
  /// Devuelve null si no hay imagen.
  static String? urlImagen(String? ruta) {
    if (ruta == null || ruta.trim().isEmpty) return null;
    final r = ruta.trim();
    if (r.startsWith('http://') || r.startsWith('https://')) return r;
    return '$hostUrl${r.startsWith('/') ? r : '/$r'}';
  }

  /// Inventario paginado/filtrado en SERVIDOR.
  /// [categoriaIds] permite pedir un subárbol completo (padre + descendientes).
  /// Devuelve la página y el total que coincide con el filtro (cabecera
  /// `X-Total-Count`), para paginar sin una segunda petición de conteo.
  static Future<ProductosPaginados> getProductosPaginados({
    int limit = 50,
    int offset = 0,
    String? q,
    List<int>? categoriaIds,
    List<int>? productoIds,
    bool? conStock,
    bool? sinStock,
    int? proveedorId,
  }) async {
    final params = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (categoriaIds != null && categoriaIds.isNotEmpty) {
      params['categoriaId'] = categoriaIds.join(',');
    }
    if (productoIds != null && productoIds.isNotEmpty) {
      params['ids'] = productoIds.take(50).join(',');
    }
    if (conStock == true && sinStock == true) {
      throw ArgumentError('No se pueden solicitar ambos filtros de stock.');
    }
    if (conStock == true) params['conStock'] = '1';
    if (sinStock == true) params['sinStock'] = '1';
    // Filtro por proveedor de compra (0 = sin proveedor atribuible).
    if (proveedorId != null) params['proveedorId'] = '$proveedorId';
    final uri = Uri.parse('$baseUrl/productos')
        .replace(queryParameters: params);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 25));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      final total =
          int.tryParse(response.headers['x-total-count'] ?? '') ?? data.length;
      return ProductosPaginados(
        datos: data.map((json) => ProductoModel.fromJson(json)).toList(),
        total: total,
      );
    }
    throw Exception('Error al cargar productos');
  }

  /// Esquema en vivo de la base para el Monitor de BD.
  /// [modo]: 'presentacion' (12 tablas del modelo expuesto) | 'full' (todas).
  static Future<Map<String, dynamic>> getMonitorEsquema({
    String modo = 'presentacion',
  }) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/monitor/esquema?modo=$modo'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    }
    throw Exception('Error al cargar el esquema de la base de datos');
  }

  /// Insights del Asistente de Negocio (Centro de Notificaciones).
  /// Cada insight trae: id, severidad (critico|atencion|positivo), modulo,
  /// titulo, mensaje y datos opcionales.
  static Future<List<Map<String, dynamic>>> getNotificaciones() async {
    final response = await http
        .get(Uri.parse('$baseUrl/dashboard/notificaciones'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final Map<String, dynamic> body = jsonDecode(response.body);
      final lista = (body['insights'] as List?) ?? const [];
      return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Error al cargar notificaciones');
  }

  static Future<bool> createProducto(Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/productos'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateProducto(int id, Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/productos/$id'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Último mensaje accionable del backend al fallar un borrado de producto.
  static String? ultimoErrorProducto;

  static Future<bool> deleteProducto(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/productos/$id'))
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 204) {
        ultimoErrorProducto = null;
        return true;
      }
      // Conserva el mensaje del backend (p. ej. P2003: el producto tiene
      // facturas asociadas) en vez de descartarlo y mostrar un texto genérico.
      try {
        final data = jsonDecode(response.body);
        final msg = (data['message'] ?? data['error'] ?? '').toString().trim();
        ultimoErrorProducto = msg.isEmpty ? null : msg;
      } catch (_) {
        ultimoErrorProducto = null;
      }
      return false;
    } catch (_) {
      ultimoErrorProducto = null;
      return false;
    }
  }

  /// GET /configuracion — datos legales de la tienda (PDF/tickets).
  static Future<Map<String, dynamic>> getConfiguracionTienda() async {
    final response = await http
        .get(Uri.parse('$baseUrl/configuracion'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al cargar la configuración de la tienda');
  }

  /// PUT /configuracion — actualiza los datos legales de la tienda.
  static Future<Map<String, dynamic>> updateConfiguracionTienda(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/configuracion'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// GET /productos/:id/variantes — matriz y ejes del inventario matricial.
  static Future<Map<String, dynamic>> getVariantesProducto(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/productos/$id/variantes'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al cargar las variantes del producto');
  }

  /// POST /productos/:id/variantes/bulk — creación/upsert en lote.
  static Future<Map<String, dynamic>> crearVariantesBulk(
    int productoId,
    List<Map<String, dynamic>> variantes,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/productos/$productoId/variantes/bulk'),
            headers: _headers,
            body: jsonEncode({'variantes': variantes}),
          )
          .timeout(const Duration(seconds: 15));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _mensajeError(response.body)};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// PATCH /productos/variantes/:id — edición rápida inline (stock/costo/precio).
  static Future<Map<String, dynamic>> actualizarVariante(
    int varianteId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/productos/variantes/$varianteId'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': _mensajeError(response.body)};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// DELETE /productos/variantes/:id — soft-delete: la variante se archiva
  /// (Activo=false); nunca se borra físicamente para preservar el historial.
  static Future<Map<String, dynamic>> eliminarVariante(int varianteId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/productos/variantes/$varianteId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      try {
        final body = jsonDecode(response.body);
        return {
          'success': false,
          'error': body['message']?.toString() ?? response.body.toString(),
        };
      } catch (_) {
        return {'success': false, 'error': response.body.toString()};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- PROVEEDORES E INVENTARIO ---
  static Future<List<dynamic>> getProveedores() async {
    final response = await http
        .get(Uri.parse('$baseUrl/proveedores'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      // Robustez: un 200 con HTML (proxy mal enrutado, portal cautivo, etc.)
      // no debe reventar el parseo con un FormatException crudo. Se valida
      // que el cuerpo JSON sea realmente una lista.
      try {
        final data = jsonDecode(response.body);
        if (data is List) return data;
      } catch (_) {
        // cae al throw de abajo con un mensaje accionable
      }
      throw Exception(
        'Respuesta inválida del servidor (se esperaba una lista de proveedores)',
      );
    }
    throw Exception(
      'Error al cargar proveedores (HTTP ${response.statusCode})',
    );
  }

  static Future<Map<String, dynamic>> createProveedor(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/proveedores'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      // El backend ahora devuelve { success, code, message } estructurado:
      // se extrae 'message' para mostrarlo directo en la UI (antes llegaba
      // el cuerpo JSON crudo, ilegible para el cajero).
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': body['message']?.toString() ?? response.body,
          if (body['code'] != null) 'code': body['code'].toString(),
        };
      } catch (_) {
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Edita un proveedor existente (PUT /api/proveedores/:id).
  static Future<Map<String, dynamic>> updateProveedor(
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/proveedores/$id'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': false,
          'error': body['message']?.toString() ?? response.body,
          if (body['code'] != null) 'code': body['code'].toString(),
        };
      } catch (_) {
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Elimina un proveedor sin historial (DELETE /api/proveedores/:id).
  /// El backend responde 409 si tiene compras o CxP pendientes.
  static Future<Map<String, dynamic>> deleteProveedor(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/proveedores/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      try {
        final body = jsonDecode(response.body);
        return {'success': false, 'error': body['message'] ?? response.body};
      } catch (_) {
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Registra una entrada de mercancía (POST /api/notas).
  /// Devuelve un mapa con `success` y, en error, el `error`/`tipo` detallado
  /// (el backend puede devolver 422 SALDO_INSUFICIENTE con texto accionable
  /// para que la UI pueda orientar al cajero a Crédito o Ingreso de Caja).
  static Future<Map<String, dynamic>> registrarEntradaMercancia(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http
          .post(
            // El backend registra las entradas de inventario como
            // "notas de entrega" en el endpoint /api/notas.
            Uri.parse('$baseUrl/notas'),
            headers: _headers,
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, ...decod};
      }
      return {
        'success': false,
        'error':
            (decod['error'] as String?) ??
            (decod['message'] as String?) ??
            response.body,
        'tipo': decod['tipo'] as String?,
      };
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar: $e'};
    }
  }

  // --- AUTENTICACIÓN Y TASA ---
  /// Cuánto se espera al backend antes de rendirse en el login.
  ///
  /// 75 s, no 8 s. Render (plan gratuito) duerme el servicio a los 15 minutos
  /// sin tráfico y el arranque en frío tarda decenas de segundos. Con el límite
  /// anterior de 8 s, un login sobre el servicio dormido se abortaba SIEMPRE y
  /// la app culpaba a las credenciales, que eran correctas. Medido el
  /// 2026-10-16: el mismo `admin`/`admin123` fallaba en frío y entraba en
  /// caliente.
  static const Duration _timeoutLogin = Duration(seconds: 75);

  /// Despierta el backend en segundo plano (fire-and-forget).
  ///
  /// Se llama al abrir la app: si el servicio está dormido, empieza a arrancar
  /// mientras el usuario escribe sus credenciales, de modo que el login llegue
  /// con el servidor ya caliente. Los errores se ignoran a propósito — es una
  /// optimización, no un requisito: si falla, el login reintenta y da un
  /// mensaje honesto.
  static Future<void> despertarServidor() async {
    try {
      await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 75));
    } catch (_) {
      // Sin red, DNS caído o servicio dormido: nada que hacer aquí.
    }
  }

  /// Intenta iniciar sesión y devuelve POR QUÉ falló (ver [ResultadoLogin]).
  ///
  /// Antes devolvía un `bool`, así que la UI no podía distinguir una contraseña
  /// equivocada de un servidor que no contestó: ambos casos mostraban el mismo
  /// "Credenciales incorrectas o servidor fuera de línea".
  static Future<ResultadoLogin> login(String usuario, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: _publicHeaders,
            // El backend espera las claves en CamelCase: Credencial y Password
            body: jsonEncode({'Credencial': usuario, 'Password': password}),
          )
          .timeout(_timeoutLogin);
      _verificarSesion(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _saveToken(data['token']?.toString());
        final usu = data['usuario'];
        if (usu is Map) {
          _saveRol((usu['rol'] ?? usu['Rol'])?.toString());
        }
        return ResultadoLogin.ok;
      }

      // El servidor SÍ contestó y rechazó las credenciales.
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        return ResultadoLogin.credenciales;
      }

      // 5xx: el servidor contestó pero está roto (p. ej. la base apagada).
      // NO es culpa de la contraseña y conviene reintentar.
      return ResultadoLogin.inesperado;
    } on TimeoutException {
      // Ni una respuesta en el plazo: casi siempre el servicio estaba dormido.
      return ResultadoLogin.servidor;
    } catch (_) {
      // SocketException (sin red / DNS), ClientException (CORS o contenido
      // mixto)… Todo esto es "no llegamos al servidor", no "clave mala".
      return ResultadoLogin.servidor;
    }
  }

  static Future<double> getTasaCambio() async {
    // 1) Endpoint de cascada del backend: intenta la tasa OFICIAL en vivo
    //    (microservicio BCV o lectura directa desde Node) y, si no la consigue,
    //    devuelve la última persistida o la deducida del histórico, siempre
    //    indicando de dónde salió en `fuente` y con `aviso` cuando no es en vivo.
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/tasa-cambio'))
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tasa = data['tasa'];
        if (tasa != null) {
          // NUNCA castear datos de la API: el backend puede mandar la tasa
          // como String ("36.50") y el cast `(tasa as num)` revienta (o, con
          // el catch externo, caía en silencio al respaldo 36.50 → el POS
          // cobraba Bs e IGTF erróneos).
          final v = double.tryParse(tasa.toString());
          if (v == null || v <= 0) {
            // Tasa inválida: NO inventamos 36.50; conservamos la última
            // válida conocida y marcamos el aviso para la interfaz.
            _lastTasaEsBCV = false;
            _lastAvisoTasa =
                'El backend devolvió una tasa no válida ("$tasa"). Se conserva '
                'la última tasa conocida: ${_lastTasa.toStringAsFixed(2)}.';
            return _lastTasa;
          }
          final fuente = (data['fuente'] ?? '').toString();
          _hayTasaValida = true;
          _lastTasa = v;
          // Solo es "tasa BCV" si viene del banco en vivo (por cualquiera de
          // las dos vías). El histórico y el respaldo se marcan como tales para
          // que la interfaz advierta al usuario.
          // El backend puede obtener la tasa oficial por varias vías: directa,
          // por proxy o por un espejo en JSON que republica el BCV. TODAS son
          // tasa BCV en vivo; antes solo se reconocían dos y las demás se
          // etiquetaban como "respaldo" aunque el dato fuera oficial.
          const fuentesBcvEnVivo = <String>{
            'bcv-en-vivo',
            'bcv-directo',
            'bcv-proxy',
            'bcv-api-espejo',
          };
          _lastTasaEsBCV = fuentesBcvEnVivo.contains(fuente);
          _lastFuenteTasa = fuente;
          _lastAvisoTasa = data['aviso']?.toString();
          return v;
        }
      }
    } catch (_) {}
    // 2) Respaldo: endpoint público que solo consulta la tasa en vivo.
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/clientes/bcv-rate'), headers: _publicHeaders)
          .timeout(const Duration(seconds: 8));
      _verificarSesion(response);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tasa = data['tasa'];
        if (tasa != null) {
          final v = double.tryParse(tasa.toString());
          if (v == null || v <= 0) {
            _lastTasaEsBCV = false;
            _lastAvisoTasa =
                'La tasa pública devuelta no es válida ("$tasa"). Se conserva '
                'la última tasa conocida: ${_lastTasa.toStringAsFixed(2)}.';
            return _lastTasa;
          }
          _hayTasaValida = true;
          _lastTasa = v;
          _lastTasaEsBCV = true;
          _lastFuenteTasa = 'bcv-en-vivo';
          _lastAvisoTasa = null;
          return v;
        }
      }
    } catch (_) {}
    _lastTasaEsBCV = false;
    _lastFuenteTasa = 'fallback-local';
    // Si ya hubo alguna tasa válida en la sesión, se conserva: sobreescribirla
    // con 36.50 falsearía Bs, IGTF y márgenes. Solo se usa 36.50 como último
    // recurso cuando nunca se obtuvo una tasa real.
    if (!_hayTasaValida) {
      _lastTasa = 36.50;
      _lastAvisoTasa =
          'No se pudo contactar al backend para obtener la tasa. Se usa un '
          'valor de respaldo local (36.50) que puede NO ser la tasa actual.';
    } else {
      _lastAvisoTasa =
          'No se pudo contactar al backend para obtener la tasa. Se mantiene '
          'la última tasa conocida (${_lastTasa.toStringAsFixed(2)}); verifícala '
          'antes de cobrar.';
    }
    return _lastTasa;
  }

  // Última tasa consultada y si proviene del BCV real (no del respaldo).
  // Útil para que la interfaz advierta cuando el servicio BCV esté caído.
  static double _lastTasa = 36.50;
  /// ¿Se obtuvo al menos una tasa numérica válida desde el backend en esta
  /// sesión? Evita degradar en silencio una tasa buena al respaldo 36.50.
  static bool _hayTasaValida = false;
  static bool _lastTasaEsBCV = false;
  static String? _lastFuenteTasa;
  static String? _lastAvisoTasa;

  static double get lastTasa => _lastTasa;
  static bool get lastTasaEsBCV => _lastTasaEsBCV;

  /// Origen de la última tasa: `bcv-en-vivo`, `bcv-directo`, `cache-bd`,
  /// `historico-facturas`, `fallback-seguro` o `fallback-local`.
  static String? get lastFuenteTasa => _lastFuenteTasa;

  /// Explicación legible de por qué la tasa NO es la oficial en vivo.
  static String? get lastAvisoTasa => _lastAvisoTasa;

  /// Obtiene las métricas del dashboard desde el backend.
  static Future<Map<String, dynamic>> getDashboard() async {
    final response = await http
        .get(Uri.parse('$baseUrl/dashboard'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Error al cargar métricas del dashboard (HTTP ${response.statusCode})',
    );
  }

  /// Obtiene la serie financiera del dashboard para un periodo
  /// (hoy | semana | mes | anio): ventas agregadas, ticket promedio, margen,
  /// valoración de inventario, caja diaria por método y alertas de stock.
  static Future<Map<String, dynamic>> getSerieFinanciera(String periodo) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/dashboard/serie?periodo=$periodo'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Error al cargar la serie financiera (HTTP ${response.statusCode})',
    );
  }

  /// Exporta el libro diario de ventas y caja del período (auditoría fiscal).
  /// Compatible con Web (descarga vía Blob/AnchorElement) y Mobile/Desktop (archivo local).
  static Future<String?> exportarLibroDiarioCsv(String periodo) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/dashboard/exportar?periodo=$periodo&formato=csv'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    _verificarSesion(response);
    if (response.statusCode != 200) {
      throw Exception(
        'Error al exportar el libro diario (HTTP ${response.statusCode})',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'libro_diario_${periodo}_$timestamp.csv';

    // DownloadService maneja automáticamente Web vs Mobile/Desktop
    // usando conditional imports (dart.library.html / dart.library.io)
    await DownloadService.downloadFile(
      bytes: response.bodyBytes,
      filename: filename,
      mimeType: 'text/csv;charset=utf-8',
    );

    // En Mobile/Desktop retorna indicador de éxito
    return filename;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORTES FISCALES SENIAT (Fase 8/9) — Libro de Ventas, Compras y Resumen IVA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Construye los query params de período (anio/mes), por defecto el mes en curso.
  static Map<String, String> _periodoQuery(int? anio, int? mes) {
    final now = DateTime.now();
    return {
      'anio': (anio ?? now.year).toString(),
      'mes': (mes ?? now.month).toString(),
    };
  }

  /// Descarga el Libro de Ventas del período en CSV (BOM UTF-8, RFC-4180).
  /// En Web dispara la descarga; en Mobile/Desktop guarda y devuelve el nombre
  /// del archivo. Autenticado (Bearer).
  static Future<String?> exportarLibroVentasCsv({int? anio, int? mes}) async {
    final params = _periodoQuery(anio, mes);
    final response = await http
        .get(
          Uri.parse('$baseUrl/seniat/libro-ventas')
              .replace(queryParameters: {...params, 'formato': 'csv'}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _verificarSesion(response);
    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response.body));
    }
    final filename = 'libro_ventas_${params['anio']}-${params['mes']}.csv';
    await DownloadService.downloadFile(
      bytes: response.bodyBytes,
      filename: filename,
      mimeType: 'text/csv;charset=utf-8',
    );
    return filename;
  }

  /// Descarga el Libro de Compras del período en CSV (BOM UTF-8, RFC-4180).
  static Future<String?> exportarLibroComprasCsv({int? anio, int? mes}) async {
    final params = _periodoQuery(anio, mes);
    final response = await http
        .get(
          Uri.parse('$baseUrl/seniat/libro-compras')
              .replace(queryParameters: {...params, 'formato': 'csv'}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _verificarSesion(response);
    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response.body));
    }
    final filename = 'libro_compras_${params['anio']}-${params['mes']}.csv';
    await DownloadService.downloadFile(
      bytes: response.bodyBytes,
      filename: filename,
      mimeType: 'text/csv;charset=utf-8',
    );
    return filename;
  }

  /// Obtiene el Resumen de IVA (débito − crédito) del período como JSON.
  /// shape: { anio, mes, ventas:{documentos,...}, compras:{...}, ivaAPagarUsd }.
  static Future<Map<String, dynamic>> obtenerResumenIVA({
    int? anio,
    int? mes,
  }) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/seniat/resumen-iva')
              .replace(queryParameters: _periodoQuery(anio, mes)),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _verificarSesion(response);
    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response.body));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Descarga el Resumen de IVA como archivo JSON para auditoría local.
  static Future<String?> exportarResumenIvaJson({int? anio, int? mes}) async {
    final data = await obtenerResumenIVA(anio: anio, mes: mes);
    final params = _periodoQuery(anio, mes);
    final filename = 'resumen_iva_${params['anio']}-${params['mes']}.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    await DownloadService.downloadFile(
      bytes: bytes,
      filename: filename,
      mimeType: 'application/json;charset=utf-8',
    );
    return filename;
  }

  /// Descarga el Resumen de IVA en CSV (normativa SENIAT: ';' + BOM + CRLF),
  /// listo para adjuntar a la declaración sin re-tipear cifras.
  static Future<String?> exportarResumenIvaCsv({int? anio, int? mes}) async {
    final params = _periodoQuery(anio, mes);
    final response = await http
        .get(
          Uri.parse('$baseUrl/seniat/resumen-iva')
              .replace(queryParameters: {...params, 'formato': 'csv'}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _verificarSesion(response);
    if (response.statusCode != 200) {
      throw Exception(_mensajeError(response.body));
    }
    final filename = 'resumen_iva_${params['anio']}-${params['mes']}.csv';
    await DownloadService.downloadFile(
      bytes: response.bodyBytes,
      filename: filename,
      mimeType: 'text/csv;charset=utf-8',
    );
    return filename;
  }

  // --- FACTURACIÓN (POS) ---
  static Future<Map<String, dynamic>> createFactura(
    Map<String, dynamic> facturaData,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/facturas'),
            headers: _headers,
            body: jsonEncode(facturaData),
          )
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decod = _decodificarError(response.body);
        return {'success': true, 'factura': decod['factura'], ...decod};
      }
      // Expone 'tipo' (CAJA_CERRADA | ARQUEO_PENDIENTE | ...) para que la UI
      // dirija al cajero al módulo correcto con un mensaje accionable.
      final decodErr = _decodificarError(response.body);
      return {
        'success': false,
        'error': _mensajeError(response.body),
        if (decodErr['tipo'] != null) 'tipo': decodErr['tipo'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'No se pudo conectar con el servidor: $e',
      };
    }
  }

  /// Si el cuerpo es JSON con 'tipo' (p. ej. SALDO_INSUFICIENTE), lo expone
  /// para que la UI decida el flujo; devuelve map vacío si no es JSON.
  static Map<String, dynamic> _decodificarError(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map<String, dynamic>) return m;
    } catch (_) {}
    return const {};
  }

  /// Reversa una venta (P0.4): emite Nota de Crédito fiscal, retorna el stock
  /// recalculando el CMP y asienta el egreso en caja. Todo en una transacción
  /// ACID del backend. [pinSupervisor] es obligatorio si el usuario activo es
  /// CAJERO (autorización en caliente). Retorna { success, error?, tipo? }.
  static Future<Map<String, dynamic>> reversarVenta(
    int facturaId, {
    String? pinSupervisor,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/facturas/$facturaId/reversar'),
            headers: _headers,
            body: jsonEncode({'pinSupervisor': pinSupervisor}),
          )
          .timeout(const Duration(seconds: 15));
      _verificarSesion(response);
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, ...decod, 'notaCredito': decod['notaCredito']};
      }
      return {
        'success': false,
        'error': (decod['error'] as String?) ?? 'No se pudo reversar la venta',
        'tipo': (decod['tipo'] as String?) ?? '',
        'codigo': decod,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'No se pudo conectar con el servidor: $e',
        'tipo': '',
      };
    }
  }

  /// Valida en caliente el PIN de un Supervisor/Admin. Retorna `{valido, ...}`
  /// para autorizar una acción crítica (reversión, ajuste de inventario).
  static Future<Map<String, dynamic>> validarPinSupervisor(String pin) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/validar-pin-supervisor'),
            headers: _headers,
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 10));
      _verificarSesion(response);
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200) {
        return {'valido': true, ...decod};
      }
      return {
        'valido': false,
        'error': decod['error'] ?? 'PIN de Supervisor inválido',
      };
    } catch (e) {
      return {'valido': false, 'error': 'No se pudo verificar el PIN: $e'};
    }
  }

  /// Obtiene las facturas emitidas (para el registro de facturas).
  ///
  /// Filtro temporal opcional (excluyentes):
  ///  - [periodo]: 'hoy' | 'semana' | 'mes' | 'anio' (rangos relativos).
  ///  - [desde]/[hasta]: rango personalizado (se envía solo la fecha; la
  ///    demarcación exacta a 00:00:00 / 23:59:59.999 la hace el backend).
  static Future<List<FacturaModel>> getFacturas({
    String? periodo,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final params = <String, String>{};
    // El listado usa contrato resumido: detalles/pagos se solicitan solo al
    // abrir o imprimir una factura concreta.
    params['resumen'] = 'true';
    if (desde != null && hasta != null) {
      String iso(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      params['desde'] = iso(desde);
      params['hasta'] = iso(hasta);
    } else if (periodo != null && periodo.isNotEmpty) {
      params['periodo'] = periodo;
    }
    final uri = params.isEmpty
        ? Uri.parse('$baseUrl/facturas')
        : Uri.parse('$baseUrl/facturas').replace(queryParameters: params);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => FacturaModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar facturas');
  }

  /// Obtiene una factura completa, incluidos detalles y pagos, bajo demanda.
  static Future<FacturaModel> getFacturaById(int id) async {
    final response = await http
        .get(Uri.parse('$baseUrl/facturas/$id'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return FacturaModel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Error al cargar la factura #$id');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TESORERÍA, CAJA Y CUENTAS POR PAGAR (Fase 5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Obtiene el saldo actual de caja y resumen de movimientos.
  static Future<Map<String, dynamic>> getTesoreriaSaldo() async {
    final response = await http
        .get(Uri.parse('$baseUrl/tesoreria/saldo'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al consultar saldo de caja');
  }

  /// Calcula el patrimonio operativo: Caja + Σ(Stock × CostoPromedio).
  static Future<Map<String, dynamic>> getPatrimonioOperativo() async {
    final response = await http
        .get(Uri.parse('$baseUrl/tesoreria/patrimonio'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al calcular patrimonio operativo');
  }

  /// Verifica si hay fondos suficientes en caja para dar vuelto.
  /// Retorna { puedeProcesar: bool, saldoUSD: double, saldoVES: double, faltanteUSD: double, faltanteVES: double }
  static Future<Map<String, dynamic>> verificarFondosVuelto({
    required double vueltoUSD,
    required double vueltoVES,
    required double tasaCambio,
  }) async {
    final params = {
      'montoUSD': vueltoUSD.toString(),
      'montoVES': vueltoVES.toString(),
      'tasaCambio': tasaCambio.toString(),
    };
    final uri = Uri.parse('$baseUrl/tesoreria/verificar-fondos')
        .replace(queryParameters: params);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al verificar fondos en caja');
  }

  /// Obtiene la lista de cuentas por pagar pendientes.
  static Future<List<dynamic>> getCuentasPorPagar() async {
    final response = await http
        .get(Uri.parse('$baseUrl/tesoreria/cuentas-pagar'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Error al cargar cuentas por pagar');
  }

  /// Registra un abono (parcial o total) a una cuenta por pagar.
  static Future<Map<String, dynamic>> abonarCuentaPorPagar(
    int cxpId,
    double monto,
    String metodoPago,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/tesoreria/cuentas-pagar/abonar'),
            headers: _headers,
            body: jsonEncode({
              'cxpId': cxpId,
              'monto': monto,
              'metodoPago': metodoPago,
            }),
          )
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, ...decod};
      }
      return {
        'success': false,
        'error': (decod['error'] as String?) ?? 'Error al abonar la cuenta',
        if (decod['tipo'] != null) 'tipo': decod['tipo'],
      };
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar: $e'};
    }
  }

  /// Fondo de maniobra: inyecta dinero a la caja del turno activo.
  /// Requiere rol SUPERVISOR/ADMIN o PIN de supervisor (bcrypt en backend).
  static Future<Map<String, dynamic>> ingresarFondoCaja({
    required double monto,
    String metodoPago = 'Efectivo',
    String observacion = '',
    String? pinSupervisor,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/caja/ingreso'),
            headers: _headers,
            body: jsonEncode({
              'monto': monto,
              'metodoPago': metodoPago,
              'observacion': observacion,
              'pinSupervisor': ?pinSupervisor,
            }),
          )
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, ...decod};
      }
      return {
        'success': false,
        'error': (decod['error'] as String?) ?? 'Error al registrar el ingreso',
        if (decod['tipo'] != null) 'tipo': decod['tipo'],
      };
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar: $e'};
    }
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // APERTURA / CIERRE DE CAJA (arqueo por turno)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Consulta el estado actual del turno de caja.
  /// Retorna { cajaActiva, caja?, resumenTurno }.
  static Future<Map<String, dynamic>> getEstadoCaja() async {
    final response = await http
        .get(Uri.parse('$baseUrl/caja/estado'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Error al consultar el estado de la caja');
  }

  /// Abre un nuevo turno de caja con un monto inicial (arranque).
  static Future<Map<String, dynamic>> abrirCaja({
    required double montoInicial,
    String? observacion,
  }) async {
    final body = <String, dynamic>{'montoInicial': montoInicial};
    final obs = observacion?.trim();
    if (obs != null && obs.isNotEmpty) body['observacion'] = obs;
    final response = await http
        .post(
          Uri.parse('$baseUrl/caja/abrir'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    _verificarSesion(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return {'success': true, ...jsonDecode(response.body)};
    }
    return {'success': false, 'error': _mensajeError(response.body)};
  }

  /// Cierra el turno activo con el arqueo (monto contado en caja).
  static Future<Map<String, dynamic>> cerrarCaja({
    double? montoContado,
    String? observacion,
  }) async {
    final body = <String, dynamic>{};
    if (montoContado != null) body['montoContado'] = montoContado;
    final obs = observacion?.trim();
    if (obs != null && obs.isNotEmpty) body['observacion'] = obs;
    final response = await http
        .post(
          Uri.parse('$baseUrl/caja/cerrar'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    _verificarSesion(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return {'success': true, ...jsonDecode(response.body)};
    }
    return {'success': false, 'error': _mensajeError(response.body)};
  }

  /// Reporte de arqueos del mes: turnos con saldo inicial/ingresos/egresos/
  /// esperado/entregado y la diferencia (faltante/sobrante).
  /// [anio]/[mes] opcionales; por defecto el mes en curso.
  static Future<List<Map<String, dynamic>>> getHistoricoArqueos({
    int? anio,
    int? mes,
  }) async {
    final now = DateTime.now();
    final params = <String, String>{
      'anio': (anio ?? now.year).toString(),
      'mes': (mes ?? now.month).toString(),
    };
    final uri = Uri.parse('$baseUrl/caja/historico')
        .replace(queryParameters: params);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final filas = data['filas'] as List<dynamic>? ?? [];
      return filas.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ── Gestión de Usuarios (Módulo de Configuración) ──────────────────────────
  /// Lista de usuarios (el backend nunca expone las contraseñas).
  static Future<List<Map<String, dynamic>>> getUsuarios() async {
    final response = await http
        .get(Uri.parse('$baseUrl/usuarios'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    _verificarSesion(response);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Crea un colaborador. Devuelve {success, usuario} o {success:false, error}.
  static Future<Map<String, dynamic>> crearUsuario(
    Map<String, dynamic> datos,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/usuarios'),
            headers: _headers,
            body: jsonEncode(datos),
          )
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return {'success': true, 'usuario': body['usuario']};
      }
      return {'success': false, 'error': _mensajeError(response.body)};
    } catch (e) {
      return {'success': false, 'error': 'Sin conexión: $e'};
    }
  }

  /// Actualiza un colaborador (la protección del root la aplica el backend).
  static Future<Map<String, dynamic>> actualizarUsuario(
    int id,
    Map<String, dynamic> datos,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/usuarios/$id'),
            headers: _headers,
            body: jsonEncode(datos),
          )
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {'success': true, 'usuario': body['usuario']};
      }
      return {'success': false, 'error': _mensajeError(response.body)};
    } catch (e) {
      return {'success': false, 'error': 'Sin conexión: $e'};
    }
  }

  /// Desactiva (soft delete) un colaborador.
  static Future<Map<String, dynamic>> desactivarUsuario(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/usuarios/$id'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      _verificarSesion(response);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': _mensajeError(response.body)};
    } catch (e) {
      return {'success': false, 'error': 'Sin conexión: $e'};
    }
  }

  /// Extrae el mensaje legible del cuerpo de un error HTTP.
  static String _mensajeError(String body) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      return (json['error'] as String?) ??
          (json['message'] as String?) ??
          'Ocurrió un error inesperado';
    } catch (_) {
      return 'Ocurrió un error inesperado';
    }
  }
}
