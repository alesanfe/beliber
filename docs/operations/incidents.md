# Respuesta a incidentes

## Severidades

| Sev | Ejemplo | Respuesta |
| --- | --- | --- |
| S1 | Token leak publicado, exploit que suplanta pids, host down total | inmediata: contención primero, análisis después |
| S2 | Corrupción de ratings, desync reproducible, crash del host bajo input | mismo día |
| S3 | Bug de reglas, pérdida de un mensaje, glitch visual | backlog priorizado |

## Contención por tipo

- **Fuga de `beliber_idtokens.json`**: regenerar el fichero entero
  (los pids vuelven a pedir `id_tok` — los nicks y ELO se conservan).
- **Host bajo flood**: los caps ya actúan; si no basta, reiniciar el
  proceso (salas en curso se pierden — el ladder sobrevive).
- **Save corrupto**: el `.bak` es la última versión buena; copiar
  encima del JSON principal.
- **Desync online**: pedir a ambos clientes el `moves` del `resync`;
  comparar contra el archivo de la sala en el host.

## Procedimiento

1. **Detectar**: heartbeat/health check (runbook.md), reporte de
   usuario, o `sec:` en logs.
2. **Contener**: reinicio del proceso, bloqueo de la versión en
   releases, regeneración de credenciales.
3. **Diagnosticar**: reproducir contra la suite (añadir regresión
   ANTES de corregir — ver CONTRIBUTING).
4. **Corregir + etiquetar**: PATCH si es bugfix; documentar en
   CHANGELOG `[Unreleased]`.
5. **Postmortem corto**: qué señal lo detectó, qué señal faltó.
   Si el bug era detectable por test → la regresión queda en la
   suite para siempre.

## Divulgación de vulnerabilidades

Los reportes van por el canal de `SECURITY.md`. Reconocer en 72 h,
fix publicado con changelog y tag; el reportante se acredita salvo
que pida lo contrario. No hay recompensa (proyecto sin financiación).
