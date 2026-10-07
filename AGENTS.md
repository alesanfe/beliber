# AGENTS.md — Beliber

## Contexto

Ajedrez asimétrico hecho en Godot 4 (`game/`) con relay de red en Python
(`server/`). Las reglas completas (leyenda + facciones) están en
`docs/COMO_FUNCIONA.md` y la comparativa con la competencia en
`docs/COMPETENCIA.md`.

## Comandos

```bash
godot --path game                                          # jugar (o F5 en el editor)
godot --headless --path game -s res://tests/run_tests.gd   # motor + regresiones
godot --headless --path game -s res://tests/playthrough.gd # partidas bot-vs-bot
godot --headless --path game -s res://tests/_smoke.gd      # smoke de UI
godot --headless --path game -s res://tests/e2e.gd         # partida por clicks

python server/relay.py                                     # relay :7778
godot --headless --path game -s res://server/host.gd -- 7779  # host autoritativo
python server/test_relay.py && python server/test_host.py && python server/test_ladder.py
godot --headless --path game -s res://tests/e2e_net.gd     # 2 clientes x relay

# Capturas de UI
godot --path game -s res://tools/screenshots.gd -- [nombre ...]  # subset opcional

# Aislar datos en tests: BELIBER_CFG, BELIBER_SAVE (ver game/README.md)
```

## Estructura

```text
game/       # proyecto Godot
#   src/core/   # motor, datos, red y servicios (RefCounted/Node)
#   src/ui/     # pantallas, widgets, tema y arte (Control)
#   src/main.gd # entrypoint (único script referenciado por ruta)
#   scenes/ tests/ i18n/ tools/
server/     # relay.py + PROTOCOL.md + tests Python
tools/      # test_all, release, sprite-pipeline/ (extracción de sprites)
docs/       # COMO_FUNCIONA, COMPETENCIA, DEPENDENCIES, decisiones, assets
builds/     # salidas de release (gitignored)
```

## Reglas del proyecto

- **Tema**: todo el chrome de UI usa `game/src/ui/theme.gd` (`BeliberTheme`) —
  nunca colores fijos en widgets; variantes dark/light/contrast conmutables
  (`ui.skin` en `BELIBER_CFG`). Los colores de piezas/tablero son arte de
  juego y sí pueden ser literales.
- **Widgets**: usar `game/src/ui/widgets.gd` (`Widgets.primary`, `.lbl`,
  `.heading`…) en vez de construir botones/etiquetas ad hoc.
- **i18n**: textos de UI en `game/i18n/ui.csv` → regenerar `.translation`
  en el editor tras cada cambio.
- Los `IMG-*.jpg` de `tools/sprite-pipeline/` son las hojas escaneadas
  fuente del pipeline de sprites — no borrar.

## Verificación

- `tools/test_all.sh` (o `.ps1`) — batería completa.
- Los avisos WASAPI/audio en headless son del entorno, no fallos de UI.
