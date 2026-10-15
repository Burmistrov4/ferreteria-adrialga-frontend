{{flutter_js}}
{{flutter_build_config}}

// ── Bootstrap personalizado de Adrialga ────────────────────────────────────
// Fuerza que el renderer CanvasKit se sirva desde el PROPIO backend
// (/canvaskit/...) en lugar del CDN de gstatic. Beneficios:
//   1) La demo funciona SIN internet (solo la red del Hotspot).
//   2) El motor queda en el mismo origen → CSP más estricto y arranque más rápido.
// (Los dos marcadores de las primeras líneas los sustituye Flutter durante
//  `flutter build web`. NUNCA deben repetirse dentro de un comentario: el
//  contenido inyectado es multi-línea y rompería el archivo con un SyntaxError.)
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "/canvaskit/",
  },
});
