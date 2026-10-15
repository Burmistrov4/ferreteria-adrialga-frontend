#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Puerta de verificación del frontend Adrialga.
#
# En este equipo `flutter build web` y `dart analyze` NO se pueden usar como
# verificación: flutter_tools y el analysis server agotan las instancias de
# named pipes de Windows y mueren con
#     CreateFile failed 231 (Todas las instancias de canalización están en uso)
# (medido el 2026-10-14; ver doc/agentes/).
#
# La alternativa que SÍ funciona es invocar el compilador (CFE) en proceso,
# sin procesos hijos: se ejecuta `frontend_server` del propio SDK con
# `dartaotruntime`, resolviendo `dart:ui` contra el outline del SDK de
# Flutter Web. Eso hace análisis semántico COMPLETO (tipos, imports, APIs,
# argumentos con nombre, nulos) y falla con el mismo rigor que un build real.
#
# Uso:
#   bash tool/verificar_compilacion.sh
#
# Salida: EXIT 0 si todo compila; distinto de 0 si hay errores.
# ─────────────────────────────────────────────────────────────────────────────
set -u

FRONT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FRONT_DIR" || exit 2

# ── 1. Imports/parts resuelven a archivos existentes ────────────────────────
echo "== 1/2  Verificando imports y parts =="
if ! python tool/verificar_imports.py; then
  echo "FALLO: hay imports rotos."
  exit 1
fi

# ── 2. Compilación real (CFE) ───────────────────────────────────────────────
FLUTTER_BIN="$(command -v flutter || true)"
if [ -z "$FLUTTER_BIN" ]; then
  echo "FALLO: no se encontró 'flutter' en el PATH."
  exit 2
fi
FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
# El compilador exige URIs `file:`; en Git Bash `pwd` devuelve /c/... y eso se
# convierte en `file:////c/...` (ruta de red inválida). `pwd -W` da la forma
# Windows (C:/...) que sí se traduce a file:///C:/...
FLUTTER_ROOT_W="$(cd "$FLUTTER_ROOT" && { pwd -W 2>/dev/null || pwd; })"
SDK="$FLUTTER_ROOT/bin/cache/dart-sdk"
WEB_SDK="$FLUTTER_ROOT/bin/cache/flutter_web_sdk"
WEB_SDK_W="$FLUTTER_ROOT_W/bin/cache/flutter_web_sdk"
PLATFORM="file:///$WEB_SDK_W/kernel/ddc_outline.dill"
OUT="${TMPDIR:-/tmp}/adrialga_verificacion.dill"

for ruta in "$SDK/bin/dartaotruntime.exe" "$SDK/bin/snapshots/frontend_server_aot.dart.snapshot" "$WEB_SDK/kernel/ddc_outline.dill"; do
  if [ ! -f "$ruta" ]; then
    echo "FALLO: falta $ruta (¿SDK de Flutter incompleto?)."
    exit 2
  fi
done

echo "== 2/2  Compilando con el CFE (frontend_server) =="
LOG="${TMPDIR:-/tmp}/adrialga_verificacion.log"
"$SDK/bin/dartaotruntime.exe" \
  "$SDK/bin/snapshots/frontend_server_aot.dart.snapshot" \
  --sdk-root "$WEB_SDK_W/" \
  --platform "$PLATFORM" \
  --packages .dart_tool/package_config.json \
  --target dartdevc \
  --output-dill "$OUT" \
  lib/main.dart > "$LOG" 2>&1
CODE=$?

ERRORES="$(grep -c -E '^Error|: Error:|^Unhandled exception' "$LOG" 2>/dev/null || true)"

if [ "$CODE" -ne 0 ] || [ "${ERRORES:-0}" -ne 0 ]; then
  echo "FALLO: la compilación reportó errores."
  grep -n -E "^Error|: Error:|^Unhandled exception" "$LOG" | head -40
  echo "(log completo: $LOG)"
  exit 1
fi

echo "OK: la aplicación compila sin errores."
echo "    (log: $LOG)"
exit 0
