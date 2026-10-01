# SLI / SLO — host autoritativo y experiencia de juego

Objetivos **proporcionales al contexto**: juego indie autoalojado, no
servicio financiero. Sirven para decidir si el host está sano y para
justificar límites en código.

## SLI y objetivos

| SLI | Medición | SLO |
|---|---|---|
| Health check | `ping` → `pong` | responde en <500 ms en LAN |
| Disponibilidad del host | proceso vivo + pong | 99 % mensual (autoalojado, sin HA) |
| Jugadas | `play` → `move`/`err` | <200 ms en LAN |
| Rooms activas | `pong.rooms` | cap 500 (`MAX_ROOMS`) |
| Conexiones | `pong` + heartbeat | cap 512 |
| Mensajes válidos | heartbeat `msgs/min` | sin objetivo — telemetría |
| Errores de protocolo | count de `err` | <5 % de mensajes (indicador) |
| Autosave cliente | `atomic_write` | 100 % atómico (tmp+rename+.bak) |

## Fiabilidad

- **RPO** (host): ratings/tokens → última escritura atómica (~0 s;
  se escriben tras cada resultado). `.bak` = última versión buena.
- **RTO** (host): arrancar `host.gd` tras restaurar los 2 JSON —
  minutos, sin migraciones.
- **Cliente:** un corte de red medio-partida se recupera con
  auto-rejoin (3 intentos, backoff) + `resync`; RTO percibido ≈ 10 s
  en el peor caso documentado.

## Capacidad objetivo (verificada en `server/test_load.py`)

- 60 conexiones concurrentes + 20 salas emparejadas + ráfaga
  ping/chat → host sigue respondiendo con `pong` correcto.
- Límites duros: 512 conexiones totales, 500 salas, 32 paquetes/
  iteración por peer, 64 KB por mensaje, 5 s handshake, chat 200
  chars, sala TTL 4 h vacía.

## Alertas sugeridas (si el host se monitoriza)

| Condición | Acción |
|---|---|
| `ping` sin `pong` >30 s | reiniciar proceso (no hay estado volátil que perder salvo salas activas) |
| `rooms` ≥ 450 | revisar flood / crecer el cap deliberadamente |
| `pending` alto sostenido | revisar origen (slowloris mitigado a 5 s) |
| disco <1 GB libre | los JSON son KB — alerta genérica de la máquina |

## Rollback

`git checkout vX.Y.Z` — protocolo y saves versionados dentro de una
major (ver CONTRIBUTING.md); sin migraciones destructivas.
