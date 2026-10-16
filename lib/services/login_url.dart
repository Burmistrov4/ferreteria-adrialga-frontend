/// Normalización de la URL del selector "Local Wi-Fi" del login.
///
/// Módulo PURO (sin dependencias de Flutter) para poder probarlo con `dart`
/// fuera del paquete (los hooks native-assets rompen `dart run` dentro del
/// paquete en este equipo — ver .workbuddy-ai/memory).
///
/// Acepta indistintamente:
///   - IP suelta:            192.168.55.201
///   - IP con protocolo:     http://192.168.55.201
///   - URL completa:         http://192.168.55.201:3000/api
///   - Con /api o con /      (se reconstruye limpia)
///
/// Regresión cubierta: antes, si el campo empezaba con "http" se usaba tal
/// cual SIN completar el puerto → el cliente posteaba a `http://<ip>/api/...`
/// (puerto 80) y el login fallaba con "servidor fuera de línea" aunque el
/// backend estuviera corriendo en el puerto 3000.
///
/// Devuelve la URL normalizada, o cadena vacía si la entrada no es un host
/// válido (la UI debe tratar '' como entrada inválida).
String normalizarUrlLocal(String input) {
  final raw0 = input.trim();
  if (raw0.isEmpty) return '';
  final raw = raw0.startsWith('http') ? raw0 : 'http://$raw0';
  final u = Uri.tryParse(raw);
  if (u == null || u.host.isEmpty) return '';
  final scheme = u.scheme == 'https' ? 'https' : 'http';
  final puerto = u.hasPort ? u.port : 3000; // backend Express en :3000
  return '$scheme://${u.host}:$puerto/api';
}

/// ¿El navegador va a BLOQUEAR esta llamada por contenido mixto?
///
/// Una página servida por HTTPS tiene prohibido pedir recursos `http://`: el
/// navegador corta la petición ANTES de que salga y la consola muestra
/// `Mixed Content: ... This request has been blocked`. No es un fallo del
/// backend ni de la IP: es política del navegador y no se puede desactivar
/// desde el código.
///
/// Medido el 2026-10-16: el frontend publicado en GitHub Pages (HTTPS) intentaba
/// `http://192.168.55.156:3000/api/auth/login` y el navegador lo bloqueó; la UI
/// mostraba "Credenciales incorrectas o servidor fuera de línea", que no
/// describe la causa. De ahí este aviso explícito.
///
/// [esquemaPagina] es el esquema con el que se cargó la app (en web,
/// `Uri.base.scheme`). Fuera de web se pasa '' o 'file' y nunca hay bloqueo.
bool bloqueadaPorContenidoMixto(String urlApi, String esquemaPagina) {
  if (esquemaPagina != 'https') return false;
  // 'https://…' no empieza por 'http://' (la 's' lo impide): solo marca http.
  return urlApi.startsWith('http://');
}
