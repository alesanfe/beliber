# Beliber — Proyecto Godot

Prototipo jugable del ajedrez asimétrico **Beliber** (ver `../docs/COMO_FUNCIONA.md`).

## Ejecutar

1. Instala **Godot 4.2+** (probado con 4.7.2): <https://godotengine.org/download>
2. Abre `project.godot` con el editor, o ejecuta:

   ```text
   godot --path game
   ```

## Multijugador

- **LAN directa** (ENet): Menú → Online → pestaña LAN; puerto 7777.
- **Salas por código** (relay Python, WebSocket):

  ```text
  python server/relay.py            # 0.0.0.0:7778
  ```

- **Servidor autoritativo** (Godot, valida jugadas + reloj + ladder):

  ```text
  godot --headless --path game -s res://server/host.gd -- 7779
  ```

- Tablas online = oferta → aceptar/rechazar (no cierre unilateral).
- El protocolo completo (ops, `cfg` efectiva, modelo de confianza) está
  documentado en `server/PROTOCOL.md`.

## Tests del motor

```text
godot --headless --path game -s res://tests/run_tests.gd
```

Cubren despliegue, movimientos base, salto, doble apertura Humenex,
orden Elfos, empujar, atravesar+inmovilizar, Consorte, victoria por
líderes, BEL-FEN (bueno y corrupto), save/load, undo tras el fin,
enroque vía `castle_partner` y cadena del Tritón.

Tests de red (requieren el servidor correspondiente):

```text
python server/test_relay.py    # relay WS (guards, rejoin, resync)
python server/test_host.py     # host autoritativo (queue, resync)
python server/test_ladder.py   # ladder/ratings
```

Para no contaminar tus datos reales al probar:

- Los tests Godot (`e2e`, `_smoke`) ya se aíslan solos
  (`StatsStore.disabled` + `BELIBER_*` env).
- El host acepta `BELIBER_RATINGS` / `BELIBER_TOKENS` (rutas
  alternativas para ratings/tokens — úsalo al lanzar host.gd para los
  tests) y `BELIBER_TLS_CERT` + `BELIBER_TLS_KEY` (PEM → sirve `wss://`).
- El cliente acepta `BELIBER_CFG` / `BELIBER_SAVE` / `BELIBER_EXPORT`
  para redirigir los archivos `user://`, y `BELIBER_TLS_INSECURE=1`
  para saltar la validación de cert al usar `wss://` autofirmado.
- Todas las escrituras (`stats`, `ratings`, `tokens`, saves) son
  atómicas y dejan `.bak` con la última versión buena.

## Estructura

```text
game/
├── project.godot
├── scenes/main.tscn        # escena raíz (un Control con src/main.gd)
├── src/
│   ├── main.gd               # controlador raíz: menú, pantallas, red, run
│   ├── core/                 # motor, datos, red y servicios (sin Control)
│   │   ├── pieces_data.gd    # ⭐ TODAS las piezas y facciones como datos
│   │   ├── board_state.gd    # estado 8x8, despliegue, aplicar movimientos
│   │   ├── move_gen.gd       # generador de movimientos legales
│   │   ├── turn_manager.gd   # turnos, reglas, victoria, save/load, BEL-FEN
│   │   ├── bot.gd            # IA minimax con personalidades y niveles
│   │   ├── net_client.gd     # cliente WebSocket (dispatch, resync, cfg)
│   │   ├── net_codec.gd      # serialización Vector2i ↔ {x,y}
│   │   ├── stats_store.gd    # persistencia de stats + escritura atómica
│   │   ├── lang.gd           # i18n (ui.csv → .translation)
│   │   ├── tts.gd            # lector de pantalla (accesibilidad)
│   │   └── sfx.gd            # audio sintetizado
│   └── ui/                   # pantallas, widgets, tema y arte (Control)
│       ├── menu_screen.gd    # menú principal (facciones, modos, ajustes)
│       ├── online_screen.gd  # lobby online (ENet/relay/host, ladder, chat)
│       ├── board_view.gd     # tablero dibujado + input + highlights
│       ├── game_hud.gd       # panel lateral, lista de jugadas, bandejas
│       ├── piece_editor.gd   # editor de piezas (celdas, leg2, overrides)
│       ├── army_builder.gd   # constructor de ejércitos con presupuesto
│       ├── pos_editor.gd     # editor de posición libre (BEL-FEN)
│       ├── puzzles.gd        # puzzles, desafío diario, modo rush
│       ├── draft.gd          # draft de piezas estilo CEO
│       ├── postgame.gd       # resumen/análisis post-partida
│       ├── profile_screen.gd # perfil, estadísticas, logros
│       ├── guide.gd          # guía interactiva / tutorial
│       ├── fx.gd             # constantes de efectos + colores de leyenda
│       ├── theme.gd          # BeliberTheme (dark/light/contrast)
│       └── widgets.gd,juice.gd,icons.gd,piece_art.gd… # helpers UI
├── server/host.gd        # árbitro autoritativo (ws://:7779, ladder)
└── tests/                # run_tests, e2e, e2e_net, playthrough, _smoke
```

