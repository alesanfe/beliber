# Changelog

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).

## [Unreleased]

### Corregido (auditoría interna, ~45 hallazgos)

- **Motor:** save/load ya no re-suma la posición actual en `pos_counts`
  (tablas espurias por triple repetición); `load_game` valida `current`,
  relojes, capturas anidadas y rechaza versiones de formato desconocidas;
  `apply()` marca `has_moved`/`last_move` en el destino del 2º tramo de
  jugadas encadenadas; al paso exige casilla destino vacía; despliegue con
  filas fuera de rango se clampea; `describe()` muestra capturas del segundo
  tramo; `match_legal` discrimina captura vs empuje y valida la forma del
  payload; detección de líderes ausentes al iniciar; anti-stall cuenta
  **turnos** (no jugadas); `is_attacked` ignora piezas inmovilizadas (no
  pueden capturar, luego no amenazan para enroque/jaque).
- **Bot:** pasar turno reproduce la semántica real del motor; los estilos
  evalúan el aterrizaje real en jugadas encadenadas.
- **Online:** sockets/peers se cierran al salir a partida local o a un
  editor; dispatch valida tipos; `resync` no fía `side` falsificable;
  `accept` de tablas exige oferta previa; `sync_pending` se libera en
  cierre/fin; timeouts de conexión WS; relay corrige race de desconexión
  (solo limpia el asiento si el socket es el mismo), marca salas terminadas
  tras resign/draw y rechaza `mv` no-Dictionary; host clampea
  `eq`/`stall`/`f`, valida `side` en chat, limpia la cola de sockets
  muertos, cierra el socket viejo al rejoin y reencola al emparejado si el
  `create` falla; `join` a sala inexistente ya no mata el socket.
- **Identidad del ladder (N19):** el host emite un token por `pid`
  (`id_tok`); reclamar un pid ajeno sin token → `id_err` y la sesión juega
  como invitado sin rating.
- **UI/UX:** `_run_next` preserva facción/reloj/reglas del jugador (las
  bendiciones ya aplican en combate 2+); rendirse/tablas/sugerir bloqueados
  en IA-vs-IA y fuera de turno online; diálogos validan `tm` al confirmar;
  drag-drop respeta `confirm_moves`; sliders de zoom/animación reflejan el
  ajuste cargado; `_saved_opts` congelado también en draft y editor de
  posición; rematch conserva `chk_flip`; guardar partida bloqueado en
  online/run; partida cargada ya terminada muestra el resultado; mensajes
  de chat entrantes avisan con toast; las cadenas de 2º tramo muestran
  destinos (cian = 2º tramo, amarillo = solo 1º) con texto guía.
- **Tests aislados** del perfil real: `StatsStore.disabled` + variables
  `BELIBER_CFG`/`BELIBER_SAVE`/`BELIBER_EXPORT`/`BELIBER_RATINGS`/
  `BELIBER_TOKENS`.

### Añadido

- Puzzle Rush persiste el récord (`stats.rush_best`) con aviso de récord.
- Saves versionados (`"v": 1`).
- Cola de toasts apilados (máx. 4).
- Auto-encaje responsive: el tablero se reduce si la ventana es < ~536 px.
- Cobertura diferenciada por forma (J0 sólido / J1 anillo) y marcas de
  análisis con forma por color (accesibilidad).
- Confetti de victoria en el modal de fin de partida.
- `README.md` raíz, `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`,
  CI en GitHub Actions (syntax check + 8 suites + pip-audit),
  templates de issues/PR, CODEOWNERS, ADRs en `docs/decisions/`.
- Auto-rejoin del cliente WS: 3 reintentos con backoff tras caída en
  mitad de partida (antes era irrecuperable — la pantalla online ya
  está destruida).
- Host: `ping → pong{rooms,queue}` para health check, `MAX_ROOMS`
  (500) como cap de capacidad, heartbeat de métricas cada 60 s, y
  TLS nativo (`BELIBER_TLS_CERT`/`BELIBER_TLS_KEY` → `wss://`;
  cliente: `BELIBER_TLS_INSECURE=1` para autofirmados).
- Anti-farming ELO: partidas de <4 plies no mueven rating.
- Backups `.bak` automáticos en toda escritura atómica de datos.
- `server/test_load.py`: test de capacidad (60 conexiones, 20 salas,
  ráfaga) — incluido en CI.
- `DEPENDENCIES.md`, SBOM generado en CI, gitleaks en CI,
  `export_presets.cfg` (Windows+Web) y `release.yml` (builds + SHA256
  + SBOM + attestation SLSA en GitHub Releases).
- `docs/ARCHITECTURE.md` (mapa de capas y contratos), `docs/
  REQUIREMENTS.md` (trazabilidad), `docs/THREAT_MODEL.md`,
  `docs/operations/RUNBOOK.md`, `server/.env.example`.
- `config/version` en `project.godot`; `.gitattributes` (EOL=LF) y
  `.editorconfig` (tabs GDScript / espacios resto).
- Lint en CI: job `lint` con `py_compile`, bandit (seguridad) y
  `gdlint` (política propia en `gdlintrc`, 0 hallazgos); también
  integrado en `tools/test_all` cuando está disponible.
- `dependabot.yml` (pip + github-actions, semanal) y
  `scorecard.yml` (OpenSSF, activo al publicar el repo).
- Log de seguridad en el host (`sec:<evento>`: flood cerrado,
  paquete oversize, cap de salas, id_err) — grep-able, sin datos
  sensibles.
- `docs/DATA_MODEL.md`, `docs/PRIVACY.md`, `docs/operations/SLO.md`
  (SLI/SLO, RPO/RTO, alertas, capacidad verificada).
- Icono propio (`game/icon.png` + `.ico`): el ejecutable y la web ya
  no usan el genérico de Godot.
- `hello`/`pong` del host llevan `v` (versión desplegada —
  observabilidad).
- `BELIBER_SEED=<n>` fija el RNG del bot → tests y partidas vs IA
  reproducibles.
- `.well-known/security.txt` (RFC 9116), `docs/operations/INCIDENTS.md`
  (severidades, contención, postmortem), `.githooks/pre-commit`
  (opt-in: gdlint + py_compile + secretos) y `tools/release.ps1`
  (bump SemVer + suite completa + tag).

### Documentación

- `COMO_FUNCIONA.md`: interpretaciones de reglas confirmadas contra la
  hoja de la leyenda (Aquonte pivota sobre piezas enemigas; empujar/atraer
  no cuenta como "realizar un movimiento"; enroque de 1 paso imposible).
- `server/PROTOCOL.md`: `tok`/`id_tok`/`id_err`, estampado de `side`,
  semántica de tablas offer/accept/decline, modelo de confianza por
  transporte.
