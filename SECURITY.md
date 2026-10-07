# Política de seguridad

## Modelo de confianza

Beliber tiene tres transportes con garantías distintas:

| Transporte | Confianza |
| --- | --- |
| **Host autoritativo** (`game/server/host.gd`, :7779) | El servidor valida jugadas con `match_legal`, resuelve efectos y es la fuente de verdad de reloj, tablas, resign y ladder. |
| **Relay WS** (`server/relay.py`, :7778) | Retransmisión sin validación de reglas. El cliente **nunca aplica** payloads remotos directamente: casa `from`/`to`/`second` contra las legales locales e ignora campos de efecto falsificados. Pensado para grupos de confianza. |
| **ENet LAN** (:7777) | Igual modelo que el relay (mismo `match_legal` local). Para red local. |

Identidad: el `pid` del cliente es autodeclarado, pero el host autoritativo
lo vincula a un **token** emitido por él (`id_tok`/`id_err`) — declarar el
pid de otro sin su token degrada la sesión a invitado sin rating. Esto
protege el ELO, **no** es autenticación de cuentas: no hay cuentas.

## Superficie defendida (ya implementado)

- Límites de tamaño y ráfaga de mensajes en ambos servidores.
- Validación de tipos de payload antes de dispatch.
- Clamp de opciones de sala (`eq`, `stall`, `f`, `clock`) en el host.
- Tokens de rejoin no predecibles (Crypto/secrets); el hueco libre de una
  sala solo lo ocupa quien presenta el token correcto.
- Chat acotado a 200 caracteres; el nick es solo display.
- Escrituras de stats/ratings atómicas (con fallback si el rename falla).
- Sin secretos en el repo: el único secreto local es el token del ladder,
  que vive en `user://` (fuera del árbol del proyecto).

## Alcance y mitigaciones

- El relay **no** valida reglas: dos clientes modificados podrían jugar con
  efectos inventados entre sí. Mitigación por diseño: el receptor recalcula
  la jugada legal; lo que no casa se rechaza.
- **Sybil en el ladder:** el pid+token hace del token la credencial real
  (equivalente a cuenta anónima). Se puede crear pids nuevos, pero el
  anti-farming mitiga el valor: partidas de <4 plies no mueven ELO y
  el rating requiere ambos jugadores autenticados. Un ladder público con
  reputación fuerte necesitaría cuentas con correo/OAuth — fuera de
  scope actual por diseño.
- **TLS:** soportado nativamente con `BELIBER_TLS_CERT`/`BELIBER_TLS_KEY`
  → `wss://`. Sin esas vars sirve `ws://` plano (LAN/grupos de
  confianza). Cliente: `wss://` en la URL; `BELIBER_TLS_INSECURE=1`
  permite probar con cert autofirmado.
- Handshake TLS se hace al aceptar la conexión (bloqueante por
  conexión, sin efecto práctico a este volumen).

## Reportar vulnerabilidades

Abre un issue etiquetado `security` (sin detalles sensibles públicos) o
contacta al mantenedor por privado. Incluye: componente, impacto, pasos de
reproducción. Se agradecen PoC contra los tests (`server/test_*.py` cubren
los paths hostiles: payload malformado, resync falsificado, flood).
