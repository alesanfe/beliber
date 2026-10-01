#!/usr/bin/env bash
# Ejecuta TODA la batería de verificación — el único comando de tests.
# Uso: tools/test_all.sh   (env GODOT=<ruta> para el binario)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export BELIBER_RATINGS="${TMPDIR:-/tmp}/beliber_test_ratings.json"
export BELIBER_TOKENS="${TMPDIR:-/tmp}/beliber_test_idtokens.json"
fail=0

if command -v gdlint >/dev/null 2>&1; then
    echo "=== gdlint ==="
    gdlint game/src game/server game/tests || fail=$((fail+1))
fi

for s in run_tests playthrough _smoke e2e; do
    echo "=== game/tests/$s.gd ==="
    "$GODOT" --headless --path game -s "res://tests/$s.gd" || fail=$((fail+1))
done

echo "=== relay (:7778) + host autoritativo (:7779) ==="
python server/relay.py & relay_pid=$!
"$GODOT" --headless --path game -s res://server/host.gd -- 7779 & host_pid=$!
trap 'kill $relay_pid $host_pid 2>/dev/null' EXIT
sleep 3
for t in test_relay test_host test_ladder test_load; do
    echo "=== server/$t.py ==="
    python "server/$t.py" || fail=$((fail+1))
done
echo "=== game/tests/e2e_net.gd ==="
"$GODOT" --headless --path game -s res://tests/e2e_net.gd || fail=$((fail+1))

if [ "$fail" -eq 0 ]; then echo "== SUITE COMPLETA: OK =="
else echo "== SUITE COMPLETA: $fail suites con fallos =="; fi
exit $fail
