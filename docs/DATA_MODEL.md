# Modelo de datos y persistencia

Sin base de datos: ficheros JSON/CFG en `user://` de Godot
(`%APPDATA%\Godot\app_userdata\Beliber` en Windows,
`~/.local/share/godot/app_userdata/Beliber` en Linux). Todas las
rutas son override por env `BELIBER_*` (ver `server/.env.example`) y
toda escritura es atómica con `.bak`.

## Cliente

### `beliber.cfg` (ConfigFile INI)

- `[net] pid` — id estable random del jugador (clave del ladder).
- `[net] tok` — token de identidad emitido por el host (secreto).
- `[ui]` zoom, animaciones, confirm_moves, board flip, etc.
- `[audio]` volumen/mute del beeper.

### `beliber_save.json` — partida en curso (`"v": 1`)

```json
{"v": 1, "state": {"board": ..., "last_move": ..., "pos_counts": null},
 "log": [...], "over": false, "winner": -1, "current": 0,
 "clock": {"t0":..., "t1":..., "inc":...}, "opts": {...}}
```

- `pos_counts` NO se persiste: se recalcula del log al cargar
  (evita doble conteo de la posición actual → tablas espurias).
- Versiones de `"v"` desconocidas → se rechazan (no migración
  silenciosa de datos corruptos).

### `beliber_stats.json`

`{xp, games, wins, faction_wins{...}, achievements{...},
rush_best, daily{date, done}, ...}` — acumulado del perfil local.

### BEL-FEN / BEL-ARMY (exports)

Strings importables/exportables de posición y ejército custom.

## Host (`server/host.gd`)

### `beliber_ratings.json`

```json
{"<pid>": {"elo": 1200, "games": 5, "wins": 3, "name": "nick"}}
```

`name` es solo display (el nick es suplantable); la clave es `pid`.

### `beliber_idtokens.json` — SECRETO

```json
{"<pid>": "<token 24 bytes>"}
```

Credencial de identidad del ladder. Sin este fichero los pid ya
registrados no autentican (quedan como invitados) — **restaurarlo
junto a ratings en cualquier migración de host**.

## Mensajes de red

Ver `server/PROTOCOL.md` — el protocolo JSON completo por
transporte (ENet / relay / host) con `cfg` efectiva, jugadas,
resync y ladder.
