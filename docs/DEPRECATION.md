# Política de ciclo de vida y retirada

## Estados de un componente/feature

`propuesto → experimental → beta → estable → deprecado → fuera de soporte → eliminado`

| Estado | Significado | Compromiso |
|---|---|---|
| propuesto | idea/ADR sin código | ninguno |
| experimental | funciona pero sin garantías | puede romperse sin aviso |
| beta | usable, puede cambiar | aviso en CHANGELOG si rompe |
| estable | feature completa | compatibilidad + tests obligatorios |
| deprecado | sigue funcionando, hay alternativa | fecha de retirada anunciada |
| fuera de soporte | no se corrige | solo eliminación pendiente |
| eliminado | código, assets y docs fuera | — |

## Contratos concretos

- **BEL-FEN**: la notación de posición es formato de intercambio — los
  saves viejos deben seguir cargando; el versionado de save (`v:1`)
  permite migración perezosa.
- **Protocolo de red**: `server/PROTOCOL.md` versionado — un cambio
  incompatible exige versión nueva coexistiendo, nunca romper en seco.
- **Definiciones de piezas/facciones**: data-driven (ADR-001) — retirar
  una pieza no puede romper replays ni saves que la referencien.

## Retirar una feature

1. Identificar consumidores (saves, replays, builds publicadas).
2. Anuncio en `CHANGELOG.md` + advertencia si la feature es visible.
3. Alternativa documentada con fecha de retirada.
4. Retirar código + assets + tests + docs.
