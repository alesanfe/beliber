# Arquitectura

Beliber es un proyecto Godot 4 (`game/`) + un relay Python opcional
(`server/`). Todo GDScript es `class_name` global — sin autoloads ni
addons.

## Capas

```text
┌─ UI ──────────────────────────────────────────────────────────┐
│ main.gd (controlador raíz) · menu_screen · online_screen ·    │
│ profile_screen · game_hud · board_view · widgets · juice/fx · │
│ captured_tray · eval_bar · draft · puzzles · postgame ·       │
│ piece_editor · army_builder · pos_editor · guide              │
├─ Red ─────────────────────────────────────────────────────────┤
│ net_client (WS: relay+host) · net_codec · net_enet ·          │
│ sfx (beeps synth)                                             │
├─ Reglas ──────────────────────────────────────────────────────┤
│ turn_manager (turno/reloj/fin/historial/pos_counts) ·         │
│ move_gen (legales: casillas+slide+efectos+cadenas) ·          │
│ board_state (tablero 8×8, apply) · pieces_data (facciones)    │
├─ Servicio ────────────────────────────────────────────────────┤
│ stats_store (stats + atomic_write) · bot (IA por niveles) ·   │
│ icons (glifos+temas) · theme · smooth_scroll                  │
└───────────────────────────────────────────────────────────────┘
  server/host.gd   árbitro WS autoritativo (motor compartido)
  server/relay.py  relay puro (solo rettransmite)
```

## Contratos clave

- **Pieza** = dict `{def, owner, has_moved, immobilized, cells_override}`.
  `def` apunta a una `PieceDef` data-driven (`cells`, `slide`, `caps`,
  `cond`). Ver ADR-001.
- **Jugada** = dict `{from, to, captures, push, attract, immobilize,
  castle, second, …}` producido por `MoveGen.moves_for`/`all_moves`
  y aplicado por `BoardState.apply`/`TurnManager.play`.
- **`match_legal(intent) → jugada_local`** es la frontera de
  seguridad: jamás se aplica un dict de jugada remoto tal cual
  (ver ADR-002 / THREAT_MODEL).
- **cfg efectiva** (`{f0,eq0,f1,eq1,mid,stall,clock,rows0,rows1,ovr}`)
  viaja en `room`/`start` y fija facciones, despliegues y overrides
  de piezas — ver `server/PROTOCOL.md`.

## Estado persistente

`user://` de Godot (rutas override por env `BELIBER_*`):

| Archivo | Qué | Quién |
| --- | --- | --- |
| `beliber.cfg` | ConfigFile de ajustes + `net.pid`/`net.tok` | cliente |
| `beliber_save.json` | partida en curso (`"v":1`) | cliente |
| `beliber_stats.json` | XP, logros, rush_best | cliente |
| `beliber_ratings.json` | ELO ladder | host |
| `beliber_idtokens.json` | pid→token (secreto) | host |

Todas las escrituras pasan por `StatsStore.atomic_write`
(tmp+rename+fallback+`.bak`).

## Modos de juego y su árbitro

| Modo | Árbitro | Transporte |
| --- | --- | --- |
| Hotseat / vs IA / IA-vs-IA | TurnManager local | — |
| ENet LAN | host de la partida | ENet RPC :7777 |
| Sala relay | receptor recalcula | WS :7778 |
| Sala host / matchmaking | host.gd (autoritativo) | WS :7779 |

## Tests

`tests/run_tests.gd` (unitarios+regresiones), `playthrough.gd`,
`_smoke.gd` (UI), `e2e.gd` (clicks), `e2e_net.gd` (2 clientes),
`server/test_*.py` (relay, host, ladder, carga). Todo en CI:
`.github/workflows/ci.yml`.
