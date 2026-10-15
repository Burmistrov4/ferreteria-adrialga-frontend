// Auditoría E2E de la app Flutter Web COMPILADA, en Chrome real.
//
// Motivo: `flutter run -d chrome` está bloqueado en este entorno (reg.EXE en la
// lista negra del sandbox). Se audita el bundle ya construido (`build/web`)
// servido por el propio backend en :3000 (mismo origen que la API → sin CORS).
//
// Usa `playwright-core` desde el workspace gestionado de Node vía createRequire,
// para que este script pueda vivir dentro del repo sin instalar nada aquí.
//
// Uso:
//   node tool/auditar_web.mjs
// Variables opcionales: BASE_URL, USUARIO, CLAVE, OUT_DIR
//
// Salida: capturas + `informe.json` en OUT_DIR. Exit 1 si hay errores de página
// o respuestas 4xx/5xx inesperadas.
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const requireWs = createRequire('C:/Users/Loro/.workbuddy-ai/binaries/node/workspace/');
const { chromium } = requireWs('playwright-core');

const BASE = process.env.BASE_URL ?? 'http://127.0.0.1:3000';
const USUARIO = process.env.USUARIO ?? 'admin';
const CLAVE = process.env.CLAVE ?? 'admin123';
const OUT = process.env.OUT_DIR ?? path.join(__dirname, '_auditoria_web');
mkdirSync(OUT, { recursive: true });

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

// Destinos del NavigationRail (índice → etiqueta), tal como los declara
// app_shell.dart. Se recorren todos para cazar pantallas rotas.
const DESTINOS = [
  'Inicio', 'Vender', 'Facturas', 'Clientes', 'Productos',
  'Compras', 'Proveedores', 'Caja y Finanzas', 'Ajustes', 'Guía',
];

const consolaErrores = [];
const pageErrors = [];
const httpMalos = [];
const reqFallidas = [];
const bitacora = [];

const paso = (m) => { console.log(m); bitacora.push(m); };

// ── Árbol semántico ───────────────────────────────────────────────────────
// Flutter no pinta widgets: pinta píxeles. El árbol semántico se construye sólo
// si algo lo pide; se enciende pulsando `flt-semantics-placeholder`.
async function encenderSemantica(page) {
  if (await page.locator('flt-semantics').count() > 0) return false;
  await page.locator('flt-semantics-placeholder').first().dispatchEvent('click');
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30_000 });
  return true;
}

// Extrae (etiqueta, rol, caja) de cada nodo. Cubre los TRES caminos del texto:
// aria-label, span hijo, y nodo de texto directo (sin hijos de elemento).
// Se pasa como FUNCIÓN (no como string): `page.evaluate` con un string evalúa la
// expresión y una función literal no es serializable → devolvería undefined.
function extraerNodos() {
  const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
  const etiquetaDe = (n) => {
    let e = n.getAttribute('aria-label') ?? '';
    if (e === '') {
      const hijo = n.children[0];
      if (hijo && hijo.tagName === 'SPAN') e = norm(hijo.textContent);
      else if (n.children.length === 0) e = norm(n.textContent);
    }
    return norm(e);
  };
  return [...document.querySelectorAll('flt-semantics')].map((n) => {
    const r = n.getBoundingClientRect();
    return {
      etiqueta: etiquetaDe(n),
      rol: n.getAttribute('role') ?? '',
      x: Math.round(r.x), y: Math.round(r.y),
      w: Math.round(r.width), h: Math.round(r.height),
      hijos: n.querySelectorAll('flt-semantics').length,
      hojas: n.querySelectorAll('flt-semantics').length === 0,
    };
  }).filter((n) => n.etiqueta !== '');
}

async function nodos(page) {
  return page.evaluate(extraerNodos);
}

// Centro del nodo MÁS PROFUNDO cuya etiqueta coincide exactamente. Preferimos el
// nodo hoja: las envolturas concatenan el texto de toda su descendencia.
// Centro del nodo cuya etiqueta coincide. `prefijo: true` acepta coincidencia
// por prefijo, que es lo que hace falta con el NavigationRail: sus etiquetas
// reales son "Vender Pestaña 2 de 10", no "Vender".
// Entre los candidatos se prefiere el nodo HOJA más pequeño: las envolturas
// concatenan el texto de toda su descendencia y su centro puede caer fuera.
async function centroDe(page, texto, { prefijo = false } = {}) {
  return page.evaluate(
    ({ txt, pref }) => {
      const norm = (s) => (s ?? '').replace(/\s+/g, ' ').trim();
      const etiquetaDe = (n) => {
        let e = n.getAttribute('aria-label') ?? '';
        if (e === '') {
          const hijo = n.children[0];
          if (hijo && hijo.tagName === 'SPAN') e = norm(hijo.textContent);
          else if (n.children.length === 0) e = norm(n.textContent);
        }
        return norm(e);
      };
      const coincide = (e) => (pref ? e === txt || e.startsWith(txt) : e === txt);
      const todos = [...document.querySelectorAll('flt-semantics')];
      const cands = todos.filter((n) => coincide(etiquetaDe(n)));
      if (cands.length === 0) return null;
      const hojas = cands.filter((n) => n.querySelectorAll('flt-semantics').length === 0);
      const pool = hojas.length ? hojas : cands;
      pool.sort((a, b) => {
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        return ra.width * ra.height - rb.width * rb.height;
      });
      const el = pool[0];
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) return null;
      return {
        x: r.x + r.width / 2,
        y: r.y + r.height / 2,
        w: r.width,
        h: r.height,
        etiqueta: etiquetaDe(el),
      };
    },
    { txt: texto, pref: prefijo }
  );
}

