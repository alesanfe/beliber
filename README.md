# Beliber

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf)
![Version](https://img.shields.io/badge/version-0.1.1-green)

Juego de estrategia por turnos **asimétrico** tipo ajedrez, implementado en
**Godot 4**: 7 facciones con piezas, efectos y reglas de victoria propias
(empujar, atraer, atravesar, inmovilizar, salto de Aquonte, doble apertura
Humenex, Consorte que copia la gama de lo capturado…), editores de piezas y
ejércitos reprogramables, IA con niveles y estilos, modo Run roguelike,
puzzles con Rush, y juego en red por ENet, relay WebSocket o host
autoritativo con ladder ELO.

## Estado

Funcional y jugable. Motor completo y testeado; UI pulida con overlays de
análisis, replay, hints y post-partida. Arte temporal (glifos de ajedrez +
colores de facción); los sprites definitivos están pendientes.

## Qué incluye / qué no

- **Incluye:** partidas locales hotseat, vs IA, IA-vs-IA y online; editor de
  piezas (patrón de movimiento por casillas), editor de ejército y de
  posición (BEL-FEN), modo draft, Run con bendiciones, puzzles diarios y
  Rush, logros/XP/estadísticas, reloj Fischer, undo, replay, exportación de
  log, matchmaking por cola y salas con código, reconexión, chat, ladder ELO.
- **No incluye:** arte final, sonido completo (beeps de sintetizador),
  matchmaking público con cuentas, despliegue a stores.

## Ejecutar

Requisito: **Godot 4.7+** (probado con 4.7.2 stable).

```
godot --path game            # jugar
```

## Tests

```
godot --headless --path game -s res://tests/run_tests.gd     # motor + regresiones
godot --headless --path game -s res://tests/playthrough.gd   # partidas bot-vs-bot
godot --headless --path game -s res://tests/_smoke.gd        # smoke de UI
godot --headless --path game -s res://tests/e2e.gd           # partida por clicks
```

Red (`pip install -r server/requirements.txt` primero; los servidores
levantados):

```
python server/relay.py                                      # relay :7778
godot --headless --path game -s res://server/host.gd -- 7779 # host autoritativo
python server/test_relay.py && python server/test_host.py \
    && python server/test_ladder.py
godot --headless --path game -s res://tests/e2e_net.gd      # 2 clientes x relay
```

Para aislar los datos de tests: `BELIBER_CFG`, `BELIBER_SAVE`,
`BELIBER_EXPORT`, `BELIBER_RATINGS`, `BELIBER_TOKENS` (ver `game/README.md`).

## Estructura

```
beliber/
├── game/            # proyecto Godot (src/, scenes/, tests/, server/host.gd)
├── server/          # relay.py + PROTOCOL.md + tests Python
├── tools/           # recortes/escaneos de las hojas de diseño
├── COMO_FUNCIONA.md # reglas completas del juego (leyenda + facciones)
├── COMPETENCIA.md   # comparativa con juegos de referencia
└── game/README.md   # guía técnica (arquitectura, tests, red)
```

## Operar el host autoritativo (opcional)

```
godot --headless --path game -s res://server/host.gd -- 7779
```

- **Health check:** WS `{"op":"ping"}` → `{"op":"pong","rooms":N,"queue":M}`.
  Además el host imprime un heartbeat/minuto:
  `stats rooms=N peers=N pending=N queue=N msgs/min=N`.
- **TLS:** con `BELIBER_TLS_CERT` + `BELIBER_TLS_KEY` apuntando a un
  cert+clave PEM el host sirve `wss://` nativo. Cliente: URL
  `wss://…`; `BELIBER_TLS_INSECURE=1` omite la validación para probar
  con certs autofirmados.
- **Estado persistente** (`user://` de Godot, ver `game/README.md`):
  `beliber_ratings.json` + `beliber_idtokens.json` — cada escritura
  es atómica y mantiene `.bak` (última versión buena). **Backup =
  copiar esos archivos**; restaurar = devolverlos antes de arrancar.
- **Rollback de versión:** `git checkout vX.Y.Z` (tags SemVer).
- **Límites ya activos:** `MAX_ROOMS` 500, 512 conexiones, 5 s de
  handshake, 32 paquetes/iter y 64 KB/mensaje, chat 200 chars, salas
  TTL 4 h, partidas de <4 plies no cuentan ELO.

## Documentación

- Arquitectura: `docs/ARCHITECTURE.md`
- Reglas del juego: `COMO_FUNCIONA.md`
- Protocolo de red: `server/PROTOCOL.md`
- Guía técnica: `game/README.md`
- Referencias de diseño: `COMPETENCIA.md`
- Decisiones de arquitectura: `docs/decisions/` (ADR)
- Requisitos trazables: `docs/REQUIREMENTS.md`
- Modelo de amenazas: `docs/THREAT_MODEL.md`
- Runbook del host: `docs/operations/RUNBOOK.md`
- Inventario de dependencias: `DEPENDENCIES.md`

## Contribuir

Ver `CONTRIBUTING.md`. Bugs y propuestas: issues del repo.

## Seguridad

Ver `SECURITY.md` — modelos de confianza por transporte y cómo reportar.

## Licencia

MIT — ver `LICENSE`.
