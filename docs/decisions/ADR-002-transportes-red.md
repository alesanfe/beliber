# ADR-002: Tres transportes online con modelos de confianza distintos

## Contexto

Las hojas no definen red; los competidores (Lichess, CEO) exigen
árbitro servidor, pero el coste de autoridad total en una app Godot
hobby es alto (hosting, TLS, cuentas).

## Decisión

Tres transportes con el **mismo protocolo JSON** y distinto modelo de
confianza, documentados en `server/PROTOCOL.md` y `SECURITY.md`:

1. **ENet LAN** (`net_enet.gd`, :7777): ambos confían; el cliente
   valida contra legales locales — spoofing de efectos inútil porque
   el receptor recalcula.
2. **Relay WS** (`server/relay.py`, :7778): retransmite sin reglas;
   el receptor solo aplica `from`/`to` si casa con una jugada legal
   local e ignora campos de efecto. Token de rejoin por sala.
3. **Host autoritativo** (`game/server/host.gd`, :7779): el servidor
   corre el motor y es la verdad: valida jugadas, resuelve tablas/
   resign/reloj/ladder, estampa `side` en resync y emite `id_tok`
   para vincular `pid` autodeclarado con un token de identidad.

La identidad del ladder usa **pid + token** (no contraseña): el pid es
autodeclarado pero declarar el de otro sin su token degrada a invitado.

## Alternativas

- Solo relay P2P: más simple pero sin árbitro → desyncs y trampa
  posibles; descartado tras comparar con competidores.
- Cuentas + wss en host: correcto para producción pública, pero exige
  infra y UX de login; documentado como gap conocido en SECURITY.md.

## Consecuencias

+ Cualquier jugador puede autoalojar el relay (`pip install
  websockets`; `python server/relay.py`).
+ El host autoritativo da ladder y validación real sin romper los
  otros transportes (mismo `net_client`).
- El relay no impide que un cliente modificado juegue con reglas
  inventadas *contra otro cliente modificado* — riesgo asumido.
- `ws://` sin TLS: para internet serio el host va detrás de proxy con
  `wss://`.
