# Runbook — operación del host autoritativo

## Arranque

```bash
# ws:// (LAN / detrás de proxy con TLS)
godot --headless --path game -s res://server/host.gd -- 7779

# wss:// (TLS nativo)
BELIBER_TLS_CERT=/path/cert.pem BELIBER_TLS_KEY=/path/key.pem \
  godot --headless --path game -s res://server/host.gd -- 7779
```

Logs a stdout. Arranque OK si aparece `Beliber host en ws[s]://…
(err=0)`.

## Monitorización

- **Health:** WS `{"op":"ping"}` → `{"op":"pong","rooms":N,"queue":M}`
  (no necesita sala — monitorizable con cualquier cliente WS).
- **Heartbeat:** cada 60 s el log imprime
  `stats rooms=… peers=… pending=… queue=… msgs/min=…`.
- **Señales de alerta prácticas:**
  - `rooms` o `peers` pegados al cap (500/512) sostenido → flood o
    salas sin liberar (revisar TTL).
  - `msgs/min` extremo con pocas salas → spam (rate-limits activos:
    32 pkt/iter, 64 KB).
  - `pending` alto sostenido → handshakes colgados (slowloris ya
    mitigado a 5 s).

## Estado persistente

En `user://` de Godot (`%APPDATA%/Godot/app_userdata/Beliber` en
Windows, `~/.local/share/godot/app_userdata/Beliber` en Linux):

- `beliber_ratings.json` — ELO del ladder.
- `beliber_idtokens.json` — tokens pid↔token (credenciales de
  identidad; **tratar como secretos**).

Cada escritura es atómica y deja `.bak` con la última versión buena.

## Backup / restauración

- **Backup** (RPO = última escritura): copiar los dos JSON (y sus
  `.bak` opcionales) con el host parado o encendido — son atómicos.
- **Restauración:** parar el host → copiar los JSON de vuelta →
  arrancar. Si el fichero principal está corrupto, copiar el `.bak`
  encima.
- **RTO:** segundos — el host no necesita estado adicional.

## Incidentes comunes

| Síntoma | Acción |
|---|---|
| `err=22` al arrancar | Puerto ocupado — matar proceso previo o cambiar el puerto (`-- NNNN`). |
| `err=32` u otro | Ver `host_out`/`host_err`; el puerto se parsea de `get_cmdline_user_args` (tras `--`). |
| Ladder vacío tras migrar host | Restaurar `beliber_idtokens.json` — sin él los pid registrados no autentican. |
| Jugadores quejas de desconexión | El cliente auto-reintenta 3× (2/6/10 s) con rejoin; pedir el código de sala si agotó reintentos. |

## Rollback de versión

`git checkout vX.Y.Z` — las reglas del motor son data-driven y el
protocolo es estable dentro de una major (ver versionado en
CONTRIBUTING.md).
