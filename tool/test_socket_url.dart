// Regresión ejecutable con `dart` puro (sin Flutter toolchain):
//   dart run tool/test_socket_url.dart
// Demuestra que la normalización de la URL del socket no produce URLs
// malformadas (bug: http://http://localhost:3000:3000).

import '../lib/services/socket_url.dart';

int fail = 0;
void check(String caso, String entrada, String esperado) {
  final obtenido = normalizarUrlSocket(entrada);
  final ok = obtenido == esperado;
  print('${ok ? 'PASS' : 'FAIL'} · $caso · in=$entrada → $obtenido');
  if (!ok) {
    fail++;
    print('   esperado: $esperado');
  }
}

void main() {
  check('IP LAN con /api', 'http://192.168.98.153:3000/api', 'http://192.168.98.153:3000');
  check('localhost con /api', 'http://localhost:3000/api', 'http://localhost:3000');
  check('localhost sin /api', 'http://localhost:3000', 'http://localhost:3000');
  check('/api con barra final', 'http://localhost:3000/api/', 'http://localhost:3000');
  check('espacios envolventes', '  http://127.0.0.1:3000/api  ', 'http://127.0.0.1:3000');
  check('https LAN', 'https://192.168.55.4:3000/api', 'https://192.168.55.4:3000');
  // Anti-regresión explícita del bug:
  final r = normalizarUrlSocket('http://localhost:3000/api');
  if (r.contains('http://http://') || r.contains('localhost:3000:3000')) {
    print('FAIL · reproducción del bug de URL malformada: $r');
    fail++;
  } else {
    print('PASS · bug de URL malformada no reproducible');
  }

  print(fail == 0 ? '\nSOCKET_URL: TODO PASS' : '\nSOCKET_URL: $fail FALLOS');
  if (fail > 0) {
    throw StateError('fallos en test_socket_url');
  }
}
