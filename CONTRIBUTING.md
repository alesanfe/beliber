# Contribuir a Beliber

## Antes de codear

1. Lee `COMO_FUNCIONA.md` — las reglas son la fuente de verdad (hojas de
   diseño escaneadas en la raíz y `tools/crops/`).
2. Lee `server/PROTOCOL.md` si tocas red.
3. Convención del repo: comentarios explican **el porqué**, no el qué; en
   español; tabs en GDScript; estilo compacto.

## Ejecutar tests

Todo cambio debe dejar la batería en verde:

```
godot --headless --path game -s res://tests/run_tests.gd
godot --headless --path game -s res://tests/playthrough.gd
godot --headless --path game -s res://tests/_smoke.gd
godot --headless --path game -s res://tests/e2e.gd
python server/test_relay.py    # con `python server/relay.py` corriendo
python server/test_host.py     # con el host corriendo (:7779)
python server/test_ladder.py
godot --headless --path game -s res://tests/e2e_net.gd
```

- Bugfix del motor → añade regresión en `tests/run_tests.gd`.
- Bugfix de red → añade caso al `test_*.py` correspondiente.
- Los tests están aislados del perfil real (`StatsStore.disabled` + env
  `BELIBER_*`); no los desactives.

## Piezas y ejércitos

El contenido es data-driven: no hace falta tocar código para crear piezas
(piece_editor) ni despliegues (army_builder) — pero los cambios de datos
oficiales van en `pieces_data.gd` y deben reflejar las hojas de diseño.

## Red

Si tocas el protocolo: actualiza `server/PROTOCOL.md` **y** ambos lados
(cliente `net_client.gd`, relay `relay.py` / host `server/host.gd`), y
mantén la regla de oro del relay: *el cliente nunca aplica campos de
efecto remotos; solo casa `from`/`to` contra sus legales*.

## PRs

Un tema por PR, mensaje explicando el porqué. La CI ejecuta la batería
completa (ver `.github/workflows/ci.yml`).

## Versionado

Tags SemVer en `main`: `vMAJOR.MINOR.PATCH`.

- **MAJOR**: cambio incompatible de protocolo (PROTOCOL.md), de
  formato de save (`"v"` en el JSON) o de BEL-FEN.
- **MINOR**: funcionalidad nueva compatible (modos, facciones, piezas
  oficiales).
- **PATCH**: bugfixes y hardening sin cambio de superficie.

Cada release lleva entrada en `CHANGELOG.md` (Keep a Changelog).
