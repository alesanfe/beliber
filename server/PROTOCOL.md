# Protocolo de red de Beliber

Tres transportes, mismos conceptos: **sala** de 2 lados (0=host/creador,
1=invitado), **cfg** con la configuración efectiva de la partida y
**jugadas** como diccionarios del motor (`{from,to,captures,…}` más
`second` para el 2º tramo encadenado del Tritón).

## `cfg` (configuración efectiva, va en `room`/`start`/`resync`)

```json
{"f0":0,"eq0":0,"f1":0,"eq1":0, "mid":false, "stall":0, "clock":0,
 "rows0":[...], "rows1":[...], "ovr": {"humenex": {"P": {...}}}}
```

- `f*`/`eq*` índices de facción y equipo; `mid` línea media,
  `stall` límite anti-stall (0=off), `clock` índice de
  `TurnManager.CLOCK_CHOICES`.
- `rowsN`: filas de despliegue **efectivas** del equipo elegido — el
  rival las inyecta con `ArmyBuilder.inject_at(eq)` aunque no tenga el
  archivo local.
- `ovr`: overrides del editor de piezas por facción (unión de ambos
  lados); se aplican con `PieceEditor.apply_dict` **antes** de
  desplegar.
- `pid`: id persistente del jugador (ConfigFile `net.pid`) — clave del
  rating del ladder (el nick es solo display).
- `tok`: token de identidad del ladder (ConfigFile `net.tok`, solo
  host autoritativo). El host emite uno la primera vez que ve un pid
  (`S→C id_tok{tok}`) y el cliente lo reenvía en create/join/queue.
  Reclamar un pid registrado con token incorrecto → `id_err` y la
  sesión juega como invitado sin rating (ya no se puede robar el ELO
  ajeno declarando su pid). Sin token: pid nuevo queda registrado;
  pid existente queda en invitado.

## Relay WebSocket — `ws://…:7778` (`server/relay.py`, sin árbitro)

C→S: `create{cfg}` · `join{code,ovr}` · `rejoin{code,side,token}` ·
`queue{prefs{f,eq,clock,mid,stall,rows,ovr}}` · `dequeue` ·
`move{mv}` · `chat{text}` · `leave`.

S→C: `room{code,side,token,cfg}` · `peer{side}` ·
`start{cfg?}` (join: cfg final con `ovr` fusionado a ambos; en queue
la cfg ya llegó en `room`) · `queued{n}` · `dequeued` · `move{mv,n}` ·
`resync{moves,side}` · `offline{on}` · `over{reason:"leave"}` ·
`chat{text}` · `err{msg}`.
(**Sin** `hello` — ese saludo solo lo envía el host autoritativo y es
lo que marca `ws_auth` en el cliente.)

**Modelo de confianza:** el relay retransmite, apenas valida. El
cliente **nunca aplica el dict remoto**: `TurnManager.match_legal`
casa from/to(/second_to) contra las legales locales y juega la
variante LOCAL. Un `captures`/`push` falsificado no tiene efecto.
`resign` se interpreta en vivo como `1 - side_local`. El relay sí
valida que `mv` sea Dictionary, **estampa `side` con el emisor real**
en resign/draw (un `side` falsificado rendía al rival en resync) y
marca la sala como terminada tras resign/draw-accept (jugadas
posteriores se rechazan, no se archivan). El `resync` aplica
`match_legal` entrada a entrada, exige una oferta previa para un
`accept` de tablas y usa el `side` estampado.

## Host autoritativo — `ws://…:7779` (`game/server/host.gd`)

C→S: `create{cfg,name,pid,tok}` · `join{code,name,pid,tok,ovr}` ·
`rejoin{code,side,token}` · `queue{name,pid,tok,prefs}` · `dequeue` ·
`play{from:{x,y},to:{x,y},second_to?} | {resign:true} |
{draw:"offer|accept|decline"}` · `leave` · `chat{text}` · `ladder` ·
`ping` (health check → `pong{rooms,queue,v}`).

S→C: `hello{v}` (v = versión desplegada) · `room{code,side,token,cfg}` (la cfg SIEMPRE va en
`room`; `resync` no la repite) · `peer{side}` · `start{cfg?}` ·
`move{mv,n}` (jugada **resuelta**, a ambos — echo autoritativo) ·
`resync{moves,side}` · `offline{on}` · `over{winner|reason}` ·
`rating{you}` · `ladder{rows}` · `id_tok{tok}` / `id_err` (auth del
ladder) · `draw_offer`/`draw_decline` · `err{msg}` ·
`queued`/`dequeued` · `pong{rooms,queue,v}`.

El servidor mantiene un `TurnManager` por sala: el cliente envía solo
intención (`from`/`to`/`second_to`), el host resuelve la jugada legal
y difunde el resultado. `resign`/`draw` se archivan en `r.moves` para
que `resync` reconstruya el final; un `leave` en curso cuenta como
derrota. El reloj es autoritativo (tick del host → `flag`).

## ENet (LAN, `--path game`, puerto configurable)

El host crea `TurnManager` local; las jugadas viajan como dict RPC al
cliente, que las valida con `match_legal` igual que en el relay.
La cfg viaja una vez en `_rpc_config` (incluye `rows`/`ovr` del host).
Salidas especiales: `{"resign":true}`, `{"draw":"offer|accept|decline"}`.
No hay rejoin ni ladder.

## Códigos y tokens

Sala: 4 letras/alfabeto Crockford vía `Crypto`. Token de rejoin: 24
bytes aleatorios por lado — caducan con la sala (TTL 4 h sin conexión).

**Auto-rejoin del cliente:** si el socket WS cae en mitad de partida,
`net_client` reintenta `rejoin` automáticamente (3 intentos, backoff
~2s/6s/10s) usando la URL recordada — la pantalla online ya está
destruida en ese punto, así que sin esto la partida era irrecuperable.
Un `err` o un `room` recibido desarma los reintentos.
