# Automatiza el ciclo de release (checklist §13):
#   powershell tools/release.ps1 0.2.0
# 1) bumpea config/version en project.godot + VERSION en host.gd
# 2) exige que CHANGELOG tenga sección para la versión
# 3) corre la batería completa
# 4) commit + tag anotado
param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "version '$Version' no es SemVer" }
if (-not (Select-String -Path CHANGELOG.md -Pattern "## \[?$Version" -Quiet)) {
    throw "CHANGELOG.md no tiene sección para $Version — escríbela primero"
}

# bump en los dos puntos que llevan versión explícita
(Get-Content game\project.godot -Raw) `
  -replace 'config/version="[^"]*"', "config/version=`"$Version`"" |
  Set-Content game\project.godot -NoNewline -Encoding UTF8
(Get-Content game\server\host.gd -Raw) `
  -replace 'const VERSION := "[^"]*"', "const VERSION := `"$Version`"" |
  Set-Content game\server\host.gd -NoNewline -Encoding UTF8

powershell -ExecutionPolicy Bypass -File tools\test_all.ps1
if ($LASTEXITCODE -ne 0) { throw "suite con fallos — no se publica" }

git add -A
git commit -m "release: v$Version"
git tag -a "v$Version" -m "v$Version"
Write-Output "== v$Version commiteado y taggeado — push con: git push --follow-tags =="
