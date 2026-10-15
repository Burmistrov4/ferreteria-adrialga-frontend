#!/usr/bin/env python3
"""Validador de imports/parts de Dart sin necesidad del toolchain de Flutter.

Motivo: en este equipo `flutter analyze` / `flutter build` fallan por el entorno
(error 231: agotamiento de named pipes), y `dart format --output=none` SOLO
parsea la sintaxis -- no resuelve rutas de import. Eso deja pasar errores como
`import 'walkthrough_overlay.dart';` cuando el archivo vive en `../widgets/`,
que solo explotan al compilar.

Este script hace lo que `dart format` NO hace: resuelve cada directiva
`import` / `export` / `part` y verifica que el archivo destino exista.

Uso:
    python tool/verificar_imports.py [raiz_proyecto]

Salida: lista de imports rotos y resumen. Exit code 1 si hay rotos.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Directivas que referencian otro archivo. `part of` NO lleva ruta -> se ignora.
DIRECTIVA = re.compile(r"^\s*(import|export|part)\s+(?!of\b)")
COMILLAS = re.compile(r"['\"]([^'\"]+)['\"]")

# Paquetes externos: no se validan contra el disco (viven en pub-cache).
EXTERNOS = ("dart:", "package:flutter", "package:flutter_test")


def archivos_dart(raices: list[Path]) -> list[Path]:
    vistos: list[Path] = []
    for raiz in raices:
        if not raiz.is_dir():
            continue
        vistos.extend(p for p in raiz.rglob("*.dart") if ".dart_tool" not in p.parts)
    return sorted(set(vistos))


def resolver(uri: str, origen: Path, lib_dir: Path) -> Path | None:
    """Devuelve la ruta esperada en disco, o None si es externo/irrelevante."""
    if uri.startswith("dart:"):
        return None
    if uri.startswith("package:"):
        resto = uri[len("package:"):]
        paquete, _, ruta = resto.partition("/")
        # Solo el propio paquete se resuelve contra lib/.
        if paquete == "adrialga_frontend":
            return lib_dir / ruta
        return None
    # Ruta relativa (./ ../ o desnuda): relativa al directorio del archivo.
    return (origen.parent / uri).resolve()


def main() -> int:
    raiz = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    lib_dir = raiz / "lib"
    raices = [raiz / "lib", raiz / "tool", raiz / "test", raiz / "integration_test"]

    archivos = archivos_dart(raices)
    if not archivos:
        print(f"[!] No se encontraron .dart bajo {raiz}")
        return 2

    rotos: list[tuple[Path, int, str, Path]] = []
    total_dirs = 0

    for archivo in archivos:
        try:
            lineas = archivo.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError) as exc:
            print(f"[!] No se pudo leer {archivo}: {exc}")
            continue
        for i, linea in enumerate(lineas, 1):
            if not DIRECTIVA.match(linea):
                continue
            for uri in COMILLAS.findall(linea):
                destino = resolver(uri, archivo, lib_dir)
                if destino is None:
                    continue
                total_dirs += 1
                if not destino.exists():
                    rotos.append((archivo, i, uri, destino))

    rel = lambda p: p.relative_to(raiz) if p.is_relative_to(raiz) else p  # noqa: E731

    print(f"Archivos .dart analizados : {len(archivos)}")
    print(f"Directivas resueltas      : {total_dirs}")
    if not rotos:
        print("\nOK: todos los imports/parts resuelven a un archivo existente.")
        return 0

    print(f"\nROTOS: {len(rotos)}\n")
    for archivo, ln, uri, destino in rotos:
        print(f"  {rel(archivo)}:{ln}")
        print(f"      import '{uri}'")
        print(f"      -> no existe: {rel(destino)}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
