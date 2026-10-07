# Gobernanza técnica

Proyecto personal de código abierto — una sola persona ejerce todos
los roles. Este documento hace explícitas las políticas para que el
proyecto no dependa de memoria.

## Roles y responsabilidades

| Rol | Quién | Dónde se ejerce |
| --- | --- | --- |
| Producto / visión | mantenedor | COMO_FUNCIONA.md, REQUIREMENTS.md |
| Arquitectura | mantenedor | ADRs en docs/decisions/ |
| Repositorio / releases | mantenedor | CODEOWNERS, tools/release.ps1 |
| Seguridad | mantenedor | SECURITY.md, THREAT_MODEL.md, scorecard |
| Calidad | CI + mantenedor | tools/test_all, gdlintrc, run_tests |
| Incidentes | mantenedor | docs/operations/incidents.md |

Bus factor = 1. Aceptado (ver TECH_DEBT.md). Mitigación parcial:
toda decisión está en un ADR o en comentario junto al código.

## Políticas

- **Versionado**: SemVer sobre el protocolo + saves. PATCH =
  bugfix/hardening; MINOR = feature compatible; MAJOR = protocolo o
  save incompatible. `config/version` es la única fuente
  (`tools/release.ps1` la propaga a `host.VERSION`).
- **Compatibilidad**: dentro de una major, save `v:N` y protocolo
  deben interoperar. Un cambio incompatible requiere major + nota en
  CHANGELOG + entrada en `docs/decisions/`.
- **Deprecación**: campos de protocolo marcados primero en
  PROTOCOL.md, se retiran en la siguiente major. Nunca se borra un
  campo que un peer viejo pueda enviar sin tolerarlo.
- **Dependencias**: docs/DEPENDENCIES.md — sin nuevas deps sin
  justificación; lockfile pineado; dependabot semanal; pip-audit
  bloquea.
- **Secretos**: nunca en el repo ni en logs (gitleaks + pre-commit
  hook); idtokens vive solo en el host.
- **Datos**: PRIVACY.md — minimización; lo que no existe no se
  protege (sin cuentas, sin emails, sin IPs persistidas).
- **Soporte**: best-effort vía issues; sin SLA. El código se
  licencia MIT sin garantía.
- **Excepciones**: cualquier desviación de estas políticas va
  documentada en TECH_DEBT.md con su riesgo.

## Definition of Done

Un cambio está hecho cuando:

- El requisito/resuelto queda en un test (regresión permanente).
- `tools/test_all.ps1` pasa entero.
- gdlint + bandit limpios (pre-commit hook o CI).
- Si toca protocolo: PROTOCOL.md actualizado + ambos lados
  toleran la versión vieja.
- Si toca persistencia: la recuperación `.bak` sigue intacta.
- CHANGELOG `[Unreleased]` recoge el cambio si es visible.
- La documentación afectada se actualizó en el mismo commit.

## Definition of Ready

Antes de implementar una feature:

- Está claro qué regla de diseño la gobierna (las hojas de
  COMO_FUNCIONA o un ADR nuevo si es feature propia).
- Se conoce qué test la verificará.
- No rompe compatibilidad sin justificación.
