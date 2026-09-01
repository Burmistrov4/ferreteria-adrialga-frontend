import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/categoria_model.dart';
import '../models/cliente_model.dart';
import '../models/factura_model.dart';
import '../models/producto_model.dart';

class ApiService {
  // ─── Configuración de la URL base de la API ───────────────────────────────
  // PRODUCCIÓN (por defecto): backend desplegado en Railway.
  //   URL pública: https://ferreteria-adrialga-backend-production.up.railway.app
  //
  // DESARROLLO LOCAL: para apuntar al backend local (http://localhost:3000),
  // compila/ejecuta con el flag de entorno USE_LOCAL_API=true:
  //   flutter run -d chrome --dart-define=USE_LOCAL_API=true
  //
  // También se puede sobrescribir la URL completa de forma manual:
  //   flutter run --dart-define=API_BASE_URL=https://mi-api.com/api
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const bool _usarLocal = bool.fromEnvironment('USE_LOCAL_API');

  static const String _urlProduccion = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ferreteria-adrialga-backend-production.up.railway.app/api',
  );
  static const String _urlLocalWeb = 'http://localhost:3000/api';

  // Determinación dinámica de la URL base según la plataforma
  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty && _usarLocal) return _baseUrlOverride;
    if (_usarLocal) {
      // Desarrollo local
      if (kIsWeb) return _urlLocalWeb;
      if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000/api'; // Emulador Android
      return _urlLocalWeb; // Windows / macOS / iOS Simulator
    }
    // Producción (por defecto en compilación web para Vercel)
    return _urlProduccion;
  }

  // Token JWT en memoria, persistido en SharedPreferences para reutilizarlo
  // entre sesiones y adjuntarlo como autorización en cada petición protegida.
  static String? _token;

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
    } catch (_) {
      _token = null;
    }
  }

  static bool get isLoggedIn => _token != null;

  /// Limpia la sesión local (útil al cerrar sesión).
  static Future<void> logout() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
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

  static Future<bool> registrarEntradaMercancia(
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
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
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
        return {'success': true};
      }
      return {'success': false, 'error': response.body};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Obtiene todas las facturas emitidas (para el registro de facturas).
  static Future<List<FacturaModel>> getFacturas() async {
    final response = await http
        .get(Uri.parse('$baseUrl/facturas'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => FacturaModel.fromJson(json)).toList();
    }
    throw Exception('Error al cargar facturas');
  }
}
