{{flutter_js}}
{{flutter_build_config}}

// ── Bootstrap personalizado de Adrialga ────────────────────────────────────
// Fuerza que el renderer CanvasKit se sirva desde el PROPIO backend
// (canvaskit/...) en lugar del CDN de gstatic. Beneficios:
//   1) La demo funciona SIN internet (solo la red del Hotspot).
//   2) El motor queda en el mismo origen → CSP más estricta y arranque más rápido.
// (Los dos marcadores de las primeras líneas los sustituye Flutter durante
//  `flutter build web`. NUNCA deben repetirse dentro de un comentario: el
//  contenido inyectado es multi-línea y rompería el archivo con un SyntaxError.)
//
// ⚠️ El valor de canvasKitBaseUrl es RELATIVO a propósito. El loader de Flutter
// lo resuelve con `new URL(valor, document.baseURI)`, o sea contra el <base href>
// del index.html. Si empieza con "/" se salta ese <base> y pide el motor a la
// RAÍZ del dominio: en GitHub Pages el sitio vive en
// /ferreteria-adrialga-frontend/ y la petición cayó en 404 → app en blanco.
// Con "canvaskit/" (sin barra inicial) el mismo archivo funciona en los dos
// despliegues: en la raíz del backend (:3000 / Render) y en el subpath de Pages.
// No volver a ponerle la barra inicial.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