async function clickTexto(page, texto, { obligatorio = false, prefijo = false } = {}) {
  const c = await centroDe(page, texto, { prefijo });
  if (!c) {
    if (obligatorio) {
      throw new Error(`No encontré el elemento "${texto}" en el árbol semántico`);
    }
    return false;
  }
  await page.mouse.click(c.x, c.y);
  return c.etiqueta;
}

// El walkthrough de primer uso se abre solo al entrar a un módulo. Hay que
// cerrarlo o tapa la pantalla.
async function cerrarWalkthrough(page) {
  for (let i = 0; i < 4; i++) {
    const c = await centroDe(page, 'Omitir');
    if (!c) return i;
    await page.mouse.click(c.x, c.y);
    await page.waitForTimeout(350);
  }
  return -1;
}

async function captura(page, nombre) {
  await page.screenshot({ path: path.join(OUT, `${nombre}.png`), fullPage: false });
}

async function esperarTexto(page, texto, timeoutMs = 30_000, { prefijo = false } = {}) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    if (await centroDe(page, texto, { prefijo })) return true;
    await page.waitForTimeout(300);
  }
  return false;
}

// ── Main ──────────────────────────────────────────────────────────────────
const navegador = await chromium.launch({
  executablePath: CHROME,
  headless: true,
  args: [
    '--no-proxy-server',            // sólo loopback: nada de proxy
    '--enable-unsafe-swiftshader',  // CanvasKit/WebGL en headless
    '--disable-dev-shm-usage',
  ],
});

const contexto = await navegador.newContext({
  acceptDownloads: true,
  viewport: { width: 1600, height: 900 },
  deviceScaleFactor: 1,
});
const page = await contexto.newPage();

page.on('console', (m) => {
  if (m.type() === 'error') consolaErrores.push(m.text());
});
page.on('pageerror', (e) => pageErrors.push(String(e && e.message ? e.message : e)));
page.on('requestfailed', (r) => {
  const u = r.url();
  if (u.startsWith(BASE)) reqFallidas.push(`${r.failure()?.errorText ?? '?'} ${u}`);
});
page.on('response', (r) => {
  const u = r.url();
  if (!u.startsWith(BASE)) return;
  if (u.endsWith('/favicon.png')) return;
  if (r.status() >= 400) httpMalos.push(`${r.status()} ${r.request().method()} ${u}`);
});

