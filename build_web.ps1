# build_web.ps1 — Build estandarizado de Flutter Web para GitHub Pages.
# Uso:  .\build_web.ps1   (desde la carpeta adrialga_frontend)
$ErrorActionPreference = "Stop"

$BaseHref = "/ferreteria-adrialga-frontend/"

Write-Host "=== Build Web Ferreteria Adrialga ===" -ForegroundColor Cyan

Write-Host "[1/4] flutter clean..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean fallo" }

Write-Host "[2/4] flutter pub get..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get fallo" }

Write-Host "[3/4] flutter build web --release --base-href $BaseHref ..." -ForegroundColor Yellow
flutter build web --release --base-href $BaseHref
if ($LASTEXITCODE -ne 0) { throw "flutter build web fallo" }

Write-Host "[4/4] Verificacion de artefactos..." -ForegroundColor Yellow
$webDir = Join-Path $PSScriptRoot "build\web"
$requisitos = @("index.html", "main.dart.js", "manifest.json", "flutter_bootstrap.js")
foreach ($f in $requisitos) {
    if (-not (Test-Path (Join-Path $webDir $f))) {
        throw "FALLO: no se encontro el artefacto requerido '$f' en build\web"
    }
}

$index = Get-Content (Join-Path $webDir "index.html") -Raw
if ($index -notmatch [regex]::Escape("<base href=`"$BaseHref`">")) {
    throw "FALLO: index.html no contiene <base href=`"$BaseHref`">"
}

$tamanoMB = [math]::Round((Get-ChildItem $webDir -Recurse | Measure-Object Length -Sum).Sum / 1MB, 2)
Write-Host ""
Write-Host "BUILD WEB CORRECTO" -ForegroundColor Green
Write-Host "  Salida : $webDir"
Write-Host "  Tamano : $tamanoMB MB"
Write-Host "  Base   : $BaseHref"
Write-Host ""
Write-Host "Siguiente paso: copiar el contenido de build\web a la rama gh-pages (o carpeta docs/) del repo ferreteria-adrialga-frontend."