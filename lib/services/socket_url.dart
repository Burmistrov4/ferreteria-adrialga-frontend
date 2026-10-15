/// Normalización de la URL de Socket.IO.
///
/// Extraída a un módulo Dart puro (sin dependencias de Flutter) para poder
/// probarla con `dart` a secas. Regresión del siguiente defecto:
///
///   final api = ApiService.baseUrl; // http://localhost:3000/api
///   final base = api.replaceAll(RegExp(r'/api$'), '');
///   final server = base.replaceFirst('localhost', _explicitLocalIp(base));
///   // _explicitLocalIp devolvía la URL COMPLETA →
///   // server = 'http://http://localhost:3000:3000'  (malformada)
///
/// La selección del host (localhost vs IP LAN) ya la resuelve
/// `ApiService.baseUrl` desde SharedPreferences (`api_base_url`); aquí solo se
/// elimina el sufijo `/api` y cualquier barra final residual. No se reemplaza
/// ninguna subcadena del host.
library;

String normalizarUrlSocket(String apiBaseUrl) {
  var base = apiBaseUrl.trim();
  base = base.replaceAll(RegExp(r'/api/?$'), '');
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  return base;
}
