# ADR-003: Persistencia atómica + overrides por env para aislar tests

## Contexto

La app guarda config, partidas, stats XP/rush, ratings del ladder y
tokens de identidad en `user://`. Dos riesgos reales observados:

1. Escritura directa → un crash/corte a mitad corrompía el save.
2. Los tests de red tocan ratings/tokens → contaminaban el perfil
   real del usuario en `app_userdata`.

## Decisión

- `atomic_write()` para todo save stateful: fichero temporal +
  `rename`, con fallback a escritura directa si rename falla
  (Windows con archivo abierto).
- Saves versionados (`"v": 1`); versiones desconocidas se rechazan.
- Todas las rutas son override por variables de entorno:
  `BELIBER_CFG`, `BELIBER_SAVE`, `BELIBER_EXPORT`,
  `BELIBER_RATINGS`, `BELIBER_TOKENS`. Los tests las redirigen a
  `%TEMP%` y `StatsStore.disabled` corta escrituras de stats.

## Alternativas

- SQLite para stats: sobredimensionado para dicts JSON pequeños y
  añade un SDB binding de más.
- Snapshot de `pos_counts` entero en saves: elegido al revés — se
  guarda el log y se **recalcula** al cargar, evitando doble conteo
  (bug encontrado y fijado en la auditoría).

## Consecuencias

+ Tests 100% aislados del perfil real (CI en máquina limpia es igual
  que local).
+ Un crash durante save deja como mucho el fichero anterior íntegro.
- Cada env nuevo debe añadirse a la tabla en `game/README.md` —
  documentación, no autodescubrimiento.