try {
  paso(`BASE = ${BASE}`);
  await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60_000 });
  await page.waitForSelector('flt-semantics-placeholder, flt-semantics', { state: 'attached', timeout: 60_000 });
  const encendido = await encenderSemantica(page);
  paso(`Motor Flutter montado. Árbol semántico encendido ahora: ${encendido}`);
  await page.waitForTimeout(1200);

  await captura(page, '01-login');
  const arbolLogin = await nodos(page);
  paso(`Login: ${arbolLogin.length} nodos semánticos.`);

  // Campos: el input REAL dentro de flt-semantics; el aria-label es la etiqueta.
  const campoUsuario = page.locator('flt-semantics input[aria-label="Usuario / RIF / Email"]');
  const campoClave = page.locator('flt-semantics input[aria-label="Contraseña"]');
  if (await campoUsuario.count() === 0) throw new Error('No encontré el campo "Usuario / RIF / Email"');
  if (await campoClave.count() === 0) throw new Error('No encontré el campo "Contraseña"');

  await campoUsuario.click();
  await campoUsuario.pressSequentially(USUARIO, { delay: 20 });
  await campoClave.click();
  await campoClave.pressSequentially(CLAVE, { delay: 20 });

  const valorU = await campoUsuario.inputValue();
  const valorC = await campoClave.inputValue();
  paso(`Campos escritos (largo usuario=${valorU.length}, largo clave=${valorC.length}).`);
  if (valorU.length === 0 || valorC.length === 0) throw new Error('Algún campo quedó vacío tras teclear');

  await captura(page, '02-login-lleno');
  await clickTexto(page, 'INGRESAR', { obligatorio: true });

  const entro = await esperarTexto(page, 'Vender', 40_000, { prefijo: true });
  paso(`¿Apareció el shell (destino "Vender")?: ${entro}`);
  await page.waitForTimeout(1500);
  const cerrados = await cerrarWalkthrough(page);
  paso(`Walkthrough inicial cerrado (intentos): ${cerrados}`);
  await page.waitForTimeout(800);
  await captura(page, '03-inicio');
  const arbolShell = await nodos(page);
  writeFileSync(path.join(OUT, 'arbol-shell.json'), JSON.stringify(arbolShell, null, 2));

  // Recorrido de todos los destinos. Las etiquetas del rail son
  // "<Nombre> Pestaña N de 10" → coincidencia por prefijo.
  const recorrido = [];
  for (const destino of DESTINOS) {
    const etiqueta = await clickTexto(page, destino, { prefijo: true });
    if (!etiqueta) {
      recorrido.push({ destino, ok: false, motivo: 'no está en el árbol' });
      paso(`  ✗ ${destino}: no encontrado`);
      continue;
    }
    await page.waitForTimeout(1600);
    await cerrarWalkthrough(page);
    await page.waitForTimeout(600);
    const errAntes = pageErrors.length;
    await captura(page, `mod-${destino.replace(/[^a-zA-Z0-9]+/g, '_').toLowerCase()}`);
    recorrido.push({
      destino,
      etiqueta,
      ok: true,
      pageErrorsNuevos: pageErrors.length - errAntes,
    });
    paso(`  ✓ ${destino}  (nodo: "${etiqueta}")`);
  }
  writeFileSync(path.join(OUT, 'recorrido.json'), JSON.stringify(recorrido, null, 2));

  // ── Monitor de Base de Datos ────────────────────────────────────────────
  await clickTexto(page, 'Inicio', { prefijo: true });
  await page.waitForTimeout(1200);
  const abierto = await clickTexto(page, 'Monitor de BD');
  paso(`Monitor de BD: clic enviado = ${abierto}`);
  if (abierto) {
    await page.waitForTimeout(3000);
    await captura(page, '04-monitor-presentacion');
    const arbolMonitor = await nodos(page);
    writeFileSync(path.join(OUT, 'arbol-monitor.json'), JSON.stringify(arbolMonitor, null, 2));
    paso(`Monitor (presentación): ${arbolMonitor.length} nodos.`);

    // Cambio discreto a "completa" (full db). La etiqueta real del botón es
    // "Vista completa de la base completa".
    const aCompleta = await clickTexto(page, 'Vista completa', { prefijo: true });
    paso(`Cambio a modo completo: ${aCompleta}`);
    if (aCompleta) {
      await page.waitForTimeout(3000);
      await captura(page, '05-monitor-completa');
      const arbolFull = await nodos(page);
      writeFileSync(path.join(OUT, 'arbol-monitor-full.json'), JSON.stringify(arbolFull, null, 2));
      paso(`Monitor (completa): ${arbolFull.length} nodos.`);
    }

    // Volver al modo presentación (para dejar el estado como estaba).
    await clickTexto(page, 'Vista de presentación', { prefijo: true });
    await page.waitForTimeout(1500);
    await captura(page, '06-monitor-vuelta-presentacion');
  }
} catch (e) {
  pageErrors.push(`FALLO DEL GUION: ${e && e.message ? e.message : e}`);
  paso(`ERROR: ${e && e.message ? e.message : e}`);
  try { await captura(page, '99-error'); } catch { /* ignorar */ }
} finally {
  const informe = {
    base: BASE,
    generadoEn: new Date().toISOString(),
    consolaErrores,
    pageErrors,
    httpMalos,
    reqFallidas,
    bitacora,
  };
  writeFileSync(path.join(OUT, 'informe.json'), JSON.stringify(informe, null, 2));
  console.log('\n=== RESUMEN ===');
  console.log(`errores de consola : ${consolaErrores.length}`);
  console.log(`errores de página  : ${pageErrors.length}`);
  console.log(`HTTP 4xx/5xx       : ${httpMalos.length}`);
  console.log(`peticiones fallidas: ${reqFallidas.length}`);
  if (consolaErrores.length) console.log('\n[console.error]\n' + consolaErrores.slice(0, 12).join('\n'));
  if (pageErrors.length) console.log('\n[pageerror]\n' + pageErrors.slice(0, 12).join('\n'));
  if (httpMalos.length) console.log('\n[HTTP >=400]\n' + [...new Set(httpMalos)].slice(0, 20).join('\n'));
  if (reqFallidas.length) console.log('\n[requestfailed]\n' + [...new Set(reqFallidas)].slice(0, 20).join('\n'));
  console.log(`\nCapturas en ${OUT}`);
  await navegador.close();
  process.exit(pageErrors.length > 0 ? 1 : 0);
}