## Cómo se define una pieza

Cada pieza es un **mapa de casillas** — literalmente el diagrama de la hoja
de referencia—: un diccionario `"dx,dy" -> código de color`. En
`pieces_data.gd`:

```gdscript
# Peón Humenex: avanza 1 (m), despliegue a 2 (d), captura diagonal/al paso (E)
_pc("P", "Peón", 1, _cells([
    [Vector2i(0, -1), "m"], [Vector2i(0, -2), "d"],
    [Vector2i(-1, -1), "E"], [Vector2i(1, -1), "E"],
]), {"sym": "lit"})
```

- Códigos = letras por cada color de la leyenda (`m` amarillo, `c` rojo,
  `o` naranja, `J` morado, `p` teal, `e` azul, `q` marrón… 19 en total,
  ver `PiecesData.CODE_NAMES`).
- `sym = "all"` expande el patrón a las 8 direcciones (lo normal);
  `sym = "lit"` aplica el patrón literal (solo girado para J2), para
  piezas direccionales como los básicos.
- Celdas contiguas alineadas = deslizamiento; celda aislada o no alineada
  = salto. Cada celda conserva su propio efecto.

## Editor de piezas

Menú → **Editor de piezas**. Permite:

- Elegir facción y pieza, pintar celdas con la paleta de la leyenda.
- Reubicar la pieza en el diagrama (clic con "Reubicar pieza").
- Editar nombre, valor, simetría, líder, robo de movimientos,
  pareja de enroque y **segundo tramo encadenado** (leg2, Tritón).
- **Vista previa real**: el motor calcula movimientos legales sobre un
  tablero de prueba con enemigos/aliados dummy.
- Guardar → `user://beliber_pieces.json` (sobreescribe al instante);
  "Restaurar" borra el override de esa pieza.

Los patrones por defecto son mi transcripción de los diagramas; el editor
sirve para corregirlos casilla a casilla sin tocar código.

## Estado / provisional

- ✅ Motor completo: mover, capturar, saltar, atravesar (+inmovilizar),
  empujar (arrolla enemigos), atraer, al paso, despliegue, enroque,
  Salto de Aquonte, cadena del Tritón, Consorte, doble líder Bestiarios,
  orden Humenex/Elfos, doble apertura.
- ✅ **Despliegues Eq1/Eq2 transcritos de las hojas** (formaciones
  dispersas de ~5 filas, no filas de ajedrez).
- ✅ Hotseat 2 jugadores con selección de facción y Eq1/Eq2/Personalizado.
- ✅ Highlights coloreados con la paleta oficial de la leyenda.
- ✅ Editor visual de piezas con persistencia JSON.
- ✅ **Funcionalidades de la competencia** (ver `../docs/COMPETENCIA.md`):
  - Valor de ejército por facción en el menú (equilibrio estilo Betza).
  - Material vivo en el HUD.
  - Mapa de cobertura alternable (estilo Chess Evolved Online).
  - Invasión de línea opcional (Chess 2): líder en última fila gana.
  - Anti-estancamiento opcional: N turnos sin captura → material decide.
  - Constructor de ejército con presupuesto de puntos (CEO): se guarda
    como equipo "Personalizado".
- ✅ IA minimax con niveles y personalidades (`bot.gd`), sonido
  (`sfx.gd`), animaciones/toasts (`juice.gd`), puzzles + desafío
  diario + rush, draft, modo Run, análisis post-partida, estadísticas
  y logros, guía interactiva.
- ✅ Online: ENet (LAN), relay WebSocket no autoritativo (:7778) y host
  autoritativo con rejoin/resync/ladder (:7779) — ver
  `server/PROTOCOL.md`.
- ⚠️ Algunos glifos góticos del manual son ambiguos; los despliegues se
  transcribieron letra a letra, pendiente verificación visual.
- 🔜 Arte final (sprites/animación dedicada) y empaquetado.
