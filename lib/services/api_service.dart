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

  // Determinación dinámica de la URL base según la plataforma
  static String get baseUrl {
    String url;
    if (_baseUrlOverride.isNotEmpty) {
      // 1) Override explícito: gana sobre cualquier otro modo.
      url = _baseUrlOverride;
    } else if (_usarLocal) {
      // 2) Desarrollo local (solo como fallback cuando no hay override).
      if (kIsWeb) {
        url = _urlLocalWeb;
      } else if (!kIsWeb && Platform.isAndroid) {
        url = 'http://10.0.2.2:3000/api'; // Emulador Android
      } else {
        url = _urlLocalWeb; // Windows / macOS / iOS Simulator
      }
    } else {
      // 3) Producción (por defecto).
      url = _urlProduccion;
    }
    if (!url.endsWith('/api')) {
      if (url.endsWith('/')) {
        url = '${url}api';
      } else {
        url = '$url/api';
      }
    }
    return url;
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
            Uri.parse(
              '$baseUrl/clientes/consultar-cliente/$tipoDoc$numDoc',
            ),
            headers: _publicHeaders,
          )
          .timeout(const Duration(seconds: 10));
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
          .get(
            Uri.parse('$baseUrl/clientes?limit=$limit'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
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
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => CategoriaModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar categorías');
  }

  static Future<bool> createCategoria(String nombre, String descripcion) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/categorias'),
            headers: _headers,
            body: jsonEncode({'Nombre': nombre, 'Descripcion': descripcion}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Crea una categoría y devuelve el modelo recién creado (`null` si falla).
  /// Reutilizado por el diálogo de producto para crear categorías "in‑line"
  /// sin salir del formulario y seleccionarlas automáticamente.
  static Future<CategoriaModel?> createCategoriaConRetorno(
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return CategoriaModel.fromJson(data);
        }
        final catId = (data as num?)?.toInt();
        if (catId != null) return CategoriaModel(categoriaId: catId, nombreCategoria: nombre, descripcion: descripcion);
      }
      return null;
    } catch (_) {
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
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => ProductoModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar productos');
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
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteProducto(int id) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/productos/$id'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // --- PROVEEDORES E INVENTARIO ---
  static Future<List<dynamic>> getProveedores() async {
    final response = await http
        .get(Uri.parse('$baseUrl/proveedores'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Error al cargar proveedores');
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {'success': false, 'error': response.body};
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
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'error': response.body};
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
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, ...decod};
      }
      return {
        'success': false,
        'error': (decod['error'] as String?) ??
            (decod['message'] as String?) ??
            response.body,
        'tipo': decod['tipo'] as String?,
      };
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar: $e'};
    }
  }

  // --- AUTENTICACIÓN Y TASA ---
  static Future<bool> login(String usuario, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: _publicHeaders,
            // El backend espera las claves en CamelCase: Credencial y Password
            body: jsonEncode({'Credencial': usuario, 'Password': password}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _saveToken(data['token']?.toString());
        final usu = data['usuario'];
        if (usu is Map) {
          _saveRol((usu['rol'] ?? usu['Rol'])?.toString());
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<double> getTasaCambio() async {
    // 1) Tasa real del Banco Central de Venezuela vía el backend
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/clientes/bcv-rate'), headers: _publicHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tasa = data['tasa'];
        if (tasa != null) {
          final v = (tasa as num).toDouble();
          _lastTasa = v;
          _lastTasaEsBCV = true;
          return v;
        }
      }
    } catch (_) {}
    // 2) Fallback: endpoint de respaldo estático del backend
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/tasa-cambio'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tasa = data['tasa'];
        if (tasa != null) return (tasa as num).toDouble();
      }
    } catch (_) {}
    _lastTasa = 36.50;
    return _lastTasa;
  }

  // Última tasa consultada y si proviene del BCV real (no del respaldo).
  // Útil para que la interfaz advierta cuando el servicio BCV esté caído.
  static double _lastTasa = 36.50;
  static bool _lastTasaEsBCV = false;

  static double get lastTasa => _lastTasa;
  static bool get lastTasaEsBCV => _lastTasaEsBCV;

  /// Obtiene las métricas del dashboard desde el backend.
  static Future<Map<String, dynamic>> getDashboard() async {
    final response = await http
        .get(Uri.parse('$baseUrl/dashboard'), headers: _headers)
        .timeout(const Duration(seconds: 10));
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
    if (response.statusCode != 200) {
      throw Exception('Error al exportar el libro diario (HTTP ${response.statusCode})');
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        final decod = _decodificarError(response.body);
        return {
          'success': true,
          'factura': decod['factura'],
          ...decod,
        };
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
      return {'success': false, 'error': 'No se pudo conectar con el servidor: $e'};
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
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          ...decod,
          'notaCredito': decod['notaCredito'],
        };
      }
      return {
        'success': false,
        'error': (decod['error'] as String?) ??
            'No se pudo reversar la venta',
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
      final decod = _decodificarError(response.body);
      if (response.statusCode == 200) {
        return {'valido': true, ...decod};
      }
      return {'valido': false, 'error': decod['error'] ?? 'PIN de Supervisor inválido'};
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
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => FacturaModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar facturas');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TESORERÍA, CAJA Y CUENTAS POR PAGAR (Fase 5)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Obtiene el saldo actual de caja y resumen de movimientos.
  static Future<Map<String, dynamic>> getTesoreriaSaldo() async {
    final response = await http
        .get(Uri.parse('$baseUrl/tesoreria/saldo'), headers: _headers)
        .timeout(const Duration(seconds: 10));
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
    final uri = Uri.parse('$baseUrl/caja/historico').replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers).timeout(
          const Duration(seconds: 12),
        );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final filas = data['filas'] as List<dynamic>? ?? [];
      return filas.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Extrae el mensaje legible del cuerpo de un error HTTP.
  static String _mensajeError(String body) {
    try {
      final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
      return (json['error'] as String?) ??
          (json['message'] as String?) ??
          'Ocurrió un error inesperado';
    } catch (_) {
      return 'Ocurrió un error inesperado';
    }
  }
}
