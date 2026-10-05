# Registro de riesgos

Complemento de THREAT_MODEL.md: allí están las amenazas y sus
controles; aquí el riesgo residual **aceptado formalmente** y su
justificación. Exposición = probabilidad × impacto (baja/media/alta).

| ID | Riesgo | Cat. | Exp. | Mitigación aplicada | Residual aceptado |
|---|---|---|---|---|---|
| R-1 | Suplantación de pid para falsear ELO | seguridad | media | token de identidad por pid + `id_err` → invitado | token robado localmente = suplantación real (aceptado: el jugador protege su PC) |
| R-2 | `ws://` plano en LAN expone el token en tránsito | seguridad | baja | `wss://` soportado vía BELIBER_TLS_* | en LAN de confianza la ventana es mínima; para internet wss es obligatorio (documentado) |
| R-3 | Flood al host agota sockets | disponibilidad | media | caps: 512 conns / 500 salas / 32 pkt/iter / 64 KB / handshake 5 s / TTL 4 h | un botnet real tira el host — autoalojado no aspira a resistir DDoS |
| R-4 | Desync entre peers del relay | integridad | media | cliente recalcula con match_legal, jamás aplica mv remoto | divergencia de versiones de motor sigue pudiendo desync — mitigado por SemVer en releases |
| R-5 | Corrupción de saves/ratings | datos | baja | atomic_write + `.bak` + recuperación automática en load_json + test | pérdida total si ambos ficheros mueren — backup del user:// es del usuario |
| R-6 | Arte/licencias de terceros | legal | baja | glifos Unicode (libres) + icono generado | las hojas escaneadas en `tools/` son propiedad del diseñador — el código es MIT, el reglamento es del usuario |
| R-7 | Dependencia `websockets` con CVE | cadena | baja | pineada + pip-audit en CI + dependabot | esperar al fix upstream |
| R-8 | Bots con semilla repetible | juego | — | `BELIBER_SEED` es feature de test, no bug | — |
| R-9 | El operador del host manipula el ladder | confianza | media | ratings.json legible; el operador ES el árbitro | aceptado por diseño: el host es de quien lo corre; un ladder público necesitaría servidor central firmado |
| R-10 | Build no reproducible bit-a-bit | cadena | baja | export presets fijados + attestation SLSA | el pck de Godot no es determinista; el checksum verifica el artefacto publicado, no reconstrucción |

## Revisión

Por release o tras cualquier incidente: reevaluar exposición y
actualizar la tabla. Un riesgo que cambia de categoría sin mitigación
nueva es un hallazgo, no un olvido.
