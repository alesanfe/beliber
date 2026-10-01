# Matriz de madurez — autoevaluación Beliber

Escala 0-4 por dimensión (0=implícito … 4=medido/evolutivo).
Revisar por release. La puntuación NO sustituye al análisis de
riesgos — un 4 medio con un fallo crítico abierto sigue siendo un
proyecto con un fallo crítico abierto.

| Dimensión | Nivel | Evidencia |
|---|---|---|
| Requisitos | 3 | `docs/REQUIREMENTS.md`: 22 reqs con ID + trazabilidad a tests |
| Arquitectura | 3 | `docs/ARCHITECTURE.md` + 3 ADRs; límites de confianza explícitos (host autoritativo / relay / cliente) |
| Pruebas | 3 | 9 suites automatizadas por riesgo (motor, red, e2e, carga, recuperación `.bak`, regresiones del audit) |
| Seguridad | 3 | threat model, tokens, TLS real, clamps, bandit+gdlint+gitleaks en CI, `sec:` log |
| Despliegue | 3 | export presets commiteados + release.yml (build, SHA256, SBOM, attestation) + `tools/release.ps1` |
| Operación | 2 | `ping/pong`+`v`, heartbeat 60 s, runbook + SLO + INCIDENTS — sin dashboards externos (host = proceso único) |
| Recuperación | 3 | atomic_write + `.bak` con **recuperación automática** (load_json) + drill en test_ladder/run_tests |
| Documentación | 3 | 15 docs indexados desde README; contrato de protocolo versionado |
| Datos | 3 | `DATA_MODEL.md` con esquemas + propietarios; versionado de save (`v:1`); restore probado |
| Equipo | 1 | mantenedor único — bus factor = 1 (riesgo aceptado y documentado en TECH_DEBT) |
| **Total** | **30/40** | **proyecto profesional mantenible** (23-30) |

## Qué falta para subir

- Operación →3 exige un dashboard/monitor externo (overkill para
  self-host; queda proporcional).
- Equipo →2 exige un segundo mantenedor — no es un cambio de repo.
- Seguridad →4 exige pentest/revisión independiente.

## Lo que deliberadamente NO se busca

Microservicios, orquestación, HA, feature flags, i18n (español único
por diseño, listado como deuda). Un juego indie autoalojado no se
beneficia de la maquinaria — el checklist advierte contra añadir
capas que nadie usa.
