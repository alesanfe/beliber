# Modelo de amenazas

Scope: juego local + host autoritativo autoalojado + relay opcional.
Atacante externo con red al servidor; también un jugador con cliente
modificado. Fuera de scope: compromiso del propio servidor.

## Activos

- **A1** Integridad de la partida (jugadas legales, reloj, resultado).
- **A2** Integridad del ladder ELO (quién es quién, partidas reales).
- **A3** Disponibilidad del host/relay (no tumbado por flood).
- **A4** Datos persistentes: ratings, tokens, saves (no corromperse ni
  filtrarse).
- **A5** Secreto: token de identidad del ladder por jugador.

## Amenazas y mitigaciones

| Amenaza | Activo | Mitigación implementada |
| --- | --- | --- |
| Payload malformado → crash | A1/A3 | validación `typeof`/Dictionary en cliente y ambos servidores; `match_legal` solo casa from/to |
| Efectos falsificados (captures, push) en `move` | A1 | receptor recalcula legalidad; host es autoritativo y resuelve él mismo |
| `side` falsificado en resync/resign | A1 | relay estampa `side` con el emisor real; cliente ignora `mv.side` no estampado |
| `accept` de tablas sin oferta | A1 | oferta previa requerida en relay y host |
| Robar el pid ajeno → corromper ELO | A2 | `id_tok` secreto por pid; sin token → `id_err` + invitado |
| Farming con smurfs (resigns en masa) | A2 | `MIN_RATED_PLIES` (4) + ambos pid autenticados requeridos |
| Flood de conexiones/mensajes | A3 | 512 conexiones, handshake 5 s, 32 pkt/iter, 64 KB/msg, `MAX_ROOMS` 500, cola de sockets muertos limpiada |
| Handshake WS colgado (slowloris) | A3 | deadline 5 s en `pending` |
| Salas zombies | A3 | TTL 4 h sin conexión, `leave` inmediato libera |
| Corrupción de ratings/saves por corte | A4 | `atomic_write` (tmp+rename, fallback) + `.bak` |
| Tests tocan perfil real | A4 | env `BELIBER_*` a %TEMP%, `StatsStore.disabled` |
| Token de rejoin adivinable | A5 | 24 bytes `Crypto`/secrets por lado, caduca con la sala |
| Token del ladder en tránsito | A5 | `wss://` nativo con `BELIBER_TLS_CERT/KEY` |
| MitM en `ws://` plano | A2/A5 | mitigado por TLS opcional; documentado en SECURITY.md |
| DoS por `create` masivo | A3 | `MAX_ROOMS` + cap global de conexiones |
| Fuerza bruta de código de sala | — | 4 letras Crockford ≈ 331 k combos; sin límite de intentos documentado → asumido bajo (LAN/self-host) |

## Riesgo residual aceptado

- El relay no árbitra reglas: dos clientes acordados pueden jugar con
  reglas inventadas entre sí — el receptor honesto siempre valida.
- Chat sin moderación: 200 chars, solo hacia la sala propia.
- Sin cuentas con contraseña/email: pid+token = credencial anónima
  suficiente para el scope hobby; documentado en SECURITY.md.
- Intentos de join a sala inexistente no tienen rate-limit por IP
  (quedaría para el proxy si se publica en internet).
