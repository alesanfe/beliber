# Atributos de calidad prioritarios

Declaración explícita de qué importa más en este proyecto y cómo se mide.
Una decisión que empeore un atributo `crítico` exige justificación en el PR.

## Prioridades

| Atributo | Prioridad | Objetivo | Medición | Umbral |
| --- | --- | --- | --- | --- |
| Corrección de reglas | crítica | Motor data-driven sin trampas | `run_tests` + `playthrough` + BEL-FEN round-trip | 0 failures |
| Fiabilidad online | crítica | Relay/host sin pérdida ni desync | `e2e_net`, `test_relay`, `test_host`, `test_ladder` | 0 desyncs en tests |
| Usabilidad | alta | UI legible y navegable | `_smoke`, capturas por tema/resolución | usable a 800×600 |
| Mantenibilidad | alta | Facción/carta nueva = datos, no código | ADR-001, gdlint en CI | sin lógica de piezas en código |
| Rendimiento | media | 60 fps en partida | tests de carga (`test_load`) | turno < 1 s |
| Recuperación | alta | Saves íntegros ante crash | atomic_write + `.bak` + drill en tests | 0 saves corruptos |

## Presupuestos (comprobables)

```yaml
budgets:
  test_all_exit: 0            # tools/test_all.sh completo
  save_recoverable: true      # .bak automático
  min_window: 800x600         # sección dedicada del README
```

## Lo que deliberadamente NO se persigue

Microservicios, i18n extensa, telemetría — ver MATURITY.md y
TECH_DEBT.md (bus factor aceptado y documentado).
