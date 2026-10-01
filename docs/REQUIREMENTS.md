# Requisitos y trazabilidad

Requisitos verificables. Cada uno enlaza a su verificación (suite de
tests o documento). IDs estables — no renumerar.

## Funcionales (reglas del juego)

| ID | Requisito | Verificación |
|---|---|---|
| F-01 | Las 7 facciones despliegan y se mueven según las hojas (patrones por casilla, efectos: push/attract/immob/traverse/jump/Aquonte/cadena) | `tests/run_tests.gd` (batería por facción), `tests/playthrough.gd` |
| F-02 | Victoria por captura del líder; tablas por repetición, acuerdo y anti-stall | run_tests.gd; resign/draw en `test_relay.py`/`test_host.py` |
| F-03 | Reglas especiales: enroque, al paso, doble apertura Humenex, Consorte, Aquonte, encadenamiento Tritón | run_tests.gd (regresiones dedicadas) |
| F-04 | Guardar/cargar partida (JSON versionado) y BEL-FEN/ARMY | e2e.gd, save/load tests |
| F-05 | Editores de pieza, ejército y posición reprogramables con vista previa de movimientos | `_smoke.gd`, piece_editor/army_builder/pos_editor |
| F-06 | IA por niveles y estilos; IA-vs-IA; hints | playthrough.gd, bot.gd |
| F-07 | Modo Run roguelike + puzzles diarios + Rush | puzzles.gd, `_smoke.gd` |
| F-08 | Online: salas por código + matchmaking + rejoin + chat, por ENet/relay/host | test_relay.py, test_host.py, e2e_net.gd |
| F-09 | Host autoritativo valida jugadas, reloj y fin de partida; ladder ELO | test_host.py, test_ladder.py |
| F-10 | Auto-rejoin tras caída (3 intentos, backoff) | `net_client._retry` + test_load.py |

## No funcionales

| ID | Requisito | Objetivo | Verificación |
|---|---|---|---|
| NF-01 | Jugable a 60 fps en escritorio modesto | 8×8, ≤64 sprites/casilla | implícito en e2e/UX; perfilable con Godot |
| NF-02 | Arranque headless testable en CI | <30 s por suite | ci.yml |
| NF-03 | Salvaguarda íntegra ante cortes | escritura atómica + `.bak` | stats_store.atomic_write |
| NF-04 | Superficie de red acotada | 512 conex, 500 salas, 32 pkt/iter, 64 KB/msg, chat 200, TTL 4 h | host.gd consts + test_load.py |
| NF-05 | Sin secretos en repo | scan en cada push | ci.yml job `secrets` |
| NF-06 | Deps pineadas y auditadas | `requirements.txt` + pip-audit + SBOM | ci.yml |
| NF-07 | ELO no farmeable trivialmente | ≥4 plies, ambos autenticados (pid+token) | test_ladder.py |
| NF-08 | Cifrado disponible | `wss://` con `BELIBER_TLS_*` | verificado e2e manual; host.gd |
| NF-09 | Sin perdida de estado del host | ratings/tokens atómicos + .bak | test_host.py (check .bak) |
| NF-10 | Accesibilidad básica | marcas por forma+color, coordenadas, "!" amenazas | board_view.gd / e2e |
| NF-11 | Reconexión tolerante | rejoin token + resync + auto-retry | test_relay/test_host/e2e_net |
| NF-12 | Ventana pequeña usable | auto-fit <536 px | board_view.gd auto-fit |

## Trazabilidad de tests

| Suite | Cubre |
|---|---|
| `tests/run_tests.gd` | F-01..F-04, NF-03 (reglas + persistencia + regresiones) |
| `tests/playthrough.gd` | F-01, F-06 (partidas completas bot-vs-bot) |
| `tests/_smoke.gd` | F-05, F-07 (UI smoke: draft, editores, puzzles) |
| `tests/e2e.gd` | F-02, F-04 (partida por clicks) |
| `tests/e2e_net.gd` | F-08 (2 clientes × relay) |
| `server/test_relay.py` | F-08, NF-11 (rejoin, resync, hostility) |
| `server/test_host.py` | F-09, NF-04..09, NF-11 (árbitro, ping, .bak) |
| `server/test_ladder.py` | F-09, NF-07 (ELO, id_tok/id_err) |
| `server/test_load.py` | NF-04, NF-11 (capacidad: 60 conns, 20 salas) |
