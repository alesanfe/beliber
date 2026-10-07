# Registro de deuda técnica

Deudas **conscientes**: decisiones tomadas a sabiendas de su coste.
Cada entrada indica riesgo, coste de no corregir y plan. Revisar por
release.

| ID | Deuda | Tipo | Riesgo | Plan |
| --- | --- | --- | --- | --- |
| TD-1 | Glifos de ajedrez Unicode como piezas | UX/arte | aspecto amateur; ambigüedad en piezas parecidas | sprites por facción (las hojas de `tools/` son la referencia) — bloqueado por arte, no por código |
| TD-2 | Textos hardcodeados en español | i18n | no localizable | si crece el público → extraer a CSV/PO de Godot |
| TD-3 | Relay Python + host GDScript = 2 implementaciones de sala | arquitectura | divergencia de comportamiento (tests distintos) | el relay ya es solo retransmisión; si el host madura, jubilar el relay |
| TD-4 | Sin firma de binarios en releases | seguridad/cadena | un exe tampered es indetectable por el usuario | certificado de editor = compra externa; mitigado por SHA256+attestation en release.yml |
| TD-5 | ELO local no verificable por terceros | integridad | el operador del host puede editar ratings.json | aceptado: es su ladder; documentado en THREAT_MODEL |
| TD-6 | Bus factor = 1 | personas | si el mantenedor desaparece, el proyecto se congela | mitigado por documentación densa + ADRs; sin solución de repo |
| TD-7 | Chat de sala sin moderación | operación | spam/toxicidad en salas públicas | self-hosted: el operador echa a quien quiera; un host público grande necesitaría moderación |
| TD-8 | Sin coverage % medido (GDScript no tiene herramienta estándar) | testing | cobertura por criterio, no por número | las regresiones cubren cada bug encontrado; medible solo por review |
| TD-9 | `main.gd` ~1200 líneas | mantenibilidad | el controlador raíz concentra mucho | ya se separaron screens/widgets/hud; siguiente corte: extraer lobby/draft a nodos propios si crece |
| TD-10 | Icono generado por script, no arte | UX | suficiente para release; bajo para store | reemplazar cuando haya arte final |

## Regla

Toda excepción a una política de GOVERNANCE.md se registra aquí con
su justificación. Una deuda sin entrada = un bug oculto.
