// test_login_url.dart — regresión PURA (sin Flutter) de normalizarUrlLocal.
// Ejecutar FUERA del paquete (hooks native-assets rompen `dart run` adentro):
//   dart tool/test_login_url.dart   → no funciona dentro del paquete
//   (copiar junto a lib/services/login_url.dart y correr desde .workbuddy-ai/tmp_darttest)
import '../lib/services/login_url.dart';

int _pass = 0;
int _fail = 0;
void check(String name, String actual, String expected) {
  final ok = actual == expected;
  if (ok) {
    _pass++;
  } else {
    _fail++;
  }
  print('${ok ? 'PASS' : 'FAIL'} · $name · obtuve="$actual" esperaba="$expected"');
}

void checkBool(String name, bool actual, bool expected) {
  final ok = actual == expected;
  if (ok) {
    _pass++;
  } else {
    _fail++;
  }
  print('${ok ? 'PASS' : 'FAIL'} · $name · obtuve=$actual esperaba=$expected');
}

void main() {
  // Caso del bug reportado: IP con protocolo pero SIN puerto (iba al :80).
  check('http://192.168.55.201/ → +puerto+api',
      normalizarUrlLocal('http://192.168.55.201/'),
      'http://192.168.55.201:3000/api');
  check('http://192.168.55.201 (sin barra)',
      normalizarUrlLocal('http://192.168.55.201'),
      'http://192.168.55.201:3000/api');
  // IP suelta (caso feliz histórico).
  check('IP suelta', normalizarUrlLocal('192.168.55.201'),
      'http://192.168.55.201:3000/api');
  // URL ya completa no se toca.
  check('URL completa intacta',
      normalizarUrlLocal('http://192.168.55.201:3000/api'),
      'http://192.168.55.201:3000/api');
  // Puerto explícito distinto se respeta.
  check('puerto explícito 8080 respetado',
      normalizarUrlLocal('http://192.168.55.201:8080'),
      'http://192.168.55.201:8080/api');
  // Valores persistidos viejos (http://IP/api sin puerto) se reparan.
  check('persistido viejo /api sin puerto se repara',
      normalizarUrlLocal('http://192.168.55.201/api'),
      'http://192.168.55.201:3000/api');
  // Entradas inválidas → '' (la UI muestra error).
  check('vacío → inválido', normalizarUrlLocal(''), '');
  check('sin host → inválido', normalizarUrlLocal('http://'), '');
  // Anti-regresión de dobles esquemas/puerto.
  final r = normalizarUrlLocal('http://192.168.55.201/');
  check('sin doble esquema ni duplicados',
      (!r.contains('http://http') && !r.contains('api/api') &&
              r.split(':3000').length - 1 == 1)
          ? r
          : 'BAD:$r',
      r);

  // ── Contenido mixto: página https:// llamando a un backend http:// ──
  // Caso MEDIDO el 2026-10-16: la web de GitHub Pages (HTTPS) pedía
  // http://192.168.55.156:3000/api/auth/login y Chrome la bloqueó antes de
  // salir ("Mixed Content ... has been blocked").
  checkBool('página https + api http → bloqueada',
      bloqueadaPorContenidoMixto('http://192.168.55.156:3000/api', 'https'),
      true);
  checkBool('página http + api http → permitida',
      bloqueadaPorContenidoMixto('http://192.168.55.156:3000/api', 'http'),
      false);
  checkBool('página https + api https → permitida',
      bloqueadaPorContenidoMixto('https://192.168.55.156:3000/api', 'https'),
      false);
  checkBool('fuera de web (esquema vacío) → permitida',
      bloqueadaPorContenidoMixto('http://192.168.55.156:3000/api', ''), false);
  checkBool('sin IP todavía (se asume http) → bloqueada',
      bloqueadaPorContenidoMixto('http://', 'https'), true);

  print('\nLOGIN-URL: PASS=$_pass FAIL=$_fail');  if (_fail > 0) {
    throw StateError('fallaron $_fail casos');
  }
}
