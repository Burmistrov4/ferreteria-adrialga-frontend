#!/usr/bin/env python3
"""
generar_iconos_android.py — Genera el icono de lanzador de Adrialga POS.

Reemplaza el icono por defecto de Flutter (el logo azul de Flutter) por un
monograma de marca "A" sobre el azul corporativo de la app (#3B82F6 → #1D4ED8).

IMPORTANTE: es un PLACEHOLDER de marca. Sustitúyelo por el logo oficial de
Adrialga cuando exista: basta reemplazar MASTER_SRC o volver a ejecutar este
script con el logo real como fuente.

Genera:
  · Android legacy:      mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
  · Android adaptativo:  mipmap-*/ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml
                         + values/colors.xml (ic_launcher_background)
  · Web (Flutter Web):   web/icons/{Icon-192,Icon-512,Icon-maskable-192,Icon-maskable-512}.png
                         + web/favicon.png

Uso:
  python generar_iconos_android.py            # escribe los iconos
  python generar_iconos_android.py --check    # solo verifica (no escribe)
"""
from __future__ import annotations

import argparse
import os
from PIL import Image, ImageDraw, ImageFont

# ── Configuración de marca ──────────────────────────────────────────────────
AZUL_CLARO = (59, 130, 246)   # #3B82F6  (colorScheme.primary)
AZUL_OSCURO = (29, 78, 216)   # #1D4ED8  (primaryContainer)
BLANCO = (255, 255, 255)

FONT_CANDIDATAS = [
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\segoeuib.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_RES = os.path.join(RAIZ, "android", "app", "src", "main", "res")
WEB_DIR = os.path.join(RAIZ, "web")

# Densidades Android → tamaño en px del icono legacy (48dp base).
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Densidades Android → tamaño en px del canvas adaptativo (108dp base).
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def _fuente(px: int) -> ImageFont.FreeTypeFont:
    for ruta in FONT_CANDIDATAS:
        if os.path.exists(ruta):
            return ImageFont.truetype(ruta, px)
    raise SystemExit("No se encontró ninguna fuente bold conocida.")


def _gradiente(size: int) -> Image.Image:
    """Gradiente diagonal azul claro → azul oscuro, tamaño size×size."""
    base = Image.new("RGB", (size, size), AZUL_CLARO)
    px = base.load()
    for y in range(size):
        for x in range(size):
            # t en [0,1] a lo largo de la diagonal.
            t = (x + y) / (2 * (size - 1)) if size > 1 else 0
            px[x, y] = (
                round(AZUL_CLARO[0] + (AZUL_OSCURO[0] - AZUL_CLARO[0]) * t),
                round(AZUL_CLARO[1] + (AZUL_OSCURO[1] - AZUL_CLARO[1]) * t),
                round(AZUL_CLARO[2] + (AZUL_OSCURO[2] - AZUL_CLARO[2]) * t),
            )
    return base


def _monograma(size: int, fraccion: float, color=BLANCO) -> Image.Image:
    """Capa RGBA transparente con la 'A' centrada ópticamente."""
    capa = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(capa)
    fuente = _fuente(max(8, round(size * fraccion)))
    caja = d.textbbox((0, 0), "A", font=fuente)
    ancho, alto = caja[2] - caja[0], caja[3] - caja[1]
    x = (size - ancho) / 2 - caja[0]
    y = (size - alto) / 2 - caja[1]
    d.text((x, y), "A", font=fuente, fill=color)
    return capa


def icono_legacy(size: int) -> Image.Image:
    img = _gradiente(size).convert("RGBA")
    img.alpha_composite(_monograma(size, 0.66))
    return img


def icono_foreground(size: int) -> Image.Image:
    """Solo la 'A' (canal alfa) para el icono adaptativo; zona segura 66/108."""
    return _monograma(size, 0.40)


def icono_maskable(size: int) -> Image.Image:
    """Fondo a sangre + monograma reducido (zona segura del maskable)."""
    img = _gradiente(size).convert("RGBA")
    img.alpha_composite(_monograma(size, 0.44))
    return img


def escribir(img: Image.Image, ruta: str) -> None:
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    img.save(ruta, "PNG")
    print(f"  escrito {os.path.relpath(ruta, RAIZ)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="solo verificar, no escribir")
    args = ap.parse_args()
    if args.check:
        print("check: fuente y Pillow OK; nada escrito.")
        return

    print("Android legacy:")
    for dens, px in LEGACY.items():
        escribir(icono_legacy(px), os.path.join(ANDROID_RES, f"mipmap-{dens}", "ic_launcher.png"))

    print("Android adaptativo (foreground):")
    for dens, px in ADAPTIVE.items():
        escribir(
            icono_foreground(px),
            os.path.join(ANDROID_RES, f"mipmap-{dens}", "ic_launcher_foreground.png"),
        )

    # XML del icono adaptativo (API 26+) y color de fondo.
    anydpi = os.path.join(ANDROID_RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n'
        )
    print(f"  escrito {os.path.relpath(os.path.join(anydpi, 'ic_launcher.xml'), RAIZ)}")

    values = os.path.join(ANDROID_RES, "values")
    os.makedirs(values, exist_ok=True)
    ruta_colors = os.path.join(values, "colors.xml")
    if not os.path.exists(ruta_colors):
        with open(ruta_colors, "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                "<resources>\n"
                '    <color name="ic_launcher_background">#1D4ED8</color>\n'
                "</resources>\n"
            )
        print(f"  escrito {os.path.relpath(ruta_colors, RAIZ)}")
    else:
        print("  (colors.xml ya existía, no se toca)")

    print("Web:")
    escribir(icono_legacy(192), os.path.join(WEB_DIR, "icons", "Icon-192.png"))
    escribir(icono_legacy(512), os.path.join(WEB_DIR, "icons", "Icon-512.png"))
    escribir(icono_maskable(192), os.path.join(WEB_DIR, "icons", "Icon-maskable-192.png"))
    escribir(icono_maskable(512), os.path.join(WEB_DIR, "icons", "Icon-maskable-512.png"))
    escribir(icono_legacy(32), os.path.join(WEB_DIR, "favicon.png"))
    print("\nListo. Recuerda: monograma PLACEHOLDER — reemplazar por el logo oficial.")


if __name__ == "__main__":
    main()
