/**
 * Verificador de TIPOS de Dart/Flutter para este equipo.
 *
 * Por qué existe: aquí `flutter analyze`, `dart analyze` y `dart test` mueren
 * los tres en su primer subproceso (Windows ERROR_PIPE_BUSY, código 231,
 * "Todas las instancias de canalización están en uso"). El problema NO es el
 * código: es que el VM de Dart no puede crear hijos porque construye su stdio
 * sobre una tubería NOMBRADA.
 *
 * El servidor de análisis, en cambio, es un proceso normal que habla por
 * stdin/stdout. Lanzándolo DIRECTAMENTE con `dartaotruntime.exe` el problema
 * desaparece... y Node SÍ puede crear procesos en esta máquina (con `spawn`,
 * nunca `spawnSync`, que falla con EBUSY por la misma familia de tuberías).
 *
 * Protocolo (dos trampas medidas, no adivinadas):
 *   1. `--protocol=analyzer`, NO `lsp`. Con LSP el servidor completa el
 *      `initialize`, analiza y NO publica ni un diagnóstico: el cliente se
 *      queda colgado para siempre.
 *   2. JSON delimitado por saltos de línea, SIN cabeceras `Content-Length`.
 *      Con formato LSP el servidor lee `Content-Length: 193` como mensaje y
 *      contesta INVALID_REQUEST.
 *   3. Hay que CONTESTAR a las peticiones que el servidor manda al cliente,
 *      o se queda colgado.
 *
 * Uso:
 *   node devops/analizar-dart.mjs                    # todo lib/ y test/
 *   node devops/analizar-dart.mjs lib/screens/x.dart # archivos concretos
 *
 * Código de salida: 0 si está limpio, 1 si hay errores o avisos (mismo listón
 * que `flutter analyze`, que también falla por warnings).
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const SDK = 'C:\\Users\\Loro\\develop\\flutter\\bin\\cache\\dart-sdk';
const RUNTIME = path.join(SDK, 'bin', 'dartaotruntime.exe');
const SNAPSHOT = path.join(
  SDK,
  'bin',
  'snapshots',
  'analysis_server_aot.dart.snapshot',
);

// ── Resolver archivos a analizar ────────────────────────────────────────────
const args = process.argv.slice(2);
const raices = args.length ? args : ['lib', 'test'].filter((d) => fs.existsSync(d));
const archivos = [];

function caminar(dir) {
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entrada.name);
    if (entrada.isDirectory()) {
      if (entrada.name.startsWith('.') || entrada.name === 'build') continue;
      caminar(p);
    } else if (entrada.name.endsWith('.dart')) {
      archivos.push(path.resolve(p));
    }
  }
}

for (const r of raices) {
  if (!fs.existsSync(r)) {
    console.error(`No existe: ${r}`);
    process.exit(1);
  }
  if (fs.statSync(r).isDirectory()) caminar(r);
  else archivos.push(path.resolve(r));
}

if (archivos.length === 0) {
  console.error('No se encontraron archivos .dart');
  process.exit(1);
}

// ── Lanzar el servidor de análisis ──────────────────────────────────────────
const servidor = spawn(
  RUNTIME,
  [SNAPSHOT, '--client-id=local-check', '--protocol=analyzer', '--sdk', SDK],
  { stdio: ['pipe', 'pipe', 'pipe'] },
);

let buffer = '';
const pendientes = new Map();
let siguienteId = 1;
let analizando = true;

function enviar(method, params) {
  const id = String(siguienteId++);
  servidor.stdin.write(JSON.stringify({ id, method, params }) + '\n');
  return new Promise((resolve) => pendientes.set(id, resolve));
}

servidor.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  let salto;
  while ((salto = buffer.indexOf('\n')) >= 0) {
    const linea = buffer.slice(0, salto).trim();
    buffer = buffer.slice(salto + 1);
    if (!linea) continue;
    let msg;
    try {
      msg = JSON.parse(linea);
    } catch {
      continue;
    }

    if (msg.event === 'analysis.analyzing') {
      analizando = Boolean(msg.params?.isAnalyzing);
      continue;
    }
    // Petición del servidor AL cliente: hay que contestar o se cuelga.
    if (msg.method && msg.id) {
      servidor.stdin.write(JSON.stringify({ id: msg.id, result: {} }) + '\n');
      continue;
    }
    if (msg.id && pendientes.has(String(msg.id))) {
      pendientes.get(String(msg.id))(msg);
      pendientes.delete(String(msg.id));
    }
  }
});

servidor.stderr.on('data', (d) => process.stderr.write(d.toString()));

// ── Esperar a que el análisis termine y recoger diagnósticos ────────────────
function esperarAnalisis(timeoutMs = 90000) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const timer = setInterval(() => {
      if (!analizando || Date.now() - t0 > timeoutMs) {
        clearInterval(timer);
        if (analizando && Date.now() - t0 > timeoutMs) {
          console.error(
            '⚠ Timeout esperando `analysis.analyzing`; se continúa igualmente.',
          );
        }
        resolve();
      }
    }, 200);
  });
}

const salir = (codigo) => {
  try {
    servidor.kill();
  } catch {
    /* ya murió */
  }
  process.exit(codigo);
};

try {
  // Sin suscribirse a STATUS el servidor NUNCA emite `analysis.analyzing`
  // y el cliente se queda esperando para siempre (medido, no adivinado).
  await enviar('server.setSubscriptions', { subscriptions: ['STATUS'] });
  await enviar('analysis.setAnalysisRoots', {
    included: raices.map((r) => path.resolve(r)),
    excluded: [],
  });
  await esperarAnalisis();

  const diagnosticos = [];
  for (const archivo of archivos) {
    const resp = await enviar('analysis.getErrors', { file: archivo });
    const errores = resp?.result?.errors ?? [];
    for (const e of errores) {
      // INFO/LINT no cuentan: flutter analyze falla por ERROR y WARNING.
      if (e.severity === 'INFO') continue;
      diagnosticos.push({
        archivo,
        severidad: e.severity,
        linea: e.location?.startLine ?? 0,
        columna: e.location?.startColumn ?? 0,
        codigo: e.code ?? '',
        mensaje: e.message ?? '',
      });
    }
  }

  if (diagnosticos.length === 0) {
    console.log(`✅ Sin errores ni avisos en ${archivos.length} archivo(s).`);
    salir(0);
  }

  for (const d of diagnosticos) {
    const rel = path.relative(process.cwd(), d.archivo);
    console.log(
      `${d.severidad} ${rel}:${d.linea}:${d.columna} [${d.codigo}] ${d.mensaje}`,
    );
  }
  const errores = diagnosticos.filter((d) => d.severidad === 'ERROR').length;
  const avisos = diagnosticos.length - errores;
  console.log(
    `\n❌ ${errores} error(es), ${avisos} aviso(s) en ${archivos.length} archivo(s).`,
  );
  salir(1);
} catch (e) {
  console.error('Fallo al analizar:', e);
  salir(1);
}
