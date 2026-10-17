/// Dominio PURO del login (sin dependencias de Flutter) para poder probarlo con
/// `dart` fuera del paquete (los hooks native-assets rompen `dart run` dentro
/// del paquete en este equipo — ver .workbuddy-ai/memory).
///
/// Contiene dos cosas:
///   1. La normalización de la URL del selector "Local Wi-Fi".
///   2. El resultado del login y su mensaje, para que la UI pueda decir la
///      VERDAD sobre por qué falló (ver [ResultadoLogin]).
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

/// Por qué terminó (o no) un intento de login.
///
/// Existe porque antes el cliente devolvía un simple `bool` y la UI tenía un
/// ÚNICO mensaje para todo: *"Credenciales incorrectas o servidor fuera de
/// línea"*. Eso mezclaba dos causas opuestas — una contraseña mal escrita y un
/// servidor que no contestó a tiempo — y mandaba al usuario a revisar la clave
/// cuando el problema era que la capa gratuita estaba dormida.
///
/// Medido el 2026-10-16: con `admin`/`admin123` (correctas) el login fallaba
/// de forma intermitente porque el cliente cortaba a los 8 s y el arranque en
/// frío de Render tarda bastante más. El segundo intento funcionaba.
enum ResultadoLogin {
  /// 200 con token: entró.
  ok,

  /// El servidor respondió y rechazó las credenciales (401/400/403).
  /// Aquí sí hay que revisar usuario y contraseña.
  credenciales,

  /// No hubo respuesta a tiempo (servidor dormido, sin red, DNS caído).
  /// Las credenciales pueden ser perfectas: hay que reintentar.
  servidor,

  /// El servidor contestó algo que no se entiende (5xx, cuerpo inválido).
  inesperado,
}

/// ¿Tiene sentido que el usuario vuelva a pulsar INGRESAR sin cambiar nada?
///
/// Solo cuando el problema fue del servidor: el segundo intento suele encontrar
/// el backend ya despierto.
bool reintentable(ResultadoLogin r) =>
    r == ResultadoLogin.servidor || r == ResultadoLogin.inesperado;

/// Mensaje que la UI debe mostrar. Nunca dice "credenciales incorrectas"
/// cuando en realidad el servidor no respondió.
String mensajeLogin(ResultadoLogin r) {
  switch (r) {
    case ResultadoLogin.ok:
      return 'Sesión iniciada';
    case ResultadoLogin.credenciales:
      return 'Usuario o contraseña incorrectos';
    case ResultadoLogin.servidor:
      return 'El servidor no respondió. Está despertando (plan gratuito): '
          'espera unos segundos y vuelve a pulsar INGRESAR';
    case ResultadoLogin.inesperado:
      return 'El servidor respondió con un error. Vuelve a intentarlo';
  }
}

/// Texto del indicador mientras el intento está en curso.
///
/// Pasados unos segundos se avisa de que el servidor está despertando, para
/// que una espera larga no parezca que la app se colgó.
String mensajeEsperaLogin(int segundosTranscurridos) {
  if (segundosTranscurridos < 6) return 'Verificando…';
  return 'El servidor está despertando (plan gratuito), puede tardar '
      'hasta un minuto…';
}
