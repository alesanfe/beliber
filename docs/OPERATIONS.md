# Operaciones — Beliber

Superficie operativa de una instancia desplegada. El detalle vive en
[`operations/`](operations/).

## Comandos habituales

```bash
python server/relay.py                                       # relay :7778
godot --headless --path game -s res://server/host.gd -- 7779 # host autoritativo
tools/test_all.sh                                            # batería completa
tools/release.ps1 <version>                                  # empaquetado
```

## Documentos

| Doc | Contenido |
|---|---|
| [operations/incidents.md](operations/incidents.md) | Respuesta a incidentes y severidades |
| [operations/runbook.md](operations/runbook.md) | Procedimientos de despliegue y operación |
| [operations/slo.md](operations/slo.md) | Objetivos de servicio del relay/comunidad |

## Notas

- El juego funciona offline; el relay es opt-in y autoalojable.
- Sin telemetría: la operación es del todo local al operador.
