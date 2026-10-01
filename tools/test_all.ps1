# Ejecuta TODA la batería de verificación — el único comando de tests.
# Uso: powershell tools/test_all.ps1   (env GODOT=<ruta> para el binario)
$ErrorActionPreference = "Continue"
$godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
# aislamiento: ratings/tokens del host de prueba van a %TEMP%
$env:BELIBER_RATINGS = "$env:TEMP\beliber_test_ratings.json"
$env:BELIBER_TOKENS  = "$env:TEMP\beliber_test_idtokens.json"
$fail = 0

if (Get-Command gdlint -ErrorAction SilentlyContinue) {
    Write-Output "=== gdlint ==="
    gdlint game/src game/server game/tests
    if ($LASTEXITCODE -ne 0) { $fail++ }
}

foreach ($s in @("run_tests", "playthrough", "_smoke", "e2e")) {
    Write-Output "=== game/tests/$s.gd ==="
    & $godot --headless --path game -s "res://tests/$s.gd"
    if ($LASTEXITCODE -ne 0) { $fail++ }
}

Write-Output "=== relay (:7778) + host autoritativo (:7779) ==="
$relay = Start-Process -PassThru -NoNewWindow python `
    -ArgumentList "server/relay.py"
$hostP = Start-Process -PassThru -NoNewWindow $godot `
    -ArgumentList "--headless --path game -s res://server/host.gd -- 7779"
Start-Sleep 3
foreach ($t in @("test_relay", "test_host", "test_ladder", "test_load")) {
    Write-Output "=== server/$t.py ==="
    python "server/$t.py"
    if ($LASTEXITCODE -ne 0) { $fail++ }
}
Write-Output "=== game/tests/e2e_net.gd ==="
& $godot --headless --path game -s res://tests/e2e_net.gd
if ($LASTEXITCODE -ne 0) { $fail++ }

Stop-Process -Id $relay.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $hostP.Id -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output "== SUITE COMPLETA: OK ==" } else {
    Write-Output "== SUITE COMPLETA: $fail suites con fallos ==" }
exit $fail
